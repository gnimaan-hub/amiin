# -*- coding: utf-8 -*-
"""
scraper_banque_centrale.py - Amiin Project
Scrape et indexe le contenu du site de la Banque Centrale de Djibouti.
Gère les pages HTML et les PDFs.
Titres de chunks enrichis (extrait du contenu pour les parties > 1).

Usage:
  python scraper_banque_centrale.py --dry-run        # Test sans ingestion
  python scraper_banque_centrale.py                  # Exécution complète
  python scraper_banque_centrale.py --pdf-only       # Télécharge et indexe les PDFs seulement (pas les pages)
  python scraper_banque_centrale.py --pages-only     # Pages seulement, ignore les PDFs
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

# Configuration
DB_PATH    = './amiin_db'
COLLECTION = 'djibouti_knowledge'
MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2'

MAX_MOTS   = 480
OVERLAP    = 50
DOWNLOAD_PDF_DIR = './pdfs_banque_centrale'

HEADERS = {
    'User-Agent': 'Amiin-Bot/1.0 (Educational Djibouti Knowledge Base)'
}

# ============================================================================
# UTILITAIRES
# ============================================================================

def nettoyer_texte(texte):
    """Nettoie le texte des balises et références inutiles."""
    texte = re.sub(r'\[\d+\]', '', texte)
    texte = re.sub(r'\[réf\.\s*nécessaire\]', '', texte)
    texte = re.sub(r'\n{3,}', '\n\n', texte)
    texte = re.sub(r' {2,}', ' ', texte)
    # Supprimer les numéros de notes
    texte = re.sub(r'↑\s*\d+', '', texte)
    return texte.strip()

def generer_titre_chunk(texte_chunk, titre_base, num_part):
    """
    Génère un titre pour un chunk.
    - Partie 1 : titre_base inchangé.
    - Parties suivantes : titre_base + " : " + extrait (10 premiers mots du chunk).
    """
    if num_part == 1:
        return titre_base
    # Extraire les premiers mots significatifs
    mots = texte_chunk.split()
    if not mots:
        return f"{titre_base} (suite)"
    extrait = ' '.join(mots[:10])
    # Nettoyer les caractères spéciaux et limiter la longueur à 80 caractères
    extrait = extrait.replace('\n', ' ').strip()
    if len(extrait) > 80:
        extrait = extrait[:77] + "..."
    return f"{titre_base} : {extrait}"

def decouper_texte(texte, titre_base, source, category, url, prefix_id, extra_meta=None):
    """Découpe un texte long en chunks avec recouvrement et titres enrichis."""
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
        # Utiliser la nouvelle fonction de titre
        titre_chunk = generer_titre_chunk(sous_texte, titre_base, part)
        meta = {
            'title': titre_chunk,
            'category': category,
            'source': source,
            'url': url,
            'type': 'scrape_banque_centrale',
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
    """Télécharge un PDF et retourne le chemin local."""
    # Éviter les URLs mal formées
    if not url.startswith('http://') and not url.startswith('https://'):
        print(f"    ⚠️ URL invalide (ignorée) : {url}")
        return None
    os.makedirs(save_dir, exist_ok=True)
    # Nom de fichier basé sur l'URL
    filename = os.path.basename(urlparse(url).path)
    if not filename.endswith('.pdf'):
        filename = filename + '.pdf'
    # Éviter les noms trop longs
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
    """Extrait le texte d'un PDF avec pdfplumber."""
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
# EXTRACTION DES URLS À PARTIR DU MENU (navigation)
# ============================================================================

def extraire_urls_depuis_menu(soup, base_url):
    """Parcourt la structure HTML du menu principal et retourne un set d'URLs uniques."""
    urls = set()
    # Recherche des menus : éléments avec classe 'menu-item' ou dans #menu
    menu_items = soup.select('#menu li a') or soup.select('.menu-item a')
    for a in menu_items:
        href = a.get('href')
        if href and href.startswith('http') and base_url in href:
            urls.add(href)
        elif href and href.startswith('/'):
            full = urljoin(base_url, href)
            urls.add(full)
    # Ajouter explicitement les sections observées dans la structure
    sections = [
        '/statuts-et-missions/',
        '/organisation/',
        '/historique-du-franc-djibouti/',
        '/le-currency-board/',
        '/celebration-du-75e-anniversaire-du-fdj/',
        '/les-lois/',
        '/les-decrets/',
        '/les-instructions/',
        '/les-circulaires/',
        '/etats-financiers-audites/',
        '/les-procedures-dagrements/',
        '/tableau-de-bord-du-systeme-bancaire/',
        '/rapport-annuel-sur-la-stabilite-bancaire/',
        '/les-etablissements-agrees/',
        '/loi-systeme-national-de-paiement/',
        '/instruction-monnaie-electronique/',
        '/infrastructures-ats/',
        '/indicateurs-et-statistiques/',
        '/situation-publiable-bcd/',
        '/situation-des-banques-commerciales/',
        '/masse-monetaire-et-ses-contreparties/',
        '/depots-des-banques/',
        '/credits-et-engagements-des-banques/',
        '/balance-des-paiements/',
        '/position-exterieure-globale/',
        '/dette-exterieure/',
        '/reserves-internationales/',
        '/indicateurs-macroeconomiques/',
        '/enquete-sur-lacces-aux-services-financiers/',
        '/rapports-annuel-de-la-banque/',
        '/gafi/lois/',
        '/gafi/decrets/',
        '/gafi/arrete/',
        '/gafi/instructions/',
        '/gafi/circulaires/',
        '/gafi/lignes-directrices/anrf/',
        '/gafi/lignes-directrices/autorites-de-controle-de-supervision/',
        '/gafi/guide/',
        '/education-financiere/',
        '/billets-2/',
        '/actualites/',
        '/mediatheque/',
        '/contact/',
        '/registre-de-suretes-mobilieres/'
    ]
    for sec in sections:
        full = urljoin(base_url, sec)
        urls.add(full)
    return urls

def extraire_pdfs_depuis_page(soup, base_url):
    """Extrait tous les liens PDF d'une page HTML."""
    pdf_urls = set()
    for a in soup.find_all('a', href=True):
        href = a['href']
        if '.pdf' in href.lower():
            full = urljoin(base_url, href)
            pdf_urls.add(full)
    return pdf_urls

# ============================================================================
# EXTRACTION DU CONTENU PRINCIPAL D'UNE PAGE HTML
# ============================================================================

def extraire_contenu_page(soup, url):
    """Extrait le titre et le texte principal de la page."""
    # Titre
    title_tag = soup.find('h1') or soup.find('title')
    titre = title_tag.get_text(strip=True) if title_tag else "Page sans titre"
    # Supprimer les éléments indésirables
    for element in soup.find_all(['header', 'footer', 'nav', 'script', 'style', 'noscript', 'iframe', 'aside']):
        element.decompose()
    # Zones de contenu probable
    content_candidates = soup.find('div', class_='post_content') \
                        or soup.find('div', class_='entry-content') \
                        or soup.find('article') \
                        or soup.find('main') \
                        or soup.find('div', class_='wpb_wrapper')
    if content_candidates:
        texte = content_candidates.get_text(separator='\n', strip=True)
    else:
        # Fallback : tout le body
        body = soup.find('body')
        texte = body.get_text(separator='\n', strip=True) if body else ""
    texte = nettoyer_texte(texte)
    return titre, texte

# ============================================================================
# DÉTERMINATION DE CATÉGORIE (ALIGNÉE SUR VOTRE BASE)
# ============================================================================

def determiner_categorie(titre, url):
    """Retourne une catégorie parmi la liste existante."""
    titre_lower = titre.lower()
    url_lower = url.lower()
    
    # Juridique (lois, décrets, instructions, circulaires, GAFI, LBC, etc.)
    if any(k in titre_lower for k in ['loi', 'décret', 'decret', 'instruction', 'circulaire', 'code', 'arrete', 'arreté', 'gafi', 'lbc', 'blanchiment', 'terrorisme', 'sûretés', 'suretes']):
        return 'juridique'
    # Économie / commerce (rapports, indicateurs, balance des paiements, dette, réserves, crédits, dépôts)
    if any(k in titre_lower for k in ['rapport', 'indicateur', 'balance des paiements', 'dette', 'réserves', 'reserves', 'crédit', 'credit', 'dépôt', 'depot', 'monétaire', 'monetaire', 'inflation', 'prévisions', 'previsions', 'économie', 'economie', 'commercial', 'entreprises']):
        return 'economie_commerce'
    # Éducation financière
    if 'éducation' in titre_lower or 'education' in titre_lower:
        return 'education'
    # Billets et monnaies (culture)
    if 'billet' in titre_lower or 'monnaie' in titre_lower or 'franc' in titre_lower:
        return 'culture'
    # Institutions / administration générale
    if any(k in titre_lower for k in ['statuts', 'missions', 'organisation', 'banque centrale', 'agrément', 'agrement', 'supervision']):
        return 'institution'
    # Par défaut : général
    return 'general'

# ============================================================================
# SCRAPING PRINCIPAL
# ============================================================================

def scraper_banque_centrale(only_pages=False, only_pdfs=False):
    """
    Scrape toutes les pages du site, extrait les PDFs, et retourne une liste de chunks.
    """
    base_url = "https://banque-centrale.dj"
    print("\n🏦 Scraping Banque Centrale de Djibouti...")
    
    # Étape 1 : récupérer la page d'accueil pour extraire la structure des menus
    print("  Récupération de la page d'accueil...")
    try:
        resp = requests.get(base_url, headers=HEADERS, timeout=15)
        resp.encoding = 'utf-8'
        soup_accueil = BeautifulSoup(resp.text, 'html.parser')
    except Exception as e:
        print(f"  ❌ Erreur accès page d'accueil : {e}")
        return []
    
    urls = extraire_urls_depuis_menu(soup_accueil, base_url)
    print(f"  {len(urls)} URLs uniques identifiées (menus + sections prédéfinies).")
    
    # On se limite aux URLs du domaine
    urls = [u for u in urls if u.startswith(base_url)]
    
    tous_chunks = []
    pdf_urls_global = set()
    
    for idx, url in enumerate(urls):
        print(f"    [{idx+1}/{len(urls)}] {url}")
        try:
            resp = requests.get(url, headers=HEADERS, timeout=15)
            resp.encoding = 'utf-8'
            soup = BeautifulSoup(resp.text, 'html.parser')
            
            # Extraire les PDFs de cette page (même si on ne traite pas le texte, on collecte)
            pdfs_page = extraire_pdfs_depuis_page(soup, base_url)
            pdf_urls_global.update(pdfs_page)
            
            if only_pdfs:
                continue  # Ne traite que les PDFs, pas le HTML
            
            # Extraire le contenu texte
            titre, contenu = extraire_contenu_page(soup, url)
            if len(contenu.split()) < 50:
                print(f"      ⚠️ Contenu trop court ({len(contenu.split())} mots), ignoré.")
                continue
            
            # Créer un slug pour l'ID
            slug = re.sub(r'[^a-z0-9]+', '_', titre.lower())[:40]
            prefix_id = f"bcd_{slug}"
            
            # Déterminer la catégorie
            category = determiner_categorie(titre, url)
            
            chunks = decouper_texte(
                contenu, titre,
                source="banque-centrale.dj",
                category=category,
                url=url,
                prefix_id=prefix_id
            )
            tous_chunks.extend(chunks)
            print(f"      ✅ {len(contenu.split())} mots → {len(chunks)} chunks (cat: {category})")
            time.sleep(0.5)
            
        except Exception as e:
            print(f"      ❌ Erreur: {e}")
    
    # Traitement des PDFs
    if not only_pages:
        print(f"\n  📄 Traitement des PDFs ({len(pdf_urls_global)} fichiers trouvés)...")
        for pdf_url in pdf_urls_global:
            # Nettoyer l'URL (certaines contenaient 'hthttps')
            if pdf_url.startswith('hthttp'):
                pdf_url = pdf_url.replace('hthttp', 'http')
            print(f"    {pdf_url}")
            local_path = telecharger_pdf(pdf_url, DOWNLOAD_PDF_DIR)
            if not local_path:
                continue
            texte_pdf = extraire_texte_pdf(local_path)
            if len(texte_pdf.split()) < 100:
                print(f"      ⚠️ PDF trop court ou illisible ({len(texte_pdf.split())} mots)")
                continue
            # Déduire le titre du PDF depuis le nom de fichier
            titre_pdf = os.path.basename(local_path).replace('.pdf', '').replace('_', ' ')
            # Nettoyer le titre (enlever les extensions bizarres)
            titre_pdf = re.sub(r'\.(png|jpg|jpeg|gif)$', '', titre_pdf, flags=re.I)
            prefix_id = f"bcd_pdf_{re.sub(r'[^a-z0-9]+', '_', titre_pdf.lower())[:30]}"
            
            # Déterminer catégorie pour le PDF
            category_pdf = determiner_categorie(titre_pdf, pdf_url)
            
            chunks_pdf = decouper_texte(
                texte_pdf, titre_pdf,
                source="banque-centrale.dj (PDF)",
                category=category_pdf,
                url=pdf_url,
                prefix_id=prefix_id
            )
            tous_chunks.extend(chunks_pdf)
            print(f"      ✅ {len(texte_pdf.split())} mots → {len(chunks_pdf)} chunks (cat: {category_pdf})")
    
    print(f"  → Total chunks générés : {len(tous_chunks)}")
    return tous_chunks

# ============================================================================
# INGESTION DANS CHROMADB
# ============================================================================

def supprimer_anciens(collection, source_tag):
    """Supprime les anciens chunks d'une source donnée."""
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == source_tag or meta.get('source', '').startswith('banque-centrale.dj')]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"  {len(ids)} anciens chunks de la Banque Centrale supprimés")

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
    parser = argparse.ArgumentParser(description='Scraper Banque Centrale de Djibouti')
    parser.add_argument('--dry-run', action='store_true', help="Affiche les stats sans ingestion")
    parser.add_argument('--pages-only', action='store_true', help="Scrape uniquement les pages HTML, ignore les PDFs")
    parser.add_argument('--pdf-only', action='store_true', help="Scrape uniquement les PDFs (pas les pages HTML)")
    args = parser.parse_args()

    print("=" * 65)
    print("SCRAPER BANQUE CENTRALE DE DJIBOUTI - AMIIN")
    print("=" * 65)

    only_pages = args.pages_only
    only_pdfs = args.pdf_only

    tous_chunks = scraper_banque_centrale(only_pages=only_pages, only_pdfs=only_pdfs)

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

    # Supprimer les anciens contenus de la Banque Centrale
    supprimer_anciens(collection, 'banque-centrale.dj')

    nb = ingerer(tous_chunks, collection, model)

    count_after = collection.count()
    print(f"\n{'='*65}")
    print(f"TERMINÉ | {nb} chunks ingérés | Base: {count_before} → {count_after} ({count_after-count_before:+d})")
    print(f"{'='*65}")

if __name__ == '__main__':
    main()