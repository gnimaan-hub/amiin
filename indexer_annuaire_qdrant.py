# -*- coding: utf-8 -*-
"""
indexer_annuaire_qdrant.py — Amiin Project

Indexe l'annuaire Djibouti dans Qdrant Cloud (1 vecteur par entrée).
Supporte deux formats en entrée :
  - JSON enrichi : annuaire_djibouti_complet_v2.json (format actuel)
  - CSV plat    : annuaire_amiin_v2.csv (nouveau format, 899 entrées)

Produit également :
  - annuaire_enrichi.json  → bundlé dans les assets Flutter (navigation offline)

Usage :
  python indexer_annuaire_qdrant.py                          # JSON par défaut
  python indexer_annuaire_qdrant.py --csv annuaire_amiin_v2.csv
  python indexer_annuaire_qdrant.py --dry-run                # aperçu sans indexer
"""

import os
import json
import csv
import math
import time
import argparse
import re
import requests
from uuid import uuid5, UUID
from dotenv import load_dotenv

load_dotenv()

# ── Config ────────────────────────────────────────────────────────────────────

QDRANT_URL        = os.environ["QDRANT_URL"].rstrip("/")
QDRANT_API_KEY    = os.environ.get("QDRANT_API_KEY", "")
QDRANT_COLLECTION = "djibouti_knowledge"
JINA_API_KEY      = os.environ["JINA_API_KEY"]
JINA_MODEL        = "jina-embeddings-v3"
JINA_DIM          = 1024

_qdrant_headers = {"api-key": QDRANT_API_KEY, "Content-Type": "application/json"}


def _qdrant(method: str, path: str, **kwargs):
    """Appel REST Qdrant Cloud — évite la dépendance qdrant-client Python."""
    url = f"{QDRANT_URL}{path}"
    resp = requests.request(method, url, headers=_qdrant_headers, timeout=60, **kwargs)
    resp.raise_for_status()
    return resp.json()

JSON_PATH = "annuaire_djibouti_complet_v2.json"
OUT_JSON  = "annuaire_enrichi.json"

# Espace UUID stable pour générer des IDs déterministes
_NS = UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

# ── Détection de quartier depuis coordonnées ──────────────────────────────────

# Boîtes englobantes approximatives (lat_min, lat_max, lon_min, lon_max)
_QUARTIERS = [
    ("Centre-ville",       11.578, 11.605, 43.135, 43.165),
    ("Plateau du Serpent", 11.578, 11.600, 43.120, 43.140),
    ("Haramous",           11.548, 11.578, 43.118, 43.150),
    ("Héron",              11.548, 11.578, 43.098, 43.120),
    ("Gabode",             11.540, 11.572, 43.080, 43.100),
    ("Balbala",            11.455, 11.555, 42.970, 43.075),
    ("Salines",            11.530, 11.558, 43.065, 43.082),
    ("Ambouli",            11.528, 11.555, 43.115, 43.145),
    ("Port",               11.568, 11.620, 43.140, 43.175),
    ("Bord de Mer",        11.578, 11.602, 43.148, 43.172),
    ("Boulaos",            11.540, 11.575, 43.140, 43.165),
    ("Wadajir",            11.570, 11.590, 43.125, 43.148),
]

_VILLES_REGIONS = {
    "ali-sabieh": "Ali-Sabieh", "arta": "Arta", "dikhil": "Dikhil",
    "tadjourah": "Tadjourah", "obock": "Obock",
}


def _detect_quartier(lat: float, lon: float, existing: str = None) -> str:
    """Retourne le quartier déduit des coordonnées, ou existing si aucun match."""
    for name, la0, la1, lo0, lo1 in _QUARTIERS:
        if la0 <= lat <= la1 and lo0 <= lon <= lo1:
            return name
    return existing or "Djibouti-ville"


# ── Construction du texte document ───────────────────────────────────────────

def _build_doc(entry: dict) -> str:
    """Construit le texte à embedder pour une entrée annuaire."""
    parts = []

    nom  = entry.get("nom", "")
    cat  = entry.get("categorie", "")
    scat = entry.get("sous_categorie", "")
    parts.append(f"{nom} — {scat} ({cat})")

    quartier = entry.get("quartier", "") or entry.get("ville_region", "")
    adresse  = entry.get("adresse", "")
    loc_parts = [p for p in [adresse, quartier] if p and str(p) not in ("nan", "NaN")]
    if loc_parts:
        parts.append("Adresse : " + ", ".join(loc_parts))

    tel = entry.get("telephone", "")
    if tel and str(tel) not in ("nan", "NaN", ""):
        parts.append(f"Tél : {tel}")

    desc = entry.get("description", "")
    if desc and str(desc) not in ("nan", "NaN", ""):
        parts.append(str(desc))

    # Enrichissement (champ JSON uniquement)
    enr = entry.get("enrichissement") or {}
    if isinstance(enr, dict):
        for key in ["type", "specialite", "specialites", "services", "description_enrichie",
                    "horaires", "prix", "gamme_prix", "tips", "conseils", "cuisine",
                    "equipements", "standing"]:
            val = enr.get(key)
            if val:
                if isinstance(val, list):
                    parts.append(f"{key.capitalize()} : {', '.join(str(v) for v in val)}")
                else:
                    parts.append(f"{key.capitalize()} : {val}")

    horaires = entry.get("horaires", "")
    if horaires and str(horaires) not in ("nan", "NaN", ""):
        parts.append(f"Horaires : {horaires}")

    return "\n".join(parts)


def _clean(val) -> str:
    """Nettoie une valeur potentiellement NaN/None vers chaîne vide."""
    if val is None:
        return ""
    s = str(val).strip()
    return "" if s in ("nan", "NaN", "None", "none") else s


# ── Lecture des sources de données ───────────────────────────────────────────

def load_from_json(path: str) -> list:
    """Charge les entrées depuis le JSON enrichi."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("entrees", [])
    result = []
    for e in entries:
        lat = e.get("latitude")
        lon = e.get("longitude")
        quartier = _clean(e.get("quartier"))
        if lat and lon:
            quartier = quartier or _detect_quartier(float(lat), float(lon))
        result.append({
            "id":             f"ann_{e.get('id', len(result)+1):04d}",
            "nom":            _clean(e.get("nom")),
            "categorie":      _clean(e.get("categorie")),
            "sous_categorie": _clean(e.get("sous_categorie")),
            "quartier":       quartier,
            "ville_region":   quartier,
            "adresse":        _clean(e.get("adresse")),
            "telephone":      _clean(e.get("telephone")),
            "email":          _clean(e.get("email")),
            "site_web":       _clean(e.get("site_web")),
            "horaires":       _clean(e.get("horaires")),
            "description":    _clean(e.get("description")),
            "latitude":       float(lat) if lat else None,
            "longitude":      float(lon) if lon else None,
            "enrichissement": e.get("enrichissement") or {},
            "source":         "Annuaire Amiin",
            "statut":         "vérifié",
        })
    return result


def load_from_csv(path: str) -> list:
    """Charge les entrées depuis le CSV plat (nouveau format 899 entrées)."""
    result = []
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            lat_s = _clean(row.get("latitude") or row.get("lat"))
            lon_s = _clean(row.get("longitude") or row.get("lon"))
            lat   = float(lat_s) if lat_s else None
            lon   = float(lon_s) if lon_s else None
            ville = _clean(row.get("ville_region") or row.get("ville"))
            quartier = _detect_quartier(lat, lon, ville) if lat and lon else ville
            entry_id = _clean(row.get("id")) or str(i + 1)
            result.append({
                "id":             f"ann_{entry_id.zfill(4)}",
                "nom":            _clean(row.get("nom")),
                "categorie":      _clean(row.get("categorie")),
                "sous_categorie": _clean(row.get("sous_categorie")),
                "quartier":       quartier,
                "ville_region":   ville or quartier,
                "adresse":        _clean(row.get("adresse")),
                "telephone":      _clean(row.get("telephone")),
                "email":          "",
                "site_web":       "",
                "horaires":       "",
                "description":    "",
                "latitude":       lat,
                "longitude":      lon,
                "enrichissement": {},
                "source":         _clean(row.get("source") or "Annuaire Amiin"),
                "statut":         _clean(row.get("statut_verification") or "non vérifié"),
            })
    return result


# ── Embeddings Jina ───────────────────────────────────────────────────────────

def jina_embed_batch(texts: list, task: str = "retrieval.passage") -> list:
    """Embed un batch de textes. Retourne list[list[float]]."""
    resp = requests.post(
        "https://api.jina.ai/v1/embeddings",
        headers={"Authorization": f"Bearer {JINA_API_KEY}", "Content-Type": "application/json"},
        json={"model": JINA_MODEL, "input": texts, "task": task},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    tokens = data.get("usage", {}).get("total_tokens", 0)
    return [item["embedding"] for item in data["data"]], tokens


# ── Nettoyage des anciens vecteurs annuaire ───────────────────────────────────

def delete_existing_annuaire() -> int:
    """Supprime les points annuaire en scrollant leurs IDs puis en les supprimant par lot."""
    ids_to_delete = []
    offset = None

    while True:
        body: dict = {"with_payload": False, "with_vector": False, "limit": 250,
                      "filter": {"must": [{"key": "type", "match": {"value": "annuaire"}}]}}
        if offset:
            body["offset"] = offset
        try:
            result = _qdrant("POST", f"/collections/{QDRANT_COLLECTION}/points/scroll", json=body)
        except Exception as e:
            print(f"  [WARN] Scroll pour suppression échoué ({e}) — on passe")
            return 0
        points = result.get("result", {}).get("points", [])
        ids_to_delete.extend(p["id"] for p in points)
        offset = result.get("result", {}).get("next_page_offset")
        if not offset:
            break

    if not ids_to_delete:
        print("  [INFO] Aucun vecteur annuaire existant à supprimer")
        return 0

    for i in range(0, len(ids_to_delete), 500):
        batch = ids_to_delete[i:i+500]
        _qdrant("POST", f"/collections/{QDRANT_COLLECTION}/points/delete",
                json={"points": batch})
    print(f"  [OK] {len(ids_to_delete)} anciens vecteurs annuaire supprimés")
    return len(ids_to_delete)


# ── Index principal ───────────────────────────────────────────────────────────

BATCH_SIZE = 50   # Jina API : ~50 textes par appel

def index_entries(entries: list, dry_run: bool = False) -> dict:
    total_tokens = 0
    points_upserted = 0
    errors = 0

    # Divise en batches
    for batch_start in range(0, len(entries), BATCH_SIZE):
        batch = entries[batch_start:batch_start + BATCH_SIZE]
        docs  = [_build_doc(e) for e in batch]

        if dry_run:
            for e, doc in zip(batch, docs):
                print(f"  [{e['id']}] {e['nom'][:50]}")
                print(f"    → {doc[:100].replace(chr(10),' | ')}")
            continue

        try:
            embeddings, tokens = jina_embed_batch(docs)
            total_tokens += tokens
        except Exception as ex:
            print(f"  [ERR] Batch {batch_start}–{batch_start+len(batch)} : {ex}")
            errors += len(batch)
            continue

        points = []
        for entry, doc, emb in zip(batch, docs, embeddings):
            point_id = str(uuid5(_NS, entry["id"]))
            payload = {
                "type":           "annuaire",
                "document":       doc,
                "title":          entry["nom"],
                "nom":            entry["nom"],
                "categorie":      entry["categorie"],
                "sous_categorie": entry["sous_categorie"],
                "quartier":       entry["quartier"],
                "ville_region":   entry["ville_region"],
                "adresse":        entry["adresse"],
                "telephone":      entry["telephone"],
                "email":          entry["email"],
                "site_web":       entry["site_web"],
                "horaires":       entry["horaires"],
                "source":         entry["source"],
                "statut":         entry["statut"],
                "original_id":    entry["id"],
                "category":       "vie_pratique",
            }
            if entry["latitude"] is not None:
                payload["latitude"]  = entry["latitude"]
                payload["longitude"] = entry["longitude"]
            points.append({"id": point_id, "vector": emb, "payload": payload})

        _qdrant("PUT", f"/collections/{QDRANT_COLLECTION}/points",
                json={"points": points})
        points_upserted += len(points)
        print(f"  [{batch_start + len(batch)}/{len(entries)}] upsertés — {total_tokens} tokens Jina")
        time.sleep(0.2)   # évite rate limit Jina

    return {"upserted": points_upserted, "errors": errors, "jina_tokens": total_tokens}


# ── Export Flutter JSON ───────────────────────────────────────────────────────

def export_flutter_json(entries: list, path: str) -> None:
    """Génère annuaire_enrichi.json pour les assets Flutter (navigation offline)."""
    # Construit les listes de catégories / sous-catégories / quartiers uniques
    categories   = sorted({e["categorie"] for e in entries if e["categorie"]})
    sous_cats    = sorted({e["sous_categorie"] for e in entries if e["sous_categorie"]})
    quartiers    = sorted({e["quartier"] for e in entries if e["quartier"]})
    villes       = sorted({e["ville_region"] for e in entries if e["ville_region"]})

    # Arborescence catégorie → sous-catégories
    tree: dict = {}
    for e in entries:
        cat, sc = e["categorie"], e["sous_categorie"]
        if cat:
            tree.setdefault(cat, set()).add(sc)
    tree_list = [
        {"categorie": c, "sous_categories": sorted(scs)}
        for c, scs in sorted(tree.items())
    ]

    # Entrées légères (sans le texte d'embedding complet)
    light_entries = []
    for e in entries:
        le = {k: v for k, v in e.items()
              if k not in ("enrichissement",) and v not in (None, "")}
        light_entries.append(le)

    out = {
        "version":        "2.0",
        "total":          len(entries),
        "categories":     categories,
        "sous_categories": sous_cats,
        "quartiers":      quartiers,
        "villes":         villes,
        "arborescence":   tree_list,
        "entries":        light_entries,
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"  [OK] {path} écrit ({len(entries)} entrées, {len(categories)} catégories, {len(quartiers)} quartiers)")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Indexer l'annuaire dans Qdrant Cloud")
    parser.add_argument("--csv",      default=None,      help="Chemin vers le CSV")
    parser.add_argument("--json",     default=JSON_PATH, help="Chemin vers le JSON")
    parser.add_argument("--dry-run",  action="store_true")
    parser.add_argument("--no-delete", action="store_true", help="Ne pas supprimer les anciens vecteurs")
    args = parser.parse_args()

    print("=" * 65)
    print("INDEXATION ANNUAIRE — Qdrant Cloud + Jina AI")
    print("=" * 65)

    # 1. Chargement
    if args.csv:
        print(f"\n[1/4] Chargement CSV : {args.csv}")
        entries = load_from_csv(args.csv)
    else:
        print(f"\n[1/4] Chargement JSON : {args.json}")
        entries = load_from_json(args.json)
    print(f"  → {len(entries)} entrées chargées")

    # Aperçu en dry-run
    if args.dry_run:
        print("\n[DRY RUN] Aperçu des 10 premières entrées :")
        cats = {}
        for e in entries:
            cats.setdefault(e["categorie"], 0)
            cats[e["categorie"]] += 1
        for c, n in sorted(cats.items(), key=lambda x: -x[1]):
            print(f"  {c:<35} {n:>4}")
        print(f"\nTotal: {len(entries)} entrées")
        export_flutter_json(entries, OUT_JSON)
        print("\n[DRY RUN] Aucun vecteur indexé.")
        return

    # 2. Export Flutter
    print(f"\n[2/4] Export Flutter JSON...")
    export_flutter_json(entries, OUT_JSON)

    # 3. Vérification connexion Qdrant
    print(f"\n[3/4] Connexion Qdrant ({QDRANT_URL})...")
    info = _qdrant("GET", f"/collections/{QDRANT_COLLECTION}")
    points_before = info["result"]["points_count"]
    print(f"  Base actuelle : {points_before} points")

    if not args.no_delete:
        delete_existing_annuaire()
        time.sleep(1)   # laisse Qdrant valider la suppression

    # 4. Indexation
    print(f"\n[4/4] Indexation ({len(entries)} entrées par batches de {BATCH_SIZE})...")
    stats = index_entries(entries)

    time.sleep(2)
    info2 = _qdrant("GET", f"/collections/{QDRANT_COLLECTION}")
    points_after = info2["result"]["points_count"]
    print(f"\n{'='*65}")
    print(f"TERMINÉ | {stats['upserted']} vecteurs | {stats['jina_tokens']} tokens Jina")
    print(f"         {stats['errors']} erreurs | Base totale : {points_after} points")
    print(f"{'='*65}")


if __name__ == "__main__":
    main()
