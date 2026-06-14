

# requirements.txt
# scrapy ou requests + beautifulsoup4
# langchain (pour le chunking)
# chromadb
# sentence-transformers (embeddings GRATUITS et locaux)
import requests
from bs4 import BeautifulSoup
from sentence_transformers import SentenceTransformer
import chromadb
import json
import csv

# ── 1. SCRAPER ──────────────────────────────────────────────
def scrape_page(url):
    headers = {'User-Agent': 'AmiinBot/1.0 (assistant djiboutien)'}
    try:
        r = requests.get(url, timeout=10, headers=headers)
        soup = BeautifulSoup(r.text, 'html.parser')
        
        for tag in soup(['nav', 'footer', 'script', 'style', 'aside', 'header']):
            tag.decompose()
        
        # Supprimer les textes répétitifs du header presidence.dj
        for tag in soup.find_all(string=lambda t: t and 'Unité - Egalité - Paix' in t):
            tag.extract()

        title = soup.find('h1') or soup.find('title')
        body = soup.find('main') or soup.find('article') or soup.find('body')
        
        return {
            'url': url,
            'title': title.get_text(strip=True) if title else '',
            'content': body.get_text(separator='\n', strip=True) if body else ''
        }
    except Exception as e:
        print(f"Erreur sur {url}: {e}")
        return None
# ── 2. CHUNKER ──────────────────────────────────────────────
def chunk_text(text, chunk_size=500, overlap=50):
    """Découpe le texte en morceaux avec chevauchement"""
    words = text.split()
    chunks = []
    for i in range(0, len(words), chunk_size - overlap):
        chunk = ' '.join(words[i:i + chunk_size])
        if len(chunk) > 100:  # Ignorer les chunks trop courts
            chunks.append(chunk)
    return chunks
# ── 3. EMBEDDER + STOCKAGE ───────────────────────────────────
model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
# ☝️ Ce modèle est GRATUIT, LOCAL, et supporte FR/AR/Somali
client = chromadb.PersistentClient(path="./amiin_db")
collection = client.get_or_create_collection("djibouti_knowledge")
def ingest_page(url, category):
    page = scrape_page(url)
    if not page or len(page['content']) < 100:
        return
    
    chunks = chunk_text(page['content'])
    
    for i, chunk in enumerate(chunks):
        embedding = model.encode(chunk).tolist()
        
        collection.add(
            ids=[f"{url}_{i}"],
            embeddings=[embedding],
            documents=[chunk],
            metadatas=[{
                'url': url,
                'title': page['title'],
                'category': category,
                'chunk_index': i
            }]
        )
    
    print(f"✅ {len(chunks)} chunks ingérés depuis {url}")
# ── 4. LANCER LE PIPELINE ────────────────────────────────────


# Charger les URLs depuis le CSV au lieu de les ecrire a la main
def charger_sites_depuis_csv(fichier_csv, scrapper_uniquement=True):
    sites = []
    with open(fichier_csv, 'r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f, delimiter=';')
        for row in reader:
            # Filtrer selon la colonne a_scrapper
            if scrapper_uniquement and row['a_scrapper'] != 'oui':
                continue
            # Ignorer les doublons (memes URLs avec /1 /2 /3)
            url = row['url']
            category = row['category']
            sites.append((url, category))
    return sites

sites = charger_sites_depuis_csv('amiin_links_final.csv')
print(f"[INFO] {len(sites)} URLs chargees depuis le CSV")

for url, category in sites:
    ingest_page(url, category)
for url, category in sites:
    ingest_page(url, category)