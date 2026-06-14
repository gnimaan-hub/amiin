# -*- coding: utf-8 -*-
"""
migrer_base_cosine.py - Amiin Project
Migre la collection ChromaDB de la distance L2 (défaut) vers la distance COSINE
et optionnellement change le modèle d'embedding.

Ce script :
  1. Lit tous les chunks existants de la collection actuelle
  2. Supprime la collection
  3. Recrée la collection avec metadata {"hnsw:space": "cosine"}
  4. Ré-encode tous les documents avec le modèle d'embedding choisi
  5. Réingère tout

Usage:
  python migrer_base_cosine.py                    # Migration cosine avec MiniLM (actuel)
  python migrer_base_cosine.py --model bge-m3     # Migration cosine + upgrade vers BGE-M3
  python migrer_base_cosine.py --dry-run           # Simulation sans modification

Durée estimée : ~5-15 min selon le nombre de chunks et le modèle choisi
"""

import argparse
import time
import chromadb
from sentence_transformers import SentenceTransformer

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

DB_PATH    = './amiin_db'
COLLECTION = 'djibouti_knowledge'

MODELS = {
    'minilm': 'paraphrase-multilingual-MiniLM-L12-v2',   # Actuel — rapide, léger, qualité moyenne
    'bge-m3': 'BAAI/bge-m3',                              # Meilleur — multilingue, plus lourd (~2 Go)
    'e5-large': 'intfloat/multilingual-e5-large',          # Très bon — multilingue, lourd (~2.5 Go)
}

BATCH_SIZE = 64  # Nombre de documents encodés en une fois


# ── MAIN ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Migrer ChromaDB vers distance cosine')
    parser.add_argument('--model', choices=list(MODELS.keys()), default='minilm',
                        help='Modèle d\'embedding à utiliser (défaut: minilm)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Simulation sans modification')
    args = parser.parse_args()

    model_name = MODELS[args.model]
    print("=" * 65)
    print("MIGRATION CHROMADB → DISTANCE COSINE")
    print("=" * 65)
    print(f"  Base: {DB_PATH}")
    print(f"  Modèle: {args.model} ({model_name})")
    print(f"  Mode: {'DRY RUN' if args.dry_run else 'RÉEL'}")

    # ── 1. Lire tous les chunks existants ─────────────────────────────────
    print(f"\n[1/5] Lecture de la collection existante...")
    client = chromadb.PersistentClient(path=DB_PATH)

    try:
        collection = client.get_collection(COLLECTION)
    except Exception as e:
        print(f"  ERREUR: Collection '{COLLECTION}' introuvable: {e}")
        return

    count = collection.count()
    print(f"  Chunks trouvés: {count}")

    if count == 0:
        print("  Rien à migrer.")
        return

    # Récupérer TOUT (par lots de 1000 car ChromaDB a une limite)
    print(f"  Extraction des données...")
    all_ids = []
    all_docs = []
    all_metas = []

    # ChromaDB .get() sans filtre retourne tout
    data = collection.get(include=['documents', 'metadatas'])
    all_ids = data['ids']
    all_docs = data['documents']
    all_metas = data['metadatas']

    print(f"  Extraits: {len(all_ids)} chunks")

    # Vérification
    assert len(all_ids) == len(all_docs) == len(all_metas), "Données incohérentes!"

    # Stats rapides
    from collections import Counter
    cats = Counter(m.get('category', '?') for m in all_metas)
    print(f"  Par catégorie:")
    for c, n in cats.most_common():
        print(f"    {c:<25} {n}")

    if args.dry_run:
        print(f"\n[DRY RUN] Arrêt ici. En mode réel, le script :")
        print(f"  - Supprimerait la collection '{COLLECTION}'")
        print(f"  - La recréerait avec distance COSINE")
        print(f"  - Ré-encoderait {len(all_ids)} documents avec {args.model}")
        print(f"  - Réingérerait tout")
        return

    # ── 2. Supprimer la collection ────────────────────────────────────────
    print(f"\n[2/5] Suppression de la collection existante...")
    client.delete_collection(COLLECTION)
    print(f"  Collection '{COLLECTION}' supprimée.")

    # ── 3. Recréer avec cosine ────────────────────────────────────────────
    print(f"\n[3/5] Création de la nouvelle collection (distance: cosine)...")
    collection = client.create_collection(
        name=COLLECTION,
        metadata={"hnsw:space": "cosine"}
    )
    print(f"  Collection '{COLLECTION}' créée avec distance COSINE.")

    # ── 4. Charger le modèle et ré-encoder ────────────────────────────────
    print(f"\n[4/5] Chargement du modèle '{model_name}'...")
    t0 = time.time()
    model = SentenceTransformer(model_name)
    print(f"  Modèle chargé en {time.time()-t0:.1f}s")

    print(f"  Encodage de {len(all_docs)} documents (batch={BATCH_SIZE})...")
    t0 = time.time()

    all_embeddings = []
    for i in range(0, len(all_docs), BATCH_SIZE):
        batch = all_docs[i:i+BATCH_SIZE]

        # Pour les modèles E5, ajouter le préfixe "passage: "
        if 'e5' in args.model:
            batch = [f"passage: {doc}" for doc in batch]

        embs = model.encode(batch, show_progress_bar=False)
        all_embeddings.extend(embs.tolist())

        done = min(i + BATCH_SIZE, len(all_docs))
        if done % 200 == 0 or done == len(all_docs):
            elapsed = time.time() - t0
            rate = done / elapsed if elapsed > 0 else 0
            eta = (len(all_docs) - done) / rate if rate > 0 else 0
            print(f"    {done}/{len(all_docs)} ({done*100//len(all_docs)}%) "
                  f"| {rate:.0f} docs/s | ETA: {eta:.0f}s")

    print(f"  Encodage terminé en {time.time()-t0:.1f}s")

    # ── 5. Réingestion ────────────────────────────────────────────────────
    print(f"\n[5/5] Ingestion dans la nouvelle collection...")
    t0 = time.time()

    # Ingérer par lots de 500 (limite ChromaDB)
    ingeres = 0
    erreurs = 0
    for i in range(0, len(all_ids), 500):
        batch_ids   = all_ids[i:i+500]
        batch_embs  = all_embeddings[i:i+500]
        batch_docs  = all_docs[i:i+500]
        batch_metas = all_metas[i:i+500]

        try:
            collection.add(
                ids=batch_ids,
                embeddings=batch_embs,
                documents=batch_docs,
                metadatas=batch_metas
            )
            ingeres += len(batch_ids)
        except Exception as e:
            print(f"    ERREUR lot {i}-{i+500}: {e}")
            erreurs += len(batch_ids)

        if (i + 500) % 1000 == 0:
            print(f"    {min(i+500, len(all_ids))}/{len(all_ids)}...")

    print(f"  Ingestion terminée en {time.time()-t0:.1f}s")
    print(f"  Ingérés: {ingeres} | Erreurs: {erreurs}")

    # ── Vérification finale ───────────────────────────────────────────────
    final_count = collection.count()
    print(f"\n{'='*65}")
    print(f"MIGRATION TERMINÉE")
    print(f"  Avant: {count} chunks (L2)")
    print(f"  Après: {final_count} chunks (COSINE)")
    print(f"  Modèle: {args.model} ({model_name})")

    if final_count == count:
        print(f"  ✅ Tous les chunks ont été migrés avec succès!")
    else:
        print(f"  ⚠️  Différence: {count - final_count} chunks manquants")

    print(f"{'='*65}")


if __name__ == '__main__':
    main()
