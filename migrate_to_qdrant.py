# -*- coding: utf-8 -*-
"""
migrate_to_qdrant.py
Migre tous les chunks de ChromaDB vers Qdrant Cloud avec embeddings Jina AI.

Usage :
    1. Remplir .env avec JINA_API_KEY, QDRANT_URL, QDRANT_API_KEY
    2. python migrate_to_qdrant.py
    3. Attendre la fin (quelques minutes selon la connexion)
"""

import os
import sys
import time
import json
import logging
import requests
from dotenv import load_dotenv

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')

# ── Config ────────────────────────────────────────────────────────────────────
CHROMA_PATH   = './amiin_db'
COLLECTION    = 'djibouti_knowledge'
JINA_MODEL    = 'jina-embeddings-v3'
JINA_EMBED_DIM = 1024
BATCH_SIZE    = 32   # documents par appel Jina (réduit pour rester sous 100k tokens/min)
BATCH_DELAY   = 12   # secondes entre chaque batch (throttle préventif)
QDRANT_COLLECTION = 'djibouti_knowledge'

# ── Chargement des clés ───────────────────────────────────────────────────────
load_dotenv('.env')

JINA_API_KEY  = os.environ.get('JINA_API_KEY', '')
QDRANT_URL    = os.environ.get('QDRANT_URL', '')
QDRANT_API_KEY = os.environ.get('QDRANT_API_KEY', '')

def check_config():
    missing = []
    if not JINA_API_KEY or 'REMPLIR' in JINA_API_KEY:
        missing.append('JINA_API_KEY')
    if not QDRANT_URL or 'REMPLIR' in QDRANT_URL:
        missing.append('QDRANT_URL')
    if not QDRANT_API_KEY or 'REMPLIR' in QDRANT_API_KEY:
        missing.append('QDRANT_API_KEY')
    if missing:
        logging.error(f"Clés manquantes dans .env : {', '.join(missing)}")
        logging.error("Remplir le fichier .env et relancer.")
        sys.exit(1)

# ── Jina AI embeddings ────────────────────────────────────────────────────────
def embed_batch(texts: list, task: str = "retrieval.passage") -> list:
    """Retourne une liste de vecteurs 1024-dim. Gère le rate limit 429 avec retry."""
    for attempt in range(4):
        resp = requests.post(
            "https://api.jina.ai/v1/embeddings",
            headers={
                "Authorization": f"Bearer {JINA_API_KEY}",
                "Content-Type": "application/json"
            },
            json={"model": JINA_MODEL, "input": texts, "task": task},
            timeout=60
        )
        if resp.status_code == 200:
            return [item["embedding"] for item in resp.json()["data"]]
        if resp.status_code == 429:
            wait = 70 * (attempt + 1)   # 70s, 140s, 210s
            logging.warning(f"Rate limit Jina AI (429) — attente {wait}s avant retry {attempt+1}/3...")
            time.sleep(wait)
            continue
        raise RuntimeError(f"Jina AI erreur {resp.status_code}: {resp.text[:300]}")
    raise RuntimeError("Rate limit persistant après 4 tentatives — relancer le script.")

# ── Qdrant client ─────────────────────────────────────────────────────────────
def get_qdrant_headers():
    return {
        "api-key": QDRANT_API_KEY,
        "Content-Type": "application/json"
    }

def qdrant_create_collection():
    """Crée la collection Qdrant si elle n'existe pas."""
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}"
    # Vérifie si elle existe
    r = requests.get(url, headers=get_qdrant_headers(), timeout=15)
    if r.status_code == 200:
        existing = r.json().get("result", {}).get("config", {})
        existing_dim = existing.get("params", {}).get("vectors", {}).get("size", 0)
        if existing_dim == JINA_EMBED_DIM:
            logging.info(f"Collection '{QDRANT_COLLECTION}' existe déjà ({existing_dim} dims). OK.")
            return
        else:
            logging.warning(f"Collection existe avec {existing_dim} dims — suppression et recréation.")
            requests.delete(url, headers=get_qdrant_headers(), timeout=15)

    payload = {
        "vectors": {
            "size": JINA_EMBED_DIM,
            "distance": "Cosine"
        }
    }
    r = requests.put(url, headers=get_qdrant_headers(), json=payload, timeout=30)
    if r.status_code not in (200, 201):
        raise RuntimeError(f"Impossible de créer la collection: {r.status_code} {r.text[:300]}")
    logging.info(f"✅ Collection '{QDRANT_COLLECTION}' créée ({JINA_EMBED_DIM} dims, Cosine).")

def qdrant_upsert_batch(points: list):
    """Upload un batch de points dans Qdrant."""
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points"
    r = requests.put(
        url,
        headers=get_qdrant_headers(),
        json={"points": points},
        timeout=60
    )
    if r.status_code not in (200, 201):
        raise RuntimeError(f"Qdrant upsert erreur {r.status_code}: {r.text[:300]}")

def qdrant_count():
    url = f"{QDRANT_URL}/collections/{QDRANT_COLLECTION}/points/count"
    r = requests.post(url, headers=get_qdrant_headers(), json={}, timeout=15)
    if r.status_code == 200:
        return r.json().get("result", {}).get("count", 0)
    return -1

# ── Migration principale ──────────────────────────────────────────────────────
def run_migration():
    check_config()

    # 1. Lire ChromaDB
    logging.info("Connexion à ChromaDB...")
    import chromadb
    client = chromadb.PersistentClient(path=CHROMA_PATH)
    col = client.get_collection(COLLECTION)
    data = col.get(include=['documents', 'metadatas'])

    ids    = data['ids']
    docs   = data['documents']
    metas  = data['metadatas']
    total  = len(ids)
    logging.info(f"ChromaDB : {total} chunks à migrer.")

    # 2. Créer la collection Qdrant
    qdrant_create_collection()

    # 3. Vérifier combien sont déjà dans Qdrant (reprise si script relancé)
    already_in_qdrant = qdrant_count()
    start_from = 0
    if already_in_qdrant > 0:
        start_from = (already_in_qdrant // BATCH_SIZE) * BATCH_SIZE
        logging.info(f"Reprise : {already_in_qdrant} chunks déjà dans Qdrant → départ depuis le chunk {start_from}.")

    # 4. Migrer par batches
    t_start = time.time()
    migrated = already_in_qdrant
    errors   = 0
    total_batches = (total + BATCH_SIZE - 1) // BATCH_SIZE

    for i in range(start_from, total, BATCH_SIZE):
        batch_ids   = ids[i:i+BATCH_SIZE]
        batch_docs  = docs[i:i+BATCH_SIZE]
        batch_metas = metas[i:i+BATCH_SIZE]
        batch_num   = i // BATCH_SIZE + 1

        try:
            # Embed avec Jina AI (retry sur 429 géré dans embed_batch)
            embeddings = embed_batch(batch_docs, task="retrieval.passage")

            # Construire les points Qdrant (IDs numériques stables basés sur index global)
            points = []
            for j, (bid, doc, meta, emb) in enumerate(zip(batch_ids, batch_docs, batch_metas, embeddings)):
                numeric_id = i + j
                payload = {"document": doc, "original_id": bid}
                payload.update({k: v for k, v in meta.items() if v is not None})
                points.append({"id": numeric_id, "vector": emb, "payload": payload})

            # Upload vers Qdrant
            qdrant_upsert_batch(points)
            migrated += len(points)
            errors = 0  # reset compteur d'erreurs après succès

            elapsed = time.time() - t_start
            chunks_done = migrated - already_in_qdrant
            chunks_left = total - migrated
            eta = (elapsed / chunks_done * chunks_left) if chunks_done > 0 else 0
            logging.info(
                f"Batch {batch_num}/{total_batches} — {migrated}/{total} chunks "
                f"({migrated/total*100:.1f}%) — ETA: {eta:.0f}s"
            )

            # Délai préventif entre batches pour rester sous le rate limit Jina AI
            if i + BATCH_SIZE < total:
                time.sleep(BATCH_DELAY)

        except Exception as e:
            logging.error(f"Erreur batch {batch_num}: {e}")
            errors += 1
            if errors >= 5:
                logging.error("Trop d'erreurs. Relancer le script (il reprendra automatiquement).")
                sys.exit(1)
            time.sleep(10)

    # 4. Vérification finale
    count = qdrant_count()
    elapsed_total = time.time() - t_start
    logging.info(f"\n{'='*60}")
    logging.info(f"✅ Migration terminée en {elapsed_total:.0f}s")
    logging.info(f"   Chunks dans ChromaDB : {total}")
    logging.info(f"   Chunks dans Qdrant   : {count}")
    logging.info(f"   Erreurs              : {errors}")
    if count >= total:
        logging.info("✅ Migration complète et vérifiée !")
    else:
        logging.warning(f"⚠️  {total - count} chunks manquants — relancer le script.")

if __name__ == "__main__":
    run_migration()
