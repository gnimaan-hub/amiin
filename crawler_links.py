# -*- coding: utf-8 -*-
"""
crawler_links.py - Amiin Project
Crawl automatique d'un ou plusieurs sites djiboutiens.
Decouvre toutes les pages internes et exporte un CSV pret a coller dans scrapper.py.

Usage :
    python crawler_links.py

Le fichier CSV genere : amiin_links.csv
"""

import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin, urlparse
import csv
import time
from collections import deque

# -- CONFIGURATION -------------------------------------------------------------

SITES_TO_CRAWL = [
    "https://justice.gouv.dj/",
    # Ajoute d'autres sites ici :
    # "https://www.gouv.dj",
    # "https://www.la-nation.dj",
    # "https://www.interieur.gouv.dj",
    # "https://cnss.dj",
    # "https://djiboutitelecom.dj",
]

# Delai entre chaque requete (secondes) - soyez polis avec les serveurs
DELAY_BETWEEN_REQUESTS = 1.0

# Nombre maximum de pages a crawler par site (securite)
MAX_PAGES_PER_SITE = 300

# Extensions a ignorer (pas de contenu textuel utile)
IGNORE_EXTENSIONS = {
    '.pdf', '.jpg', '.jpeg', '.png', '.gif', '.svg', '.ico',
    '.mp4', '.mp3', '.zip', '.doc', '.docx', '.xls', '.xlsx',
    '.css', '.js', '.xml', '.json', '.woff', '.woff2', '.ttf'
}

# Mots dans l'URL qui signalent une page sans interet pour la KB
IGNORE_URL_PATTERNS = [
    '/tag/', '/author/', '/feed/', '/wp-', '/admin/',
    '/login', '/logout', '/cart', '/checkout', '?s=',
    '#', 'javascript:', 'mailto:', 'tel:'
]

# -- SYSTEME DE CATEGORISATION AUTOMATIQUE -------------------------------------
# Base sur les mots-cles dans l'URL ou le titre de la page

CATEGORY_RULES = [
    # (mots-cles dans URL/titre, categorie assignee)
    (['constitution', 'loi', 'decret', 'ordonnance', 'texte'], 'juridique'),
    (['ministere', 'ministre', 'gouvernement', 'attributions', 'composition'], 'gouvernement'),
    (['assemblee', 'parlement', 'senat', 'conseil-constitutionnel',
      'conseil-superieur', 'mediateur', 'commission'], 'institution'),
    (['president', 'presidence', 'discours', 'message', 'communique'], 'presidence'),
    (['region', 'ville', 'district', 'geographie', 'territoire',
      'presentation', 'generalite', 'symboles'], 'geographie'),
    (['sante', 'hopital', 'medecin', 'clinique', 'covid', 'vaccin'], 'sante'),
    (['education', 'ecole', 'universite', 'formation', 'bourse',
      'enseignement'], 'education'),
    (['economie', 'finance', 'budget', 'impot', 'douane', 'banque',
      'investissement', 'commerce'], 'economie'),
    (['travail', 'emploi', 'cnss', 'securite-sociale', 'syndicat',
      'salaire', 'contrat'], 'travail'),
    (['transport', 'route', 'port', 'aeroport', 'chemin-de-fer',
      'infrastructure'], 'transport'),
    (['culture', 'histoire', 'patrimoine', 'musee', 'tradition',
      'fete', 'tourisme'], 'culture'),
    (['actualite', 'news', 'article', 'presse', 'journal',
      'information', 'communique'], 'actualites'),
    (['passeport', 'visa', 'identite', 'cin', 'etat-civil',
      'naissance', 'mariage', 'immigration'], 'etat_civil'),
    (['environnement', 'climat', 'eau', 'energie', 'electricite',
      'agriculture', 'peche'], 'environnement'),
    (['securite', 'police', 'gendarmerie', 'defense', 'armee'], 'securite'),
]

def categorize_url(url, title=''):
    """Assigne automatiquement une categorie basee sur l'URL et le titre."""
    text = (url + ' ' + title).lower()
    for keywords, category in CATEGORY_RULES:
        if any(kw in text for kw in keywords):
            return category
    return 'general'

# -- FONCTIONS DE CRAWL --------------------------------------------------------

def is_valid_url(url, base_domain):
    """Verifie si l'URL est valide et appartient au meme domaine."""
    parsed = urlparse(url)

    # Doit etre HTTP ou HTTPS
    if parsed.scheme not in ('http', 'https'):
        return False

    # Doit appartenir au meme domaine de base
    if base_domain not in parsed.netloc:
        return False

    # Ignorer les extensions inutiles
    path_lower = parsed.path.lower()
    if any(path_lower.endswith(ext) for ext in IGNORE_EXTENSIONS):
        return False

    # Ignorer les patterns indesirables
    full_url_lower = url.lower()
    if any(pattern in full_url_lower for pattern in IGNORE_URL_PATTERNS):
        return False

    return True

def get_page_title(soup):
    """Extrait le titre de la page."""
    h1 = soup.find('h1')
    if h1:
        return h1.get_text(strip=True)[:120]
    title = soup.find('title')
    if title:
        return title.get_text(strip=True)[:120]
    return ''

def estimate_content_length(soup):
    """Estime si la page a du vrai contenu (pas juste un menu)."""
    for tag in soup(['nav', 'footer', 'script', 'style', 'aside', 'header']):
        tag.decompose()
    body = soup.find('main') or soup.find('article') or soup.find('body')
    if not body:
        return 0
    text = body.get_text(separator=' ', strip=True)
    return len(text.split())

def crawl_site(start_url):
    """Crawl complet d'un site - retourne la liste de toutes les pages trouvees."""
    parsed = urlparse(start_url)
    base_domain = parsed.netloc
    
    visited = set()
    to_visit = deque([start_url])
    results = []
    
    headers = {
        'User-Agent': 'AmiinBot/1.0 (assistant djiboutien - crawl bienveillant)'
    }
    
    print(f"\n[SEARCH] Crawl de : {start_url}")
    print(f"   Domaine : {base_domain}")
    print(f"   Max pages : {MAX_PAGES_PER_SITE}\n")
    
    while to_visit and len(visited) < MAX_PAGES_PER_SITE:
        url = to_visit.popleft()
        
        # Normaliser l'URL (supprimer fragment #)
        url = url.split('#')[0].rstrip('/')
        if not url:
            continue
            
        if url in visited:
            continue
        visited.add(url)
        
        try:
            response = requests.get(url, timeout=10, headers=headers)
            
            # Ignorer les pages non-HTML
            content_type = response.headers.get('content-type', '')
            if 'text/html' not in content_type:
                continue
                
            if response.status_code != 200:
                print(f"  WARNING {response.status_code} - {url}")
                continue
            
            response.encoding = response.apparent_encoding or 'utf-8'
            soup = BeautifulSoup(response.content, 'html.parser', from_encoding='utf-8')
            title = get_page_title(soup)
            word_count = estimate_content_length(soup)
            category = categorize_url(url, title)
            
            # Enregistrer cette page si elle a du contenu
            if word_count >= 50:
                results.append({
                    'url': url,
                    'title': title,
                    'category': category,
                    'word_count': word_count,
                    'site': base_domain,
                    'a_scrapper': 'oui' if word_count >= 150 else 'verifier'
                })
                status = '[OK]' if word_count >= 150 else '[WARN] '
                print(f"  {status} [{word_count:>5} mots] [{category:<15}] {url.replace(start_url, '')[:60]}")
            else:
                print(f"  [SKIP] [{word_count:>5} mots] (trop court) {url.replace(start_url, '')[:60]}")
            
            # Decouvrir les nouveaux liens
            for a_tag in soup.find_all('a', href=True):
                href = a_tag['href'].strip()
                full_url = urljoin(url, href).split('#')[0].rstrip('/')
                if full_url and full_url not in visited and is_valid_url(full_url, base_domain):
                    to_visit.append(full_url)
            
            time.sleep(DELAY_BETWEEN_REQUESTS)
            
        except Exception as e:
            print(f"  [ERR] Erreur sur {url}: {e}")
    
    print(f"\n  -> {len(results)} pages utiles trouvees sur {len(visited)} visitees")
    return results

# -- PROGRAMME PRINCIPAL -------------------------------------------------------

def main():
    all_results = []
    
    for site_url in SITES_TO_CRAWL:
        site_results = crawl_site(site_url)
        all_results.extend(site_results)
    
    if not all_results:
        print("\n[WARN]  Aucun resultat trouve.")
        return
    
    # Trier par categorie puis par nombre de mots (decroissant)
    all_results.sort(key=lambda x: (x['category'], -x['word_count']))
    
    # Exporter en CSV
    output_file = 'amiin_links.csv'
    fieldnames = ['url', 'title', 'category', 'word_count', 'site', 'a_scrapper']
    
    with open(output_file, 'w', newline='', encoding='utf-8-sig') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, delimiter=';')
        writer.writeheader()
        writer.writerows(all_results)
    
    print(f"\n{'='*60}")
    print(f"[OK] CSV exporte : {output_file}")
    print(f"   Total pages : {len(all_results)}")
    
    # Resume par categorie
    from collections import Counter
    categories = Counter(r['category'] for r in all_results)
    print(f"\n[STATS] Repartition par categorie :")
    for cat, count in categories.most_common():
        print(f"   {cat:<20} {count} pages")
    
    print(f"\n[TIP] Prochaine etape :")
    print(f"   1. Ouvre amiin_links.csv")
    print(f"   2. Verifie les lignes marquees 'verifier' dans la colonne a_scrapper")
    print(f"   3. Copie les URLs confirmees dans scrapper.py")

if __name__ == '__main__':
    main()