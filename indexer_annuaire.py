# -*- coding: utf-8 -*-
"""
indexer_annuaire.py - Amiin Project
Transforme le JSON annuaire_djibouti_complet_v2.json en chunks et les ingère dans ChromaDB.

Stratégie de chunking :
  1. Fiches sectorielles → 1 chunk par secteur (résumé + conseils)
  2. Entrées individuelles → regroupées par sous-catégorie (ex: toutes les pharmacies ensemble)
     pour atteindre la cible de 280-480 mots par chunk.
     Si une entrée enrichie dépasse 480 mots seule → chunk individuel.

Metadata compatibles avec le reste de la base Amiin :
  - category: 'vie_pratique'
  - source: 'Annuaire Djibouti - Vie Pratique'
  - title: descriptif du chunk
  - type: 'fiche_sectorielle' ou 'annuaire_entree'
  - secteur: catégorie de l'annuaire (Santé, Restauration, etc.)
  - sous_categorie: sous-catégorie (Pharmacie, Hôtel 5 étoiles, etc.)

Usage:
  python indexer_annuaire.py
  python indexer_annuaire.py --json chemin/vers/annuaire.json
  python indexer_annuaire.py --dry-run   (prévisualise sans ingérer)
"""

import json
import argparse
import re
from collections import defaultdict

import chromadb
from sentence_transformers import SentenceTransformer

# ── PARAMÈTRES ────────────────────────────────────────────────────────────────

DB_PATH    = './amiin_db'
JSON_PATH  = './annuaire_djibouti_complet_v2.json'
CATEGORIE  = 'vie_pratique'
SOURCE     = 'Annuaire Djibouti - Vie Pratique'

MIN_MOTS   = 280
CIBLE      = 370
MAX_MOTS   = 480
OVERLAP    = 50

# ── CONSTRUCTION DU TEXTE D'UNE ENTRÉE ───────────────────────────────────────

def entree_vers_texte(e):
    """Transforme une entrée JSON en texte lisible pour le chunk."""
    parties = []

    # Nom et type
    nom = e.get('nom', '')
    scat = e.get('sous_categorie', '')
    parties.append(f"{nom} ({scat})")

    # Localisation
    loc = []
    if e.get('adresse'):
        loc.append(e['adresse'])
    if e.get('quartier'):
        loc.append(f"Quartier {e['quartier']}")
    if loc:
        parties.append(f"Adresse : {', '.join(loc)}")

    # Contacts
    contacts = []
    if e.get('telephone'):
        contacts.append(f"Tél : {e['telephone']}")
    if e.get('telephone2'):
        contacts.append(f"Tél 2 : {e['telephone2']}")
    if e.get('email'):
        contacts.append(f"Email : {e['email']}")
    if e.get('site_web'):
        contacts.append(f"Site : {e['site_web']}")
    if contacts:
        parties.append(' | '.join(contacts))

    # Horaires
    if e.get('horaires'):
        parties.append(f"Horaires : {e['horaires']}")

    # Description de base
    if e.get('description'):
        parties.append(e['description'])

    # Enrichissement (le cœur de la valeur ajoutée)
    enr = e.get('enrichissement', {})
    if enr:
        # Champs textuels simples
        for cle in ['type', 'standing', 'nom_complet', 'cuisine', 'specialite',
                     'specialites', 'gamme_prix', 'prix', 'prix_indicatif',
                     'groupe', 'statut', 'anciennete', 'annee', 'annee_creation',
                     'role', 'historique', 'medecin', 'medecin_principal',
                     'medecin_fondateur', 'description', 'description_enrichie',
                     'acces', 'numero_urgence', 'code', 'code_iata',
                     'nb_chambres', 'chambres', 'nb_lits', 'nb_medecins',
                     'nb_boutiques', 'boutiques', 'acronyme', 'developpeur',
                     'operateur', 'directrice', 'gm_actuel', 'style',
                     'surface', 'avis_resume', 'avis_tripadvisor',
                     'tripadvisor', 'facebook', 'facebook_likes',
                     'nb_likes_facebook']:
            val = enr.get(cle)
            if val is not None:
                if isinstance(val, list):
                    parties.append(f"{cle.replace('_', ' ').capitalize()} : {', '.join(str(v) for v in val)}")
                else:
                    parties.append(f"{cle.replace('_', ' ').capitalize()} : {val}")

        # Listes de services/équipements
        for cle_liste in ['services', 'equipements', 'enseignes', 'enseignes_presentes',
                          'specialites', 'specialites_disponibles', 'services_diagnostiques',
                          'compagnies', 'banques_interconnectees', 'banques',
                          'installations', 'restaurants_internes']:
            val = enr.get(cle_liste)
            if val and isinstance(val, list):
                parties.append(f"{cle_liste.replace('_', ' ').capitalize()} : {', '.join(str(v) for v in val)}")

        # Forfaits (dict)
        forfaits = enr.get('forfaits') or enr.get('forfaits_indicatifs')
        if forfaits and isinstance(forfaits, dict):
            f_parts = [f"{k}: {v}" for k, v in forfaits.items()]
            parties.append(f"Forfaits : {' | '.join(f_parts)}")

        # Codes USSD
        codes = enr.get('codes') or enr.get('codes_utiles')
        if codes and isinstance(codes, dict):
            c_parts = [f"{k}: {v}" for k, v in codes.items()]
            parties.append(f"Codes utiles : {' | '.join(c_parts)}")

        # Conditions
        cond = enr.get('conditions')
        if cond:
            parties.append(f"Conditions : {cond}")

        # Tips (toujours en dernier - le plus riche)
        tips = enr.get('tips') or enr.get('tips_detailles')
        if tips:
            parties.append(f"Conseils : {tips}")

        # Contacts enrichis
        for cle_contact in ['telephone', 'whatsapp', 'email', 'site_web',
                            'adresse_bp', 'adresse', 'adresse_detail']:
            val = enr.get(cle_contact)
            if val and cle_contact not in ['tips', 'tips_detailles']:
                parties.append(f"{cle_contact.replace('_', ' ').capitalize()} : {val}")

    return '\n'.join(parties)


# ── CONSTRUCTION DES CHUNKS SECTORIELS ────────────────────────────────────────

def chunks_sectoriels(annuaire):
    """Crée un chunk par fiche sectorielle."""
    chunks = []
    secteurs = annuaire.get('fiches_sectorielles', {})

    for nom_secteur, fiche in secteurs.items():
        texte_parts = [
            f"Guide {nom_secteur} à Djibouti",
            f"Nombre d'établissements : {fiche.get('nb_entrees', '?')}",
        ]

        if fiche.get('resume'):
            texte_parts.append(fiche['resume'])
        if fiche.get('conseils_pratiques'):
            texte_parts.append(f"Conseils pratiques : {fiche['conseils_pratiques']}")
        if fiche.get('sous_categories'):
            texte_parts.append(f"Sous-catégories : {', '.join(fiche['sous_categories'])}")

        texte = '\n'.join(texte_parts)
        slug = re.sub(r'[^a-z0-9]+', '_', nom_secteur.lower()).strip('_')

        chunks.append({
            'id':       f"ann_sect_{slug}",
            'document': texte,
            'metadata': {
                'title':    f"Guide {nom_secteur} - Vie pratique Djibouti",
                'category': CATEGORIE,
                'source':   SOURCE,
                'type':     'fiche_sectorielle',
                'secteur':  nom_secteur,
            }
        })

    return chunks


# ── REGROUPEMENT DES ENTRÉES PAR SOUS-CATÉGORIE ──────────────────────────────

def chunks_entrees(annuaire):
    """Regroupe les entrées par (catégorie, sous_catégorie) et produit des chunks."""
    chunks = []

    # Grouper par (catégorie, sous_catégorie)
    groupes = defaultdict(list)
    for e in annuaire.get('entrees', []):
        cle = (e.get('categorie', ''), e.get('sous_categorie', ''))
        groupes[cle].append(e)

    for (cat, scat), entrees in groupes.items():
        # Convertir chaque entrée en texte
        textes = []
        for e in entrees:
            txt = entree_vers_texte(e)
            textes.append((e, txt))

        # Agglomérer les entrées courtes, isoler les longues
        buffer_entrees = []
        buffer_texte = []
        buffer_mots = 0
        chunk_num = 0

        for e, txt in textes:
            mots = len(txt.split())

            # Entrée longue seule → chunk individuel
            if mots > MAX_MOTS:
                # D'abord vider le buffer
                if buffer_texte:
                    chunk_num += 1
                    chunks.append(_emettre_chunk_groupe(
                        buffer_entrees, buffer_texte, cat, scat, chunk_num
                    ))
                    buffer_entrees, buffer_texte, buffer_mots = [], [], 0

                # Découper l'entrée longue
                sous_chunks = _decouper_long(txt, e, cat, scat)
                chunks.extend(sous_chunks)
                continue

            # Si ajouter déborderait
            if buffer_mots + mots > MAX_MOTS:
                if buffer_mots >= MIN_MOTS:
                    # Émettre le buffer actuel
                    chunk_num += 1
                    chunks.append(_emettre_chunk_groupe(
                        buffer_entrees, buffer_texte, cat, scat, chunk_num
                    ))
                    buffer_entrees, buffer_texte, buffer_mots = [], [], 0

            buffer_entrees.append(e)
            buffer_texte.append(txt)
            buffer_mots += mots

            if buffer_mots >= CIBLE:
                chunk_num += 1
                chunks.append(_emettre_chunk_groupe(
                    buffer_entrees, buffer_texte, cat, scat, chunk_num
                ))
                buffer_entrees, buffer_texte, buffer_mots = [], [], 0

        # Vider le buffer restant
        if buffer_texte:
            chunk_num += 1
            chunks.append(_emettre_chunk_groupe(
                buffer_entrees, buffer_texte, cat, scat, chunk_num
            ))

    return chunks


def _emettre_chunk_groupe(entrees, textes, cat, scat, num):
    """Produit un chunk à partir d'un groupe d'entrées."""
    noms = [e['nom'] for e in entrees]
    document = '\n\n---\n\n'.join(textes)

    # Titre descriptif
    if len(noms) == 1:
        titre = f"{noms[0]} | {scat} | {cat}"
    elif len(noms) <= 3:
        titre = f"{', '.join(noms)} | {scat} | {cat}"
    else:
        titre = f"{noms[0]} et {len(noms)-1} autres | {scat} | {cat}"

    slug_cat = re.sub(r'[^a-z0-9]+', '_', cat.lower()).strip('_')
    slug_scat = re.sub(r'[^a-z0-9]+', '_', scat.lower()).strip('_')

    return {
        'id':       f"ann_{slug_cat}_{slug_scat}_{num:03d}",
        'document': document,
        'metadata': {
            'title':          titre,
            'category':       CATEGORIE,
            'source':         SOURCE,
            'type':           'annuaire_entree',
            'secteur':        cat,
            'sous_categorie': scat,
            'noms':           ', '.join(noms[:10]),
        }
    }


def _decouper_long(texte, entree, cat, scat):
    """Découpe un texte trop long en sous-chunks avec overlap."""
    mots = texte.split()
    chunks = []
    i = 0
    part = 0

    while i < len(mots):
        fin = min(i + MAX_MOTS, len(mots))
        sous_texte = ' '.join(mots[i:fin])
        part += 1

        slug_cat = re.sub(r'[^a-z0-9]+', '_', cat.lower()).strip('_')
        slug_nom = re.sub(r'[^a-z0-9]+', '_', entree['nom'].lower()).strip('_')[:30]

        chunks.append({
            'id':       f"ann_{slug_cat}_{slug_nom}_{part:02d}",
            'document': sous_texte,
            'metadata': {
                'title':          f"{entree['nom']} (partie {part}) | {scat} | {cat}",
                'category':       CATEGORIE,
                'source':         SOURCE,
                'type':           'annuaire_entree',
                'secteur':        cat,
                'sous_categorie': scat,
                'noms':           entree['nom'],
            }
        })

        i = fin - OVERLAP if fin < len(mots) else fin

    return chunks


# ── SUPPRESSION DES ANCIENS CHUNKS ────────────────────────────────────────────

def supprimer_anciens(collection):
    """Supprime tous les chunks dont la source est l'annuaire."""
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == SOURCE]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"  [OK] {len(ids)} anciens chunks annuaire supprimés")
    else:
        print("  [INFO] Aucun ancien chunk annuaire")


# ── INGESTION ─────────────────────────────────────────────────────────────────

def ingerer(chunks, collection, model):
    """Encode et ingère les chunks dans ChromaDB."""
    print(f"\n  Ingestion de {len(chunks)} chunks...")
    ingeres = doublons = 0

    for k, chunk in enumerate(chunks):
        emb = model.encode(chunk['document']).tolist()
        try:
            collection.add(
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

    print(f"  [OK] Ingérés: {ingeres} | Doublons: {doublons}")
    return ingeres


# ── STATISTIQUES ──────────────────────────────────────────────────────────────

def afficher_stats(chunks):
    """Affiche les statistiques des chunks générés."""
    mots_list = [len(c['document'].split()) for c in chunks]

    print(f"\n  Chunks totaux : {len(chunks)}")
    if not mots_list:
        return

    print(f"  Mots — Moy: {sum(mots_list)//len(mots_list)} | "
          f"Min: {min(mots_list)} | Max: {max(mots_list)}")

    # Distribution
    from collections import Counter
    dist = Counter()
    for w in mots_list:
        if w < 100:   dist['<100'] += 1
        elif w < 200: dist['100-200'] += 1
        elif w < 280: dist['200-280'] += 1
        elif w < 370: dist['280-370'] += 1
        elif w < 480: dist['370-480'] += 1
        else:         dist['480+'] += 1

    for k in ['<100', '100-200', '200-280', '280-370', '370-480', '480+']:
        bar = '█' * (dist.get(k, 0))
        print(f"    {k:<10} {dist.get(k, 0):>4}  {bar}")

    # Par type
    types = Counter(c['metadata']['type'] for c in chunks)
    print(f"\n  Par type :")
    for t, n in types.most_common():
        print(f"    {t:<25} {n}")

    # Par secteur
    secteurs = Counter(c['metadata'].get('secteur', '?') for c in chunks)
    print(f"\n  Par secteur :")
    for s, n in secteurs.most_common():
        print(f"    {s:<25} {n}")

    # Exemples de titres
    print(f"\n  Exemples de titres :")
    step = max(1, len(chunks) // 8)
    for c in chunks[::step][:8]:
        mots = len(c['document'].split())
        print(f"    [{mots:>3}m] {c['metadata']['title'][:80]}")


# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Indexer l\'annuaire de vie pratique dans ChromaDB')
    parser.add_argument('--json', default=JSON_PATH,
                        help='Chemin vers le fichier JSON annuaire')
    parser.add_argument('--dry-run', action='store_true',
                        help='Prévisualiser sans ingérer dans ChromaDB')
    args = parser.parse_args()

    print("=" * 65)
    print("INDEXATION ANNUAIRE VIE PRATIQUE - AMIIN")
    print("=" * 65)

    # 1. Charger le JSON
    print(f"\n[1/5] Chargement {args.json}...")
    with open(args.json, 'r', encoding='utf-8') as f:
        annuaire = json.load(f)

    nb_entrees = len(annuaire.get('entrees', []))
    nb_secteurs = len(annuaire.get('fiches_sectorielles', {}))
    nb_enrichies = sum(1 for e in annuaire.get('entrees', []) if 'enrichissement' in e)
    print(f"  Entrées: {nb_entrees} | Secteurs: {nb_secteurs} | Enrichies: {nb_enrichies}")

    # 2. Générer les chunks sectoriels
    print(f"\n[2/5] Génération chunks sectoriels...")
    chunks_sect = chunks_sectoriels(annuaire)
    print(f"  → {len(chunks_sect)} chunks sectoriels")

    # 3. Générer les chunks entrées
    print(f"\n[3/5] Regroupement et chunking des entrées...")
    chunks_ent = chunks_entrees(annuaire)
    print(f"  → {len(chunks_ent)} chunks entrées")

    # Tout ensemble
    all_chunks = chunks_sect + chunks_ent
    afficher_stats(all_chunks)

    if args.dry_run:
        print("\n[DRY RUN] Aucune ingestion effectuée.")
        print("\nPour ingérer réellement :")
        print(f"  python indexer_annuaire.py --json {args.json}")
        exit(0)

    # 4. Connexion ChromaDB
    print(f"\n[4/5] Connexion ChromaDB ({DB_PATH})...")
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"  Base avant: {collection.count()} chunks")
    supprimer_anciens(collection)

    # 5. Ingestion
    print(f"\n[5/5] Ingestion...")
    nb = ingerer(all_chunks, collection, model)

    print(f"\n{'='*65}")
    print(f"TERMINÉ | Annuaire: {nb} chunks ingérés | Base totale: {collection.count()}")
    print(f"{'='*65}")
