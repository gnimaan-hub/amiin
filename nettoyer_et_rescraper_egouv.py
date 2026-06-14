# -*- coding: utf-8 -*-
"""
nettoyer_et_rescraper_egouv.py - Amiin Project
1. Supprime tous les chunks egouv.dj de ChromaDB
2. Rescrape proprement egouv.dj en extrayant uniquement le contenu utile
   (entre "De quoi s'agit-il ?" et le footer)

Usage:
    python nettoyer_et_rescraper_egouv.py
"""

import chromadb
import requests
from bs4 import BeautifulSoup
from sentence_transformers import SentenceTransformer
import csv
import time

# ── CONFIG ────────────────────────────────────────────────────────────────────

DB_PATH = './amiin_db'
CSV_PATH = './amiin_links_final.csv'
DELAY = 0.8  # secondes entre requetes

# ── ETAPE 1 : SUPPRIMER LES CHUNKS EGOUV.DJ ──────────────────────────────────

print("=" * 60)
print("ETAPE 1 - Suppression des chunks egouv.dj")
print("=" * 60)

client = chromadb.PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection("djibouti_knowledge")

# Recuperer tous les IDs egouv
results = collection.get(include=['metadatas'])
ids_to_delete = [
    id_ for id_, meta in zip(results['ids'], results['metadatas'])
    if 'egouv.dj' in (meta.get('url') or '')
]

print(f"Chunks egouv.dj trouves: {len(ids_to_delete)}")

if ids_to_delete:
    # ChromaDB accepte max ~5000 suppressions a la fois
    batch_size = 500
    for i in range(0, len(ids_to_delete), batch_size):
        batch = ids_to_delete[i:i+batch_size]
        collection.delete(ids=batch)
    print(f"[OK] {len(ids_to_delete)} chunks supprimes")
else:
    print("[INFO] Aucun chunk egouv.dj trouve")

total_restant = collection.count()
print(f"Total restant en base: {total_restant}")

# ── ETAPE 2 : SCRAPER PROPREMENT EGOUV.DJ ────────────────────────────────────

print()
print("=" * 60)
print("ETAPE 2 - Scraping propre de egouv.dj")
print("=" * 60)

model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')

headers = {
    'User-Agent': 'AmiinBot/1.0 (assistant djiboutien)',
    'Accept-Language': 'fr-FR,fr;q=0.9'
}

def extraire_contenu_egouv(soup):
    """
    Extrait uniquement le contenu utile d'une page egouv.dj.
    Le vrai contenu est dans #block (div id="block" class="entry-content")
    Il contient : De quoi s'agit-il, A qui s'adresser, Conditions, Frais, Horaires
    """
    # Cible principale : le bloc de contenu central
    bloc = soup.find('div', id='block')
    if not bloc:
        # Fallback : chercher entry-content
        bloc = soup.find('div', class_='entry-content')
    
    if not bloc:
        return None, None
    
    # Extraire le titre (h2 dans entry-title)
    titre_tag = soup.find('div', class_='entry-title')
    titre = ''
    if titre_tag:
        h = titre_tag.find('h2') or titre_tag.find('h1')
        if h:
            titre = h.get_text(strip=True)
    
    # Nettoyer le bloc : supprimer les formulaires et boutons
    for tag in bloc.find_all(['form', 'button', 'script', 'style']):
        tag.decompose()
    
    # Extraire le texte propre
    contenu = bloc.get_text(separator='\n', strip=True)
    
    # Supprimer les lignes de bruit connues
    lignes_bruit = [
        'imprimer', 'suivant', 'submit', 'login', 'envoyer',
        'vos suggestions', 'faq', 'les reponses a toutes vos questions',
        'copyright', 'ansie', 'se connecter', 'tous les services',
        'services en ligne', 'vos demarches en ligne'
    ]
    
    lignes = contenu.split('\n')
    lignes_propres = []
    for ligne in lignes:
        ligne_strip = ligne.strip()
        if not ligne_strip:
            continue
        if any(bruit in ligne_strip.lower() for bruit in lignes_bruit):
            continue
        if len(ligne_strip) < 3:
            continue
        lignes_propres.append(ligne_strip)
    
    contenu_final = '\n'.join(lignes_propres)
    return titre, contenu_final

def chunk_text(text, chunk_size=400, overlap=40):
    """Decoupe le texte en morceaux avec chevauchement."""
    words = text.split()
    chunks = []
    step = chunk_size - overlap
    for i in range(0, len(words), step):
        chunk = ' '.join(words[i:i + chunk_size])
        if len(chunk.split()) > 30:
            chunks.append(chunk)
    return chunks

def ingest_egouv(url, category, titre_csv=''):
    """Scrape et ingere une page egouv.dj proprement."""
    try:
        r = requests.get(url, timeout=10, headers=headers)
        r.encoding = 'utf-8'
        soup = BeautifulSoup(r.content, 'html.parser', from_encoding='utf-8')
        
        titre, contenu = extraire_contenu_egouv(soup)
        
        if not contenu or len(contenu.split()) < 30:
            print(f"  [VIDE] {url[-50:]}")
            return 0
        
        # Utiliser le titre du CSV si le scraper n'en trouve pas
        if not titre and titre_csv:
            titre = titre_csv
        
        chunks = chunk_text(contenu)
        
        for i, chunk in enumerate(chunks):
            embedding = model.encode(chunk).tolist()
            chunk_id = f"{url}_{i}"
            
            try:
                collection.add(
                    ids=[chunk_id],
                    embeddings=[embedding],
                    documents=[chunk],
                    metadatas=[{
                        'url': url,
                        'title': titre or titre_csv,
                        'category': category,
                        'chunk_index': i,
                        'source': 'egouv.dj'
                    }]
                )
            except Exception as e:
                # Chunk deja present, on le met a jour
                collection.update(
                    ids=[chunk_id],
                    embeddings=[embedding],
                    documents=[chunk],
                    metadatas=[{
                        'url': url,
                        'title': titre or titre_csv,
                        'category': category,
                        'chunk_index': i,
                        'source': 'egouv.dj'
                    }]
                )
        
        print(f"  [OK] {len(chunks)} chunks | {titre or titre_csv}")
        return len(chunks)
        
    except Exception as e:
        print(f"  [ERR] {url[-50:]} -> {e}")
        return 0

# Lire le CSV et scraper uniquement les URLs egouv.dj
urls_egouv = []
with open(CSV_PATH, 'r', encoding='utf-8-sig') as f:
    reader = csv.DictReader(f, delimiter=';')
    for row in reader:
        if 'egouv.dj' in row['url'] and row.get('a_scrapper') == 'oui':
            urls_egouv.append(row)

# Dedupliquer : garder une seule URL par contenu
# (egouv.dj a des URLs /102/5/1 /102/5/2 /102/5/3 qui sont des paginations
#  de la meme page - on ne garde que /1)
urls_dedupliquees = []
vus = set()
for row in urls_egouv:
    url = row['url']
    # Extraire la base sans le numero de pagination final
    parties = url.rstrip('/').split('/')
    if parties[-1].isdigit() and len(parties) > 1:
        base = '/'.join(parties[:-1])
        page = int(parties[-1])
        if base in vus:
            continue
        vus.add(base)
    urls_dedupliquees.append(row)

print(f"URLs egouv.dj a scraper: {len(urls_dedupliquees)} (deduplication de {len(urls_egouv)})")
print()

total_chunks = 0
for i, row in enumerate(urls_dedupliquees):
    chunks = ingest_egouv(row['url'], row['category'], row.get('title', ''))
    total_chunks += chunks
    time.sleep(DELAY)

print()
print("=" * 60)
print(f"[OK] Terminé")
print(f"     Chunks egouv.dj ingeres: {total_chunks}")
print(f"     Total en base: {collection.count()}")