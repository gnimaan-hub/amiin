# -*- coding: utf-8 -*-
"""
scraper_douanes.py - Amiin Project (v2 corrigé)
Scrape et indexe le contenu du site des Douanes de Djibouti (douanes.gouv.dj).
Gère les pages HTML et les PDFs.
Titres de chunks enrichis (extrait du contenu pour les parties > 1).

Exclusions explicites :
- /tarifs/ (énorme tableau des tarifs)
- Les pages mensuelles de structure des prix (si elles n'ont pas de contenu)
- Les fichiers binaires (.exe, .jnlp)

Usage:
  python scraper_douanes.py --dry-run        # Test sans ingestion
  python scraper_douanes.py                  # Exécution complète
  python scraper_douanes.py --pdf-only       # Télécharge et indexe les PDFs seulement (pas les pages)
  python scraper_douanes.py --pages-only     # Pages seulement, ignore les PDFs
"""

import argparse
import re
import time
import os
import requests
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup
from collections import Counter
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
import warnings
from bs4 import XMLParsedAsHTMLWarning
warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)

# Configuration
DB_PATH    = './amiin_db'
COLLECTION = 'djibouti_knowledge'
MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2'

MAX_MOTS   = 480
OVERLAP    = 50
DOWNLOAD_PDF_DIR = './pdfs_douanes'

HEADERS = {
    'User-Agent': 'Amiin-Bot/1.0 (Educational Djibouti Knowledge Base)'
}

# ============================================================================
# EXCLUSIONS (URLs ou motifs à ignorer)
# ============================================================================

EXCLUDED_URL_PATTERNS = [
    r'/tarifs/$',                # page énorme de 125k mots
    r'/tarifs/?$',
    r'/202[0-9]/[0-9]{2}/[0-9]{2}/$',  # archives journalières sans contenu réel
    r'/sw/outliers/',            # fichiers binaires
    r'\.exe$', r'\.jnlp$',       # fichiers exécutables
    r'/vehicule-simulation$',    # page sans contenu
    r'/declaration_d_especes/$', # page vide
    r'/edition-speciale-celebration.*$',   # certaines pages d'édition n'ont que 19 mots
    r'/journee-internationale-des-douanes-immersion.*$', # vidéo uniquement
    r'/le-premier-ministre-rend-hommage.*$',
    r'/celebration-de-la-journee-mondiale.*$',
]

def url_exclue(url):
    """Retourne True si l'URL doit être ignorée."""
    for pattern in EXCLUDED_URL_PATTERNS:
        if re.search(pattern, url):
            return True
    return False

# ============================================================================
# UTILITAIRES
# ============================================================================

def nettoyer_texte(texte):
    texte = re.sub(r'\[\d+\]', '', texte)
    texte = re.sub(r'\[réf\.\s*nécessaire\]', '', texte)
    texte = re.sub(r'\n{3,}', '\n\n', texte)
    texte = re.sub(r' {2,}', ' ', texte)
    texte = re.sub(r'↑\s*\d+', '', texte)
    return texte.strip()

def generer_titre_chunk(texte_chunk, titre_base, num_part):
    if num_part == 1:
        return titre_base
    mots = texte_chunk.split()
    if not mots:
        return f"{titre_base} (suite)"
    extrait = ' '.join(mots[:10])
    extrait = extrait.replace('\n', ' ').strip()
    if len(extrait) > 80:
        extrait = extrait[:77] + "..."
    return f"{titre_base} : {extrait}"

def decouper_texte(texte, titre_base, source, category, url, prefix_id, extra_meta=None):
    mots = texte.split()
    if not mots:
        return []
    chunks = []
    i = 0
    part = 0
    while i < len(mots):
        fin = min(i + MAX_MOTS, len(mots))
        sous_texte = ' '.join(mots[i:fin])
        part += 1
        titre_chunk = generer_titre_chunk(sous_texte, titre_base, part)
        meta = {
            'title': titre_chunk,
            'category': category,
            'source': source,
            'url': url,
            'type': 'scrape_douanes',
        }
        if extra_meta:
            meta.update(extra_meta)
        chunks.append({
            'id': f"{prefix_id}_{part:03d}",
            'document': sous_texte,
            'metadata': meta
        })
        i = fin - OVERLAP if fin < len(mots) else fin
    return chunks

def telecharger_pdf(url, save_dir):
    if not url.startswith(('http://', 'https://')):
        return None
    os.makedirs(save_dir, exist_ok=True)
    filename = os.path.basename(urlparse(url).path)
    if not filename.endswith('.pdf'):
        filename += '.pdf'
    if len(filename) > 100:
        filename = filename[-100:]
    filepath = os.path.join(save_dir, filename)
    if os.path.exists(filepath):
        return filepath
    try:
        resp = requests.get(url, headers=HEADERS, timeout=20)
        resp.raise_for_status()
        with open(filepath, 'wb') as f:
            f.write(resp.content)
        return filepath
    except Exception as e:
        print(f"    ❌ Échec téléchargement PDF {url}: {e}")
        return None

def extraire_texte_pdf(filepath):
    try:
        texte = ""
        with pdfplumber.open(filepath) as pdf:
            for page in pdf.pages:
                page_text = page.extract_text()
                if page_text:
                    texte += page_text + "\n"
        return nettoyer_texte(texte)
    except Exception as e:
        print(f"    ❌ Erreur extraction PDF {filepath}: {e}")
        return ""

# ============================================================================
# EXTRACTION DES URLS
# ============================================================================

def extraire_urls_depuis_menu(base_url):
    try:
        resp = requests.get(base_url, headers=HEADERS, timeout=15)
        resp.encoding = 'utf-8'
        soup = BeautifulSoup(resp.text, 'html.parser')
    except Exception as e:
        print(f"  ❌ Erreur accès page d'accueil : {e}")
        return set()

    urls = set()
    nav = soup.find('div', id='primary-nav')
    if nav:
        for a in nav.find_all('a', href=True):
            href = a['href']
            if href.startswith('/'):
                full = urljoin(base_url, href)
                urls.add(full)
            elif base_url in href:
                urls.add(href)

    # Sections explicites
    sections = [
        '/voyageurs/', '/prohibitions-et-restrictions/', '/colis-postaux/',
        '/mise-a-la-consommation/', '/regimes-economiques/', '/regime-exportation/',
        '/taxation-vehicules/', '/tarifs-des-douanes/', '/formulaires/',
        '/transit/', '/zone-franche/', '/exoneration/', '/admission-temporaire/',
        '/loi-de-finances/', '/lois-de-finances-initiales/', '/lois-de-finances-rectificatives/',
        '/lois-de-reglement/', '/code-des-douanes/', '/code-ethique/',
        '/charte-des-controles-douaniers/', '/structure-des-prix/', '/taux-de-change-2/',
        '/contact/', '/mot-du-directeur-general/', '/historique-de-la-douane/',
        '/les-missions-de-la-douane-de-djibouti/', '/organigramme-de-la-dgddi/',
        '/plan-strategique/', '/category/douanes/'
    ]
    for sec in sections:
        full = urljoin(base_url, sec)
        urls.add(full)

    # Ajout des catégories
    categories = ['douanes', 'contrebande', 'evenements', 'documentation',
                  'procedures-de-dedouanement', 'professionnels']
    for cat in categories:
        urls.add(urljoin(base_url, f'category/{cat}/'))

    # Nettoyer : enlever les fragments, les query params, et garder seulement le domaine
    cleaned = set()
    for u in urls:
        if not u.startswith(base_url):
            continue
        # enlever les paramètres ? et les #
        u = u.split('?')[0].split('#')[0]
        # s'assurer qu'il n'y a pas de double slash après domaine
        if u.endswith('/') or '.' not in u.split('/')[-1]:  # garder les pages sans extension
            cleaned.add(u)
    return cleaned

def extraire_urls_articles_depuis_page(url):
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        resp.encoding = 'utf-8'
        soup = BeautifulSoup(resp.text, 'html.parser')
    except Exception:
        return set()
    urls = set()
    for a in soup.find_all('a', href=True):
        href = a['href']
        if '/category/' in href:
            continue
        if '/page/' in href:
            continue
        if href.endswith('/') and 'douanes.gouv.dj' in href and '#' not in href:
            full = href.split('?')[0]
            if full.endswith('/') or '.' not in full.split('/')[-1]:
                urls.add(full)
    return urls

def collecter_toutes_les_urls(base_url):
    urls = extraire_urls_depuis_menu(base_url)
    print(f"  {len(urls)} URLs issues du menu principal et sections prédéfinies.")

    categories = ['douanes', 'contrebande', 'evenements', 'documentation',
                  'procedures-de-dedouanement', 'professionnels']
    for cat in categories:
        cat_url = urljoin(base_url, f'category/{cat}/')
        print(f"  Exploration catégorie : {cat_url}")
        art_urls = extraire_urls_articles_depuis_page(cat_url)
        urls.update(art_urls)
        print(f"    {len(art_urls)} articles trouvés.")

    # Filtrer les URLs exclues
    final_urls = {u for u in urls if not url_exclue(u)}
    # Enlever les URLs de fichiers binaires (exe, jnlp, etc.)
    final_urls = {u for u in final_urls if not u.endswith(('.exe', '.jnlp', '.dmg', '.sh'))}
    # Enlever les URLs qui ne sont pas des pages HTML
    final_urls = {u for u in final_urls if '/' in u.replace(base_url, '') and '.' not in u.split('/')[-1]}

    return final_urls

# ============================================================================
# EXTRACTION DU CONTENU
# ============================================================================

def extraire_contenu_page(soup, url):
    titre_tag = soup.find('h1')
    if not titre_tag:
        titre_tag = soup.find('title')
    titre = titre_tag.get_text(strip=True) if titre_tag else "Page sans titre"

    for element in soup.find_all(['header', 'footer', 'nav', 'script', 'style', 'noscript', 'iframe', 'aside']):
        element.decompose()

    content = None
    for cand in [soup.find('div', class_='content'),
                 soup.find('div', class_='entry-content'),
                 soup.find('div', class_='elementor-widget-container'),
                 soup.find('article'),
                 soup.find('main')]:
        if cand and cand.get_text(strip=True):
            content = cand
            break

    if content:
        texte = content.get_text(separator='\n', strip=True)
    else:
        body = soup.find('body')
        texte = body.get_text(separator='\n', strip=True) if body else ""

    texte = nettoyer_texte(texte)
    return titre, texte

def extraire_pdfs_depuis_page(soup, base_url):
    pdf_urls = set()
    for a in soup.find_all('a', href=True):
        href = a['href']
        if '.pdf' in href.lower():
            full = urljoin(base_url, href)
            pdf_urls.add(full)
    return pdf_urls

def determiner_categorie(titre, url):
    titre_lower = titre.lower()
    if any(k in titre_lower for k in ['douane', 'douanier', 'dédouanement', 'transit', 'zone franche', 'exonération', 'admission temporaire']):
        return 'administrative'
    if any(k in titre_lower for k in ['taxation', 'véhicule', 'tarif', 'valeur', 'marchandise', 'import', 'export']):
        return 'economie_commerce'
    if any(k in titre_lower for k in ['cannabis', 'cocaïne', 'drogue', 'contrebande', 'trafic', 'saisie']):
        return 'securite'
    if any(k in titre_lower for k in ['prohibition', 'restriction', 'interdiction']):
        return 'juridique'
    if any(k in titre_lower for k in ['historique', 'mission', 'vision', 'organigramme', 'plan stratégique']):
        return 'institution'
    if any(k in titre_lower for k in ['code', 'loi', 'décret', 'arrêté', 'circulaire']):
        return 'juridique'
    if 'voyageur' in titre_lower or 'bagage' in titre_lower:
        return 'transport'
    return 'general'

# ============================================================================
# SCRAPING PRINCIPAL
# ============================================================================

def scraper_douanes(only_pages=False, only_pdfs=False):
    base_url = "https://douanes.gouv.dj"
    print("\n🏛️ Scraping Direction Générale des Douanes de Djibouti...")

    print("  Récupération des URLs à explorer...")
    urls = collecter_toutes_les_urls(base_url)
    print(f"  {len(urls)} URLs uniques à traiter (après exclusions).")

    tous_chunks = []
    pdf_urls_global = set()

    for idx, url in enumerate(sorted(urls)):
        print(f"    [{idx+1}/{len(urls)}] {url}")
        try:
            resp = requests.get(url, headers=HEADERS, timeout=15)
            resp.encoding = 'utf-8'
            soup = BeautifulSoup(resp.text, 'html.parser')

            pdfs_page = extraire_pdfs_depuis_page(soup, base_url)
            pdf_urls_global.update(pdfs_page)

            if only_pdfs:
                continue

            titre, contenu = extraire_contenu_page(soup, url)
            if len(contenu.split()) < 50:
                print(f"      ⚠️ Contenu trop court ({len(contenu.split())} mots), ignoré.")
                continue

            slug = re.sub(r'[^a-z0-9]+', '_', titre.lower())[:40]
            prefix_id = f"douane_{slug}"
            category = determiner_categorie(titre, url)

            chunks = decouper_texte(
                contenu, titre,
                source="douanes.gouv.dj",
                category=category,
                url=url,
                prefix_id=prefix_id
            )
            tous_chunks.extend(chunks)
            print(f"      ✅ {len(contenu.split())} mots → {len(chunks)} chunks (cat: {category})")
            time.sleep(0.3)

        except Exception as e:
            print(f"      ❌ Erreur: {e}")

    if not only_pages:
        print(f"\n  📄 Traitement des PDFs ({len(pdf_urls_global)} fichiers trouvés)...")
        for pdf_url in pdf_urls_global:
            if not pdf_url.startswith('http'):
                pdf_url = urljoin(base_url, pdf_url)
            print(f"    {pdf_url}")
            local_path = telecharger_pdf(pdf_url, DOWNLOAD_PDF_DIR)
            if not local_path:
                continue
            texte_pdf = extraire_texte_pdf(local_path)
            if len(texte_pdf.split()) < 100:
                print(f"      ⚠️ PDF trop court ou illisible ({len(texte_pdf.split())} mots)")
                continue
            titre_pdf = os.path.basename(local_path).replace('.pdf', '').replace('_', ' ')
            titre_pdf = re.sub(r'\.(png|jpg|jpeg|gif)$', '', titre_pdf, flags=re.I)
            prefix_id = f"douane_pdf_{re.sub(r'[^a-z0-9]+', '_', titre_pdf.lower())[:30]}"
            category_pdf = determiner_categorie(titre_pdf, pdf_url)
            chunks_pdf = decouper_texte(
                texte_pdf, titre_pdf,
                source="douanes.gouv.dj (PDF)",
                category=category_pdf,
                url=pdf_url,
                prefix_id=prefix_id
            )
            tous_chunks.extend(chunks_pdf)
            print(f"      ✅ {len(texte_pdf.split())} mots → {len(chunks_pdf)} chunks (cat: {category_pdf})")
            time.sleep(0.2)

    print(f"  → Total chunks générés : {len(tous_chunks)}")
    return tous_chunks

# ============================================================================
# INGESTION
# ============================================================================

def supprimer_anciens(collection, source_tag):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == source_tag or meta.get('source', '').startswith('douanes.gouv.dj')]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"  {len(ids)} anciens chunks des Douanes supprimés")

def ingerer(chunks, collection, model):
    print(f"\n  Ingestion de {len(chunks)} chunks...")
    ingeres = doublons = 0
    for k, chunk in enumerate(chunks):
        emb = model.encode(chunk['document']).tolist()
        try:
            collection.upsert(
                ids=[chunk['id']],
                embeddings=[emb],
                documents=[chunk['document']],
                metadatas=[chunk['metadata']]
            )
            ingeres += 1
        except Exception:
            doublons += 1
        if (k + 1) % 50 == 0:
            print(f"    {k+1}/{len(chunks)}...")
    print(f"  ✅ Ingérés: {ingeres} | Doublons: {doublons}")
    return ingeres

def afficher_stats(chunks):
    mots_list = [len(c['document'].split()) for c in chunks]
    if not mots_list:
        return
    print(f"\n  Stats: {len(chunks)} chunks | Moy: {sum(mots_list)//len(mots_list)}m | "
          f"Min: {min(mots_list)}m | Max: {max(mots_list)}m")
    cats = Counter(c['metadata']['category'] for c in chunks)
    for cat, n in cats.most_common():
        print(f"    {cat:<25} {n}")

# ============================================================================
# MAIN
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description='Scraper Douanes de Djibouti v2')
    parser.add_argument('--dry-run', action='store_true', help="Affiche les stats sans ingestion")
    parser.add_argument('--pages-only', action='store_true', help="Scrape uniquement les pages HTML, ignore les PDFs")
    parser.add_argument('--pdf-only', action='store_true', help="Scrape uniquement les PDFs (pas les pages HTML)")
    args = parser.parse_args()

    print("=" * 65)
    print("SCRAPER DOUANES DE DJIBOUTI - AMIIN v2")
    print("=" * 65)

    only_pages = args.pages_only
    only_pdfs = args.pdf_only

    tous_chunks = scraper_douanes(only_pages=only_pages, only_pdfs=only_pdfs)

    if not tous_chunks:
        print("\n  Aucun chunk généré.")
        return

    afficher_stats(tous_chunks)

    if args.dry_run:
        print(f"\n  [DRY RUN] {len(tous_chunks)} chunks prêts. Aucune ingestion.")
        return

    print(f"\nChargement du modèle et connexion à ChromaDB...")
    model = SentenceTransformer(MODEL_NAME)
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(COLLECTION)
    count_before = collection.count()
    print(f"Base avant: {count_before} chunks")

    supprimer_anciens(collection, 'douanes.gouv.dj')

    nb = ingerer(tous_chunks, collection, model)

    count_after = collection.count()
    print(f"\n{'='*65}")
    print(f"TERMINÉ | {nb} chunks ingérés | Base: {count_before} → {count_after} ({count_after-count_before:+d})")
    print(f"{'='*65}")

if __name__ == '__main__':
    main()