# -*- coding: utf-8 -*-
"""
scraper_universel.py - Amiin Project
Scraper intelligent qui s'adapte automatiquement a la structure de chaque site.
Crawl, extrait le contenu principal, chunk et ingere dans ChromaDB.

Usage:
    python scraper_universel.py

Configure les sites dans la section CONFIGURATION en bas du fichier.
"""

import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
from sentence_transformers import SentenceTransformer
import chromadb
import csv
import time
import json
from collections import deque

# ── CONFIGURATION GLOBALE ─────────────────────────────────────────────────────

DB_PATH = './amiin_db'
DELAY = 0.8
MAX_PAGES = 300
MIN_WORDS = 80

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
}

IGNORE_EXTENSIONS = {
    '.pdf', '.jpg', '.jpeg', '.png', '.gif', '.svg', '.ico', '.webp',
    '.mp4', '.mp3', '.zip', '.doc', '.docx', '.xls', '.xlsx',
    '.css', '.js', '.xml', '.json', '.woff', '.woff2', '.ttf', '.eot'
}

IGNORE_URL_PATTERNS = [
    '/tag/', '/author/', '/feed/', '/wp-json/', '/wp-admin/', '/wp-login',
    '/login', '/logout', '/register', '/cart', '/checkout', '/panier',
    '?s=', '?search=', '?p=', 'javascript:', 'mailto:', 'tel:', 'whatsapp:',
    '#', '/print/', '/imprimer', '?print=', '?format=pdf'
]

# Lignes de bruit universelles a supprimer
BRUIT_UNIVERSEL = [
    'accueil', 'menu', 'navigation', 'rechercher', 'search',
    'partager', 'share', 'imprimer', 'print', 'telecharger',
    'retour en haut', 'back to top', 'cookie', 'gdpr',
    'nous contacter', 'contact us', 'inscription newsletter',
    'suivez-nous', 'reseaux sociaux', 'facebook', 'twitter', 'instagram',
    'copyright', 'tous droits reserves', 'mentions legales', 'politique de confidentialite',
    'plan du site', 'sitemap', 'aller au contenu', 'skip to content',
]

# ── CATEGORIES ────────────────────────────────────────────────────────────────

CATEGORY_RULES = [
    (['constitution', 'loi', 'decret', 'ordonnance', 'code', 'arrete', 'texte legislatif'], 'juridique'),
    (['ministere', 'ministre', 'gouvernement', 'attributions', 'organigramme', 'composition'], 'gouvernement'),
    (['assemblee', 'parlement', 'conseil constitutionnel', 'mediateur', 'commission'], 'institution'),
    (['president', 'presidence', 'discours', 'allocution', 'communique'], 'presidence'),
    (['region', 'ville', 'district', 'geographie', 'territoire', 'presentation', 'symboles'], 'geographie'),
    (['sante', 'hopital', 'medecin', 'clinique', 'pharmacie', 'maladie', 'vaccin', 'chirurgie'], 'sante'),
    (['education', 'ecole', 'universite', 'lycee', 'formation', 'bourse', 'baccalaureat', 'pedagogie'], 'education'),
    (['economie', 'finance', 'budget', 'impot', 'douane', 'banque', 'investissement', 'commerce', 'taux'], 'economie'),
    (['travail', 'emploi', 'cnss', 'securite sociale', 'salaire', 'contrat', 'pension', 'retraite'], 'travail'),
    (['transport', 'route', 'port', 'aeroport', 'ferrovia', 'infrastructure', 'voirie'], 'transport'),
    (['culture', 'histoire', 'patrimoine', 'tradition', 'fete', 'tourisme', 'site touristique'], 'culture'),
    (['actualite', 'news', 'article', 'presse', 'journal', 'evenement', 'agenda'], 'actualites'),
    (['passeport', 'visa', 'identite', 'cin', 'etat civil', 'naissance', 'mariage', 'immigration', 'demarch'], 'etat_civil'),
    (['environnement', 'climat', 'eau', 'energie', 'electricite', 'agriculture', 'peche', 'foret'], 'environnement'),
    (['securite', 'police', 'gendarmerie', 'defense', 'armee', 'surete'], 'securite'),
    (['justice', 'tribunal', 'jugement', 'avocat', 'notaire', 'juridiction', 'penal', 'civil'], 'juridique'),
    (['banque', 'credit', 'epargne', 'pret', 'compte', 'virement', 'carte bancaire', 'microcredit'], 'economie'),
]

def categorize(url, title='', content=''):
    text = (url + ' ' + title + ' ' + content[:200]).lower()
    for keywords, cat in CATEGORY_RULES:
        if any(kw in text for kw in keywords):
            return cat
    return 'general'

# ── DETECTION AUTOMATIQUE DE STRUCTURE ───────────────────────────────────────

CONTENT_SELECTORS = [
    # Du plus specifique au plus general
    ('div', {'id': 'block'}),                          # egouv.dj
    ('div', {'class': 'entry-content'}),               # WordPress standard
    ('div', {'class': 'post-content'}),
    ('div', {'class': 'article-content'}),
    ('div', {'class': 'page-content'}),
    ('div', {'class': 'content-area'}),
    ('div', {'id': 'content'}),
    ('div', {'id': 'main-content'}),
    ('div', {'id': 'main'}),
    ('div', {'class': 'main-content'}),
    ('div', {'class': 'single-post'}),
    ('article', {}),
    ('main', {}),
    ('div', {'role': 'main'}),
    ('section', {'class': 'content'}),
    ('div', {'class': 'container'}),                   # Fallback large
]

NOISE_SELECTORS = [
    'nav', 'header', 'footer', 'aside',
    'script', 'style', 'noscript',
    '.sidebar', '.widget', '#sidebar',
    '.breadcrumb', '.breadcrumbs',
    '.social-share', '.share-buttons',
    '.related-posts', '.related',
    '.comments', '#comments',
    '.navigation', '.post-navigation',
    '.pagination', '.pager',
    '.cookie-notice', '.gdpr',
    '.newsletter', '.subscribe',
    '#searchBar', '.search-container',    # egouv.dj
    '.contact-widget',                    # egouv.dj
    '#faqs',                              # egouv.dj
    'form',
]

def detecter_selecteur_contenu(soup, url):
    """
    Detecte automatiquement le meilleur selecteur de contenu pour cette page.
    Retourne l'element contenant le plus de texte utile.
    """
    meilleur = None
    meilleur_mots = 0
    meilleur_sel = 'body'

    for tag, attrs in CONTENT_SELECTORS:
        if attrs:
            el = soup.find(tag, attrs)
        else:
            el = soup.find(tag)

        if not el:
            continue

        # Compter les mots en excluant le bruit
        el_copy = BeautifulSoup(str(el), 'html.parser')
        for bruit in el_copy.select(','.join(NOISE_SELECTORS[:10])):
            bruit.decompose()
        for t in el_copy(['script', 'style', 'form', 'nav']):
            t.decompose()

        texte = el_copy.get_text(separator=' ', strip=True)
        mots = len(texte.split())

        if mots > meilleur_mots:
            meilleur_mots = mots
            meilleur = el
            sel_name = f"{tag}.{attrs}" if attrs else tag
            meilleur_sel = sel_name

    return meilleur, meilleur_mots, meilleur_sel

def extraire_titre(soup):
    """Extrait le titre le plus pertinent de la page."""
    # Priorite: h1 dans zone de contenu, puis h1 global, puis h2, puis title
    for zone in ['article', 'main', '.entry-title', '.page-title', '.post-title']:
        zone_el = soup.select_one(zone)
        if zone_el:
            h1 = zone_el.find('h1')
            if h1:
                return h1.get_text(strip=True)[:150]

    h1 = soup.find('h1')
    if h1:
        titre = h1.get_text(strip=True)
        if len(titre) > 5:
            return titre[:150]

    h2 = soup.find('h2')
    if h2:
        titre = h2.get_text(strip=True)
        if len(titre) > 5:
            return titre[:150]

    title = soup.find('title')
    if title:
        # Nettoyer "Titre | Nom du site"
        t = title.get_text(strip=True)
        if '|' in t:
            t = t.split('|')[0].strip()
        if '-' in t and len(t.split('-')[0]) > 5:
            t = t.split('-')[0].strip()
        return t[:150]

    return ''

def nettoyer_contenu(element):
    """Nettoie un element BeautifulSoup et retourne le texte propre."""
    if not element:
        return ''

    # Supprimer tous les elements de bruit
    for sel in NOISE_SELECTORS:
        for el in element.select(sel):
            el.decompose()

    # Supprimer scripts, styles, formulaires
    for tag in element(['script', 'style', 'form', 'button', 'input', 'noscript']):
        tag.decompose()

    # Extraire le texte ligne par ligne
    texte = element.get_text(separator='\n', strip=True)

    # Filtrer les lignes de bruit
    lignes_finales = []
    for ligne in texte.split('\n'):
        ligne = ligne.strip()
        if not ligne or len(ligne) < 3:
            continue
        ligne_lower = ligne.lower()
        if any(bruit in ligne_lower for bruit in BRUIT_UNIVERSEL):
            continue
        # Ignorer les lignes qui sont juste des URLs ou emails
        if ligne.startswith('http') or '@' in ligne and '.' in ligne and len(ligne) < 50:
            continue
        lignes_finales.append(ligne)

    # Supprimer les lignes dupliquees consecutives
    result = []
    prev = None
    for ligne in lignes_finales:
        if ligne != prev:
            result.append(ligne)
        prev = ligne

    return '\n'.join(result)

# ── CRAWL ─────────────────────────────────────────────────────────────────────

def is_valid_url(url, base_domain):
    parsed = urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        return False
    if base_domain not in parsed.netloc:
        return False
    path_lower = parsed.path.lower()
    if any(path_lower.endswith(ext) for ext in IGNORE_EXTENSIONS):
        return False
    url_lower = url.lower()
    if any(pat in url_lower for pat in IGNORE_URL_PATTERNS):
        return False
    return True

def crawl_et_scraper(site_config):
    """
    Crawl complet d'un site + scraping + ingestion ChromaDB.
    site_config = {
        'url': 'https://...',
        'category': 'sante',          # categorie par defaut (peut etre override)
        'content_selector': None,      # None = detection auto
        'url_filter': None,            # fonction(url)->bool optionnelle
    }
    """
    start_url = site_config['url'].rstrip('/')
    default_category = site_config.get('category', 'general')
    force_selector = site_config.get('content_selector', None)

    parsed = urlparse(start_url)
    base_domain = parsed.netloc

    visited = set()
    to_visit = deque([start_url])
    stats = {'pages': 0, 'chunks': 0, 'vides': 0, 'erreurs': 0}
    rapport = []

    print(f"\n{'='*65}")
    print(f"SITE: {start_url}")
    print(f"Domaine: {base_domain} | Categorie defaut: {default_category}")
    print(f"{'='*65}")

    while to_visit and len(visited) < MAX_PAGES:
        url = to_visit.popleft().split('#')[0].rstrip('/')
        if not url or url in visited:
            continue
        visited.add(url)

        try:
            r = requests.get(url, timeout=12, headers=HEADERS,
                           allow_redirects=True, verify=False)

            if r.status_code != 200:
                print(f"  [{r.status_code}] {url[-60:]}")
                stats['erreurs'] += 1
                continue

            ct = r.headers.get('content-type', '')
            if 'text/html' not in ct:
                continue

            r.encoding = r.apparent_encoding or 'utf-8'
            soup = BeautifulSoup(r.content, 'html.parser', from_encoding='utf-8')

            # Extraire titre
            titre = extraire_titre(soup)

            # Detecter ou forcer le selecteur de contenu
            if force_selector:
                contenu_el = soup.select_one(force_selector)
                sel_utilise = force_selector
                mots = len(contenu_el.get_text().split()) if contenu_el else 0
            else:
                contenu_el, mots, sel_utilise = detecter_selecteur_contenu(soup, url)

            # Nettoyer et extraire le texte
            contenu = nettoyer_contenu(contenu_el) if contenu_el else ''
            nb_mots = len(contenu.split())

            # Determiner la categorie
            cat = categorize(url, titre, contenu)

            if nb_mots < MIN_WORDS:
                print(f"  [VIDE  {nb_mots:>4}m] {url.replace(start_url,'')[:55]}")
                stats['vides'] += 1
            else:
                # Chunker et ingerer
                chunks = chunk_text(contenu)
                nb_chunks = 0

                for i, chunk in enumerate(chunks):
                    emb = model.encode(chunk).tolist()
                    chunk_id = f"{url}_{i}"
                    try:
                        collection.add(
                            ids=[chunk_id],
                            embeddings=[emb],
                            documents=[chunk],
                            metadatas={
                                'url': url,
                                'title': titre,
                                'category': cat,
                                'chunk_index': i,
                                'source': base_domain,
                                'selector': sel_utilise
                            }
                        )
                        nb_chunks += 1
                    except Exception:
                        # Deja present, ignorer
                        pass

                stats['pages'] += 1
                stats['chunks'] += nb_chunks

                etat = '[OK]' if nb_chunks > 0 else '[DUP]'
                print(f"  {etat} [{nb_mots:>4}m/{nb_chunks}c] [{cat:<14}] {titre[:35]:<35} | {url.replace(start_url,'')[:25]}")

                rapport.append({
                    'url': url,
                    'titre': titre,
                    'category': cat,
                    'mots': nb_mots,
                    'chunks': nb_chunks,
                    'selecteur': sel_utilise
                })

            # Decouvrir les liens
            for a in soup.find_all('a', href=True):
                href = a['href'].strip()
                full = urljoin(url, href).split('#')[0].rstrip('/')
                if full and full not in visited and is_valid_url(full, base_domain):
                    # Filtre optionnel specifique au site
                    if site_config.get('url_filter') and not site_config['url_filter'](full):
                        continue
                    to_visit.append(full)

            time.sleep(DELAY)

        except Exception as e:
            print(f"  [ERR] {url[-55:]}: {str(e)[:50]}")
            stats['erreurs'] += 1

    print(f"\n  BILAN: {stats['pages']} pages | {stats['chunks']} chunks | {stats['vides']} vides | {stats['erreurs']} erreurs")
    return rapport, stats

def chunk_text(text, chunk_size=400, overlap=40):
    words = text.split()
    chunks = []
    step = max(1, chunk_size - overlap)
    for i in range(0, len(words), step):
        chunk = ' '.join(words[i:i + chunk_size])
        if len(chunk.split()) >= 30:
            chunks.append(chunk)
    return chunks

# ── INITIALISATION ────────────────────────────────────────────────────────────

import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

print("Chargement du modele d'embedding...")
model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
client = chromadb.PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection("djibouti_knowledge")
print(f"Base actuelle: {collection.count()} chunks\n")

# ── SITES A SCRAPER ───────────────────────────────────────────────────────────
# Ajoute / commente les sites selon tes besoins.
# content_selector: mettre None pour detection auto,
#                   ou un selecteur CSS precis si tu connais la structure.

SITES = [
    {
        'url': 'https://justice.gouv.dj',
        'category': 'juridique',
        'content_selector': None,   # auto
    },
    {
        'url': 'https://sante.gouv.dj',
        'category': 'sante',
        'content_selector': None,
    },
    {
        'url': 'http://www.education.gov.dj',
        'category': 'education',
        'content_selector': None,
    },
    {
        'url': 'https://cnss.dj',
        'category': 'travail',
        'content_selector': None,
    },
    {
        'url': 'https://www.salaambankdj.com',
        'category': 'economie',
        'content_selector': None,
    },
    # Ajoute d'autres sites ici :
    # {'url': 'https://budget.gouv.dj', 'category': 'economie', 'content_selector': None},
    # {'url': 'https://diplomatie.gouv.dj', 'category': 'gouvernement', 'content_selector': None},
    # {'url': 'https://djiboutitelecom.dj', 'category': 'pratique', 'content_selector': None},
]

# ── LANCEMENT ─────────────────────────────────────────────────────────────────

tous_rapports = []
bilan_global = {'pages': 0, 'chunks': 0}

for site in SITES:
    rapport, stats = crawl_et_scraper(site)
    tous_rapports.extend(rapport)
    bilan_global['pages'] += stats['pages']
    bilan_global['chunks'] += stats['chunks']

# Sauvegarder le rapport CSV
with open('rapport_scraping.csv', 'w', newline='', encoding='utf-8-sig') as f:
    if tous_rapports:
        writer = csv.DictWriter(f, fieldnames=tous_rapports[0].keys(), delimiter=';')
        writer.writeheader()
        writer.writerows(tous_rapports)

print(f"\n{'='*65}")
print(f"TERMINE - {bilan_global['pages']} pages scrapees | {bilan_global['chunks']} chunks ingeres")
print(f"Total en base: {collection.count()} chunks")
print(f"Rapport detaille: rapport_scraping.csv")
print(f"\nSi un site n'a rien donne (0 pages), il filtre probablement par IP.")
print(f"Dans ce cas, envoie-moi le rapport + le code source d'une page du site")
print(f"pour que j'adapte le selecteur manuellement.")