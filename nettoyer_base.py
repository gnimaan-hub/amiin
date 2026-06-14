# -*- coding: utf-8 -*-
"""
nettoyer_base.py - Amiin Project
Nettoie la base ChromaDB :
1. Supprime tous les chunks education.gov.dj (100% bruit)
2. Supprime les chunks presidence.dj avec header bruit
3. Corrige les titres generiques de justice.gouv.dj
4. Corrige les titres generiques de sante.gouv.dj

Usage: python nettoyer_base.py
"""

import chromadb
import requests
from bs4 import BeautifulSoup
import time

DB_PATH = './amiin_db'
client = chromadb.PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection("djibouti_knowledge")

print(f"Base avant nettoyage: {collection.count()} chunks\n")

# ── ETAPE 1 : SUPPRIMER education.gov.dj ─────────────────────────────────────
print("=" * 60)
print("ETAPE 1 - Suppression de education.gov.dj (bruit pur)")
print("=" * 60)

all_data = collection.get(include=['metadatas', 'documents'])
ids_education = [
    id_ for id_, meta in zip(all_data['ids'], all_data['metadatas'])
    if 'education.gov.dj' in (meta.get('url') or '')
]
print(f"Chunks education.gov.dj a supprimer: {len(ids_education)}")
if ids_education:
    for i in range(0, len(ids_education), 500):
        collection.delete(ids=ids_education[i:i+500])
    print(f"[OK] Supprimes")

# ── ETAPE 2 : SUPPRIMER chunks presidence.dj bruites ─────────────────────────
print("\n" + "=" * 60)
print("ETAPE 2 - Nettoyage presidence.dj (header bruit + doublons courts)")
print("=" * 60)

all_data = collection.get(include=['metadatas', 'documents'])
ids_presidence_bruit = []
for id_, meta, doc in zip(all_data['ids'], all_data['metadatas'], all_data['documents']):
    if 'presidence.dj' not in (meta.get('url') or ''):
        continue
    doc = doc or ''
    # Supprimer si contient le header repetitif OU trop court
    if 'Unité - Egalité - Paix' in doc or len(doc.split()) < 50:
        ids_presidence_bruit.append(id_)

print(f"Chunks presidence.dj a nettoyer: {len(ids_presidence_bruit)}")
if ids_presidence_bruit:
    for i in range(0, len(ids_presidence_bruit), 500):
        collection.delete(ids=ids_presidence_bruit[i:i+500])
    print(f"[OK] Supprimes")

print(f"\nBase apres suppressions: {collection.count()} chunks")

# ── ETAPE 3 : CORRIGER TITRES justice.gouv.dj ────────────────────────────────
print("\n" + "=" * 60)
print("ETAPE 3 - Correction des titres justice.gouv.dj")
print("=" * 60)

headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0',
    'Accept-Language': 'fr-FR,fr;q=0.9'
}

all_data = collection.get(include=['metadatas', 'documents'])
justice_chunks = [
    (id_, meta, doc)
    for id_, meta, doc in zip(all_data['ids'], all_data['metadatas'], all_data['documents'])
    if 'justice.gouv.dj' in (meta.get('url') or '') and meta.get('title') == 'Justice'
]

print(f"Chunks justice avec titre generique: {len(justice_chunks)}")

# Grouper par URL pour ne faire qu'une requete par page
url_to_ids = {}
for id_, meta, doc in justice_chunks:
    url = meta.get('url', '')
    if url not in url_to_ids:
        url_to_ids[url] = []
    url_to_ids[url].append((id_, meta, doc))

corriges = 0
for url, items in url_to_ids.items():
    try:
        r = requests.get(url, timeout=8, headers=headers, verify=False)
        if r.status_code != 200:
            continue
        r.encoding = r.apparent_encoding or 'utf-8'
        soup = BeautifulSoup(r.content, 'html.parser')

        # Chercher le vrai titre
        titre = ''
        for sel in ['.article-title h1', '.page-title h1', 'h1.title',
                    'h1', '.content h2', 'h2.article-title', 'h2']:
            el = soup.select_one(sel)
            if el:
                t = el.get_text(strip=True)
                if len(t) > 5 and t.lower() not in ['justice', 'accueil']:
                    titre = t[:150]
                    break

        if not titre:
            # Essayer le <title> de la page
            title_tag = soup.find('title')
            if title_tag:
                t = title_tag.get_text(strip=True)
                if '|' in t:
                    t = t.split('|')[0].strip()
                if t.lower() not in ['justice', 'accueil'] and len(t) > 5:
                    titre = t[:150]

        if titre and titre != 'Justice':
            # Mettre a jour tous les chunks de cette URL
            for id_, meta, doc in items:
                meta['title'] = titre
                collection.update(
                    ids=[id_],
                    metadatas=[meta]
                )
            corriges += len(items)
            print(f"  [OK] '{titre}' ({len(items)} chunks)")
        else:
            print(f"  [?] Titre non trouve: {url[-50:]}")

        time.sleep(0.5)
    except Exception as e:
        print(f"  [ERR] {url[-50:]}: {str(e)[:40]}")

print(f"\nChunks corriges: {corriges}/{len(justice_chunks)}")

# ── ETAPE 4 : CORRIGER TITRES sante.gouv.dj ──────────────────────────────────
print("\n" + "=" * 60)
print("ETAPE 4 - Correction des titres sante.gouv.dj")
print("=" * 60)

all_data = collection.get(include=['metadatas', 'documents'])
sante_chunks = [
    (id_, meta, doc)
    for id_, meta, doc in zip(all_data['ids'], all_data['metadatas'], all_data['documents'])
    if 'sante.gouv.dj' in (meta.get('url') or '')
    and meta.get('title') in ['Ministère de la santé', 'Ministere de la sante', '']
]

print(f"Chunks sante avec titre generique: {len(sante_chunks)}")

url_to_ids_sante = {}
for id_, meta, doc in sante_chunks:
    url = meta.get('url', '')
    if url not in url_to_ids_sante:
        url_to_ids_sante[url] = []
    url_to_ids_sante[url].append((id_, meta, doc))

corriges_sante = 0
for url, items in url_to_ids_sante.items():
    try:
        r = requests.get(url, timeout=8, headers=headers, verify=False)
        if r.status_code != 200:
            continue
        r.encoding = r.apparent_encoding or 'utf-8'
        soup = BeautifulSoup(r.content, 'html.parser')

        titre = ''
        for sel in ['h1', 'h2', '.article-title', '.post-title', 'title']:
            el = soup.select_one(sel)
            if el:
                t = el.get_text(strip=True)
                if '|' in t:
                    t = t.split('|')[0].strip()
                generic = ['ministere', 'sante', 'accueil', 'home']
                if len(t) > 5 and not any(g in t.lower() for g in generic):
                    titre = t[:150]
                    break

        if titre:
            for id_, meta, doc in items:
                meta['title'] = titre
                collection.update(ids=[id_], metadatas=[meta])
            corriges_sante += len(items)
            print(f"  [OK] '{titre}' ({len(items)} chunks)")
        else:
            print(f"  [?] {url[-55:]}")

        time.sleep(0.5)
    except Exception as e:
        print(f"  [ERR] {url[-50:]}: {str(e)[:40]}")

print(f"\nChunks sante corriges: {corriges_sante}/{len(sante_chunks)}")

# ── BILAN FINAL ───────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("BILAN FINAL")
print("=" * 60)
print(f"Total chunks en base: {collection.count()}")

# Stats par source
all_data = collection.get(include=['metadatas'])
from collections import Counter
sources = Counter(
    m.get('source') or m.get('url', '').split('/')[2]
    for m in all_data['metadatas']
)
print("\nChunks par source:")
for src, n in sources.most_common():
    print(f"  {src:<30} {n}")