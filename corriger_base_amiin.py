# -*- coding: utf-8 -*-
"""
corriger_base_amiin.py - Script de correction de la base ChromaDB
Corrige les 6 problèmes identifiés dans le diagnostic :

  1. Réindexe la composition du gouvernement (chunk tronqué → contenu complet)
  2. Corrige les 33 chunks sans source (source='?')
  3. Supprime les doublons (5 groupes identifiés)
  4. Redécoupe les 11 chunks géants (>700 mots)
  5. Vérifie et vide la queue de 800 embeddings
  6. Fusionne les micro-chunks de l'annuaire (<50 mots)

Usage:
  python corriger_base_amiin.py                # Exécute toutes les corrections
  python corriger_base_amiin.py --dry-run      # Prévisualise sans modifier

IMPORTANT: Faire un backup de amiin_db/ AVANT de lancer ce script !
  xcopy /E /I amiin_db amiin_db_backup
"""

import argparse
import chromadb
from sentence_transformers import SentenceTransformer
from collections import Counter, defaultdict

DB_PATH    = './amiin_db'
COLLECTION = 'djibouti_knowledge'
MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2'

MAX_MOTS   = 480
OVERLAP    = 50

# ══════════════════════════════════════════════════════════════════════════════
# CORRECTION 1 : Composition du gouvernement (chunk tronqué)
# ══════════════════════════════════════════════════════════════════════════════

GOUVERNEMENT_CHUNKS = [
    {
        "id": "gouv_composition_001",
        "document": """Composition du gouvernement de la République de Djibouti

Chef de l'État : Président ISMAÏL OMAR GUELLEH (depuis 1999, réélu en 2021 pour un 5e mandat)

Premier Ministre : M. ABDOULKADER KAMIL MOHAMED
Tél : +253 21 32 52 14 | Email : contact@primature.gouv.dj | Site : primature.gouv.dj

Le gouvernement comprend 26 membres : 1 Premier Ministre, 21 Ministres, 2 Ministres Délégués et 2 Secrétaires d'État.

Ministres :
1. M. Ali Hassan Bahdon — Justice et Affaires Pénitentiaires, Droits de l'Homme | Tél : +253 21 33 33 33 | justice.gouv.dj
2. M. Ilyas Moussa Dawaleh — Économie et Finances, Industrie | Tél : +253 21 32 51 05 | economie.gouv.dj
3. M. Abdoulkader Houssein Omar — Affaires Étrangères, Coopération Internationale, Porte-Parole | Tél : +253 21 35 24 71 | diplomatie.gouv.dj
4. M. Hassan Omar Mohamed Bourhan — Défense, Relations avec le Parlement | Tél : +253 21 35 20 34
5. M. Said Nouh Hassan — Intérieur | Tél : +253 21 35 25 42 | interieur.gouv.dj
6. M. Isman Ibrahim Robleh — Budget | Tél : +253 21 32 53 01 | budget.gouv.dj
7. Dr Ahmed Robleh Abdilleh — Santé | Tél : +253 21 35 19 31 | sante.gouv.dj
8. M. Moustapha Mohamed Mahamoud — Éducation Nationale, Formation Professionnelle | Tél : +253 21 35 09 97
9. Dr Nabil Mohamed Ahmed — Enseignement Supérieur et Recherche | Tél : +253 21 35 12 10 | mensur.gouv.dj
10. Mme Mouna Osman Aden — Femme et Famille | Tél : +253 21 35 34 09 | famille.gouv.dj
11. M. Mohamed Ahmed Awaleh — Agriculture, Eau, Pêche, Élevage, Ressources Halieutiques | Tél : +253 21 35 12 97
12. M. Hassan Houmed Ibrahim — Infrastructures et Équipement | Tél : +253 21 35 79 13""",
        "metadata": {
            "title": "Composition du gouvernement djiboutien - Premier Ministre et Ministres (partie 1)",
            "category": "gouvernement",
            "source": "presidence.dj",
            "url": "https://www.presidence.dj/composition",
            "type": "composition_gouvernement"
        }
    },
    {
        "id": "gouv_composition_002",
        "document": """Composition du gouvernement de Djibouti (suite)

13. M. Mohamed Abdoulkader Moussa Helem — Environnement et Développement Durable | Tél : +251 35 10 20
14. M. Moumin Hassan Barreh — Affaires Musulmanes et Biens Wakfs | Tél : +253 21 32 54 62
15. Mme Ouloufa Ismail Abdo — Affaires Sociales et Solidarités | Tél : +253 21 32 54 81 | sociales.gouv.dj
16. M. Yonis Ali Guedi — Énergie, Ressources Naturelles | Tél : +253 21 32 54 31
17. M. Omar Abdi Said — Travail, Formalisation, Protection Sociale | Tél : +253 21 35 04 97
18. Mme Amina Abdi Aden — Ville, Urbanisme et Habitat | Tél : +253 21 35 00 06 | logement.gouv.dj
19. M. Radwan Abdillahi Bahdon — Communication, Postes et Télécommunications | Tél : +253 21 31 11 80 | communication.gouv.dj
20. M. Mohamed Warsama Dirieh — Commerce et Tourisme | Tél : +253 21 32 54 41
21. Dr Hibo Moumin Assoweh — Jeunesse et Culture | Tél : +253 21 35 58 86

Ministres Délégués :
22. M. Kassim Haroun Ali — Décentralisation | Tél : +253 21 35 97 87 | decentralisation.gouv.dj
23. Mme Mariam Hamadou Ali — Économie Numérique et Innovation | Tél : +253 21 33 92 31 | numerique.gouv.dj

Secrétaires d'État :
24. Mme Safia Mohamed Ali Gadileh — Investissements et Développement du secteur privé | Tél : +253 21 33 99 50 | investissement.gouv.dj
25. M. Hassan Mohamed Kamil — Sports

Le Premier Ministre M. Abdoulkader Kamil Mohamed coordonne l'action gouvernementale. Il a été nommé par décret n°2016-109/PRE du 11 mai 2016.""",
        "metadata": {
            "title": "Composition du gouvernement djiboutien - Ministres suite, Délégués et Secrétaires d'État (partie 2)",
            "category": "gouvernement",
            "source": "presidence.dj",
            "url": "https://www.presidence.dj/composition",
            "type": "composition_gouvernement"
        }
    }
]

# ══════════════════════════════════════════════════════════════════════════════
# CORRECTION 2 : Source manquante pour les chunks presidence.dj
# ══════════════════════════════════════════════════════════════════════════════

SOURCE_FIXES = {
    # ID prefix → source correcte
    "https://www.presidence.dj": "presidence.dj",
}

# ══════════════════════════════════════════════════════════════════════════════
# FONCTIONS
# ══════════════════════════════════════════════════════════════════════════════

def correction_1_gouvernement(collection, model, dry_run=False):
    """Remplace le chunk tronqué par le contenu complet."""
    print("\n[1/6] COMPOSITION DU GOUVERNEMENT")
    print("─" * 50)

    # Supprimer l'ancien chunk tronqué
    old_id = "https://www.presidence.dj/composition_1"
    try:
        data = collection.get(ids=[old_id])
        if data['ids']:
            old_doc = data['documents'][0] if data['documents'] else ''
            print(f"  Ancien chunk trouvé: {len(old_doc.split())} mots (tronqué)")
            if not dry_run:
                collection.delete(ids=[old_id])
                print(f"  ✅ Ancien chunk supprimé")
        else:
            print(f"  ⚠️ Ancien chunk non trouvé (déjà supprimé?)")
    except Exception:
        print(f"  ⚠️ Ancien chunk non trouvé")

    # Insérer les nouveaux chunks complets
    for chunk in GOUVERNEMENT_CHUNKS:
        mots = len(chunk['document'].split())
        print(f"  Nouveau: {chunk['id']} ({mots} mots)")
        if not dry_run:
            emb = model.encode(chunk['document']).tolist()
            try:
                collection.add(
                    ids=[chunk['id']],
                    embeddings=[emb],
                    documents=[chunk['document']],
                    metadatas=[chunk['metadata']]
                )
                print(f"  ✅ Ingéré")
            except Exception as e:
                print(f"  ❌ Erreur: {e}")

    print(f"  {'[DRY RUN]' if dry_run else '[OK]'} 1 chunk tronqué → 2 chunks complets (26 ministres)")


def correction_2_sources(collection, dry_run=False):
    """Corrige les chunks avec source='?' en ajoutant la bonne source."""
    print("\n[2/6] CORRECTION DES SOURCES MANQUANTES")
    print("─" * 50)

    data = collection.get(include=['metadatas', 'documents', 'embeddings'])
    fixes = 0

    for i, (id_, meta) in enumerate(zip(data['ids'], data['metadatas'])):
        if meta.get('source') in (None, '', '?'):
            # Déduire la source de l'ID
            new_source = None
            if 'presidence.dj' in id_:
                new_source = 'presidence.dj'
            elif 'egouv.dj' in id_:
                new_source = 'egouv.dj'
            elif 'justice.gouv.dj' in id_:
                new_source = 'justice.gouv.dj'

            if new_source:
                meta_copy = dict(meta)
                meta_copy['source'] = new_source
                print(f"  {id_[:50]} → source='{new_source}'")

                if not dry_run:
                    collection.update(
                        ids=[id_],
                        metadatas=[meta_copy]
                    )
                fixes += 1

    print(f"  {'[DRY RUN]' if dry_run else '[OK]'} {fixes} chunks corrigés")


def correction_3_doublons(collection, dry_run=False):
    """Supprime les chunks dupliqués (garde le premier)."""
    print("\n[3/6] SUPPRESSION DES DOUBLONS")
    print("─" * 50)

    data = collection.get(include=['documents'])
    seen = {}
    to_delete = []

    for id_, doc in zip(data['ids'], data['documents']):
        # Hash sur les 200 premiers caractères
        key = doc[:200] if doc else ''
        if key in seen:
            to_delete.append(id_)
            print(f"  Doublon: {id_[:50]} (identique à {seen[key][:50]})")
        else:
            seen[key] = id_

    if to_delete:
        if not dry_run:
            for i in range(0, len(to_delete), 500):
                collection.delete(ids=to_delete[i:i+500])
        print(f"  {'[DRY RUN]' if dry_run else '[OK]'} {len(to_delete)} doublons supprimés")
    else:
        print(f"  Aucun doublon trouvé")


def correction_4_chunks_geants(collection, model, dry_run=False):
    """Redécoupe les chunks de plus de 700 mots."""
    print("\n[4/6] REDÉCOUPAGE DES CHUNKS GÉANTS")
    print("─" * 50)

    data = collection.get(include=['documents', 'metadatas', 'embeddings'])
    to_delete = []
    to_add = []

    for id_, doc, meta in zip(data['ids'], data['documents'], data['metadatas']):
        mots = doc.split()
        if len(mots) > 700:
            print(f"  Géant: {id_[:50]} ({len(mots)} mots)")
            to_delete.append(id_)

            # Découper en sous-chunks
            i = 0
            part = 0
            while i < len(mots):
                fin = min(i + MAX_MOTS, len(mots))
                sous_texte = ' '.join(mots[i:fin])
                part += 1

                new_meta = dict(meta)
                old_title = new_meta.get('title', '')
                new_meta['title'] = f"{old_title} (partie {part})" if old_title else f"Partie {part}"

                to_add.append({
                    'id': f"{id_}_p{part}",
                    'document': sous_texte,
                    'metadata': new_meta
                })

                i = fin - OVERLAP if fin < len(mots) else fin

            print(f"    → Découpé en {part} sous-chunks")

    if to_delete:
        if not dry_run:
            for i in range(0, len(to_delete), 500):
                collection.delete(ids=to_delete[i:i+500])

            for chunk in to_add:
                emb = model.encode(chunk['document']).tolist()
                try:
                    collection.add(
                        ids=[chunk['id']],
                        embeddings=[emb],
                        documents=[chunk['document']],
                        metadatas=[chunk['metadata']]
                    )
                except Exception as e:
                    print(f"    ❌ Erreur: {e}")

        print(f"  {'[DRY RUN]' if dry_run else '[OK]'} {len(to_delete)} géants → {len(to_add)} sous-chunks")
    else:
        print(f"  Aucun chunk géant trouvé")


def correction_5_queue(dry_run=False):
    """Vérifie et documente la queue d'embeddings."""
    print("\n[5/6] VÉRIFICATION DE LA QUEUE D'EMBEDDINGS")
    print("─" * 50)

    import sqlite3
    import os

    db_file = os.path.join(DB_PATH, 'chroma.sqlite3')
    if not os.path.exists(db_file):
        print(f"  ⚠️ Fichier {db_file} non trouvé")
        return

    db = sqlite3.connect(db_file)
    cursor = db.cursor()

    cursor.execute("SELECT COUNT(*) FROM embeddings_queue")
    count = cursor.fetchone()[0]
    print(f"  Items en queue: {count}")

    if count > 0:
        cursor.execute("SELECT id, operation FROM embeddings_queue LIMIT 10")
        rows = cursor.fetchall()
        ops = Counter(r[1] for r in rows)
        print(f"  Types d'opérations: {dict(ops)}")

        # Vérifier si ces IDs existent déjà dans la collection principale
        cursor.execute("SELECT id FROM embeddings_queue")
        queue_ids = [r[0] for r in cursor.fetchall()]

        cursor.execute("SELECT embedding_id FROM embeddings")
        main_ids = set(r[0] for r in cursor.fetchall())

        already_in = sum(1 for qid in queue_ids if qid in main_ids)
        missing = sum(1 for qid in queue_ids if qid not in main_ids)

        print(f"  Déjà dans la collection principale: {already_in}")
        print(f"  Manquants (non encore indexés): {missing}")

        if missing > 0:
            print(f"  ⚠️ {missing} embeddings en queue n'ont pas été finalisés.")
            print(f"     Ce sont probablement des chunks du Code de Commerce.")
            print(f"     Relancer l'indexeur correspondant pour les réintégrer.")

        if count > 0 and not dry_run:
            # Vider la queue (les chunks sont déjà dans la collection ou seront réindexés)
            cursor.execute("DELETE FROM embeddings_queue")
            db.commit()
            print(f"  ✅ Queue vidée ({count} items)")

    db.close()


def correction_6_micro_chunks(collection, model, dry_run=False):
    """Fusionne les micro-chunks de l'annuaire (<50 mots) par sous-catégorie."""
    print("\n[6/6] FUSION DES MICRO-CHUNKS ANNUAIRE")
    print("─" * 50)

    data = collection.get(include=['documents', 'metadatas'])

    # Identifier les micro-chunks de l'annuaire
    micros_by_scat = defaultdict(list)
    for id_, doc, meta in zip(data['ids'], data['documents'], data['metadatas']):
        if meta.get('source') == 'Annuaire Djibouti - Vie Pratique' and len(doc.split()) < 60:
            scat = meta.get('sous_categorie', meta.get('secteur', 'autre'))
            micros_by_scat[scat].append((id_, doc, meta))

    total_micros = sum(len(v) for v in micros_by_scat.values())
    print(f"  Micro-chunks identifiés: {total_micros}")

    to_delete = []
    to_add = []

    for scat, chunks in micros_by_scat.items():
        if len(chunks) < 2:
            continue  # Pas besoin de fusionner un chunk isolé

        # Fusionner les chunks de cette sous-catégorie
        buffer_ids = []
        buffer_docs = []
        buffer_mots = 0
        merge_num = 0

        for id_, doc, meta in chunks:
            mots = len(doc.split())
            buffer_ids.append(id_)
            buffer_docs.append(doc)
            buffer_mots += mots

            if buffer_mots >= 200:  # Seuil de fusion
                merge_num += 1
                merged_doc = '\n\n---\n\n'.join(buffer_docs)

                # Construire le titre
                secteur = meta.get('secteur', '')
                noms_list = []
                for _, d, _ in [(i, d, m) for i, d, m in chunks if i in buffer_ids]:
                    first_line = d.split('\n')[0]
                    noms_list.append(first_line.split('(')[0].strip())

                titre = f"{', '.join(noms_list[:3])} | {scat} | {secteur}"
                if len(noms_list) > 3:
                    titre = f"{noms_list[0]} et {len(noms_list)-1} autres | {scat} | {secteur}"

                new_meta = {
                    'title': titre,
                    'category': 'vie_pratique',
                    'source': 'Annuaire Djibouti - Vie Pratique',
                    'type': 'annuaire_entree',
                    'secteur': secteur,
                    'sous_categorie': scat,
                }

                to_delete.extend(buffer_ids)
                to_add.append({
                    'id': f"ann_merged_{scat.replace(' ', '_').lower()}_{merge_num:03d}",
                    'document': merged_doc,
                    'metadata': new_meta
                })

                buffer_ids, buffer_docs, buffer_mots = [], [], 0

        # Vider le reste du buffer
        if buffer_docs and len(buffer_ids) > 1:
            merge_num += 1
            merged_doc = '\n\n---\n\n'.join(buffer_docs)
            secteur = chunks[0][2].get('secteur', '')
            to_delete.extend(buffer_ids)
            to_add.append({
                'id': f"ann_merged_{scat.replace(' ', '_').lower()}_{merge_num:03d}",
                'document': merged_doc,
                'metadata': {
                    'title': f"Divers {scat} | {secteur}",
                    'category': 'vie_pratique',
                    'source': 'Annuaire Djibouti - Vie Pratique',
                    'type': 'annuaire_entree',
                    'secteur': secteur,
                    'sous_categorie': scat,
                }
            })

    print(f"  Chunks à supprimer: {len(to_delete)}")
    print(f"  Chunks fusionnés à créer: {len(to_add)}")

    if to_delete and not dry_run:
        # Supprimer les micro-chunks
        for i in range(0, len(to_delete), 500):
            collection.delete(ids=to_delete[i:i+500])

        # Ajouter les chunks fusionnés
        for chunk in to_add:
            emb = model.encode(chunk['document']).tolist()
            try:
                collection.add(
                    ids=[chunk['id']],
                    embeddings=[emb],
                    documents=[chunk['document']],
                    metadatas=[chunk['metadata']]
                )
            except Exception as e:
                print(f"    ❌ Erreur: {e}")

    print(f"  {'[DRY RUN]' if dry_run else '[OK]'} {len(to_delete)} micro-chunks → {len(to_add)} chunks fusionnés")


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description='Corriger la base Amiin')
    parser.add_argument('--dry-run', action='store_true', help='Simulation')
    args = parser.parse_args()

    print("=" * 65)
    print("CORRECTION DE LA BASE AMIIN")
    print("=" * 65)
    if args.dry_run:
        print("⚠️  MODE DRY RUN — Aucune modification ne sera faite")
    else:
        print("⚠️  MODE RÉEL — La base sera modifiée !")
        print("   Assurez-vous d'avoir fait un backup : xcopy /E /I amiin_db amiin_db_backup")

    # Charger
    print(f"\nChargement...")
    model = SentenceTransformer(MODEL_NAME)
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(COLLECTION)
    count_before = collection.count()
    print(f"Base: {count_before} chunks")

    # Corrections
    correction_1_gouvernement(collection, model, args.dry_run)
    correction_2_sources(collection, args.dry_run)
    correction_3_doublons(collection, args.dry_run)
    correction_4_chunks_geants(collection, model, args.dry_run)
    correction_5_queue(args.dry_run)
    correction_6_micro_chunks(collection, model, args.dry_run)

    # Bilan
    count_after = collection.count()
    print(f"\n{'='*65}")
    print(f"CORRECTIONS TERMINÉES")
    print(f"  Avant: {count_before} chunks")
    print(f"  Après: {count_after} chunks")
    print(f"  Delta: {count_after - count_before:+d}")
    print(f"{'='*65}")


if __name__ == '__main__':
    main()
