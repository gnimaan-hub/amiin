# =============================================================================
# AMIIN LEGAL — ENDPOINT FastAPI
# Fichier  : amiin_legal_api.py
# Version  : 2.3 — Corrections complètes :
#   • Appels Claude asynchrones (AsyncAnthropic) + retry avec backoff
#   • Radar de prescription : GET /alertes (recalcul quotidien de tous les dossiers)
#   • Liste des dossiers : GET /dossiers
#   • Statut DOCX suivi en base (en_cours / pret / erreur)
#   • Versionnage des dossiers (historique conservé)
#   • Export calendrier .ics : GET /dossier/{id}/calendrier.ics
#   • Chiffrement optionnel des données sensibles (Fernet, AMIIN_ENCRYPT_KEY)
#   • Mode démo (AMIIN_DEMO=1)
#   • Messages d'erreur structurés en français
# Intégrer : from amiin_legal_api import router as legal_router
#            app.include_router(legal_router)
# Dépend de: amiin_legal_prompts.py | amiin_rag.py | amiin_legal_docx.py
# Optionnel: cryptography (chiffrement) | google-api-python-client (Drive)
# =============================================================================

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import sqlite3
import uuid
from contextlib import contextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import anthropic
from fastapi import APIRouter, BackgroundTasks, HTTPException
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

from amiin_legal_prompts import (
    PROMPT_EXPANSION_JURIDIQUE,
    TYPES_AFFAIRES,
    build_legal_prompt,
    calculer_alerte_prescription,
)

try:
    from amiin_rag import (
        get_collection,
        get_embedding_model,
        recherche_semantique,
    )
    RAG_DISPONIBLE = True
except ImportError:
    RAG_DISPONIBLE = False
    logging.warning("amiin_rag.py non trouvé — mode dégradé sans RAG.")

from amiin_legal_docx import generer_docx_dossier

# ─────────────────────────────────────────────────────────────────────────────
logger = logging.getLogger("amiin_legal")
router = APIRouter(prefix="/v1/legal", tags=["Amiin Legal B2B"])

# Client ASYNCHRONE — ne bloque plus l'event loop FastAPI (correction v2.3)
client_claude = anthropic.AsyncAnthropic(api_key=os.environ.get("ANTHROPIC_API_KEY", ""))

MODEL_EXPANSION  = "claude-haiku-4-5-20251001"
MODEL_GENERATION = "claude-sonnet-4-20250514"

N_CHUNKS_PAR_REQUETE = 6
MAX_TOKENS_DOSSIER   = 8000

# Retry sur erreurs transitoires Anthropic (surcharge, rate limit)
CLAUDE_MAX_RETRIES   = 3
CLAUDE_RETRY_BASE_S  = 2.0   # backoff : 2s, 4s, 8s

DOCX_OUTPUT_DIR = "./dossiers_generes"
os.makedirs(DOCX_OUTPUT_DIR, exist_ok=True)


# =============================================================================
# CHIFFREMENT OPTIONNEL (Fernet)
# =============================================================================
#
# Si AMIIN_ENCRYPT_KEY est définie, les colonnes sensibles (dossier_markdown,
# lettre_client, resume_executif) sont chiffrées au repos dans SQLite et dans
# les backups JSON. Générer une clé :
#   python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
# Install : python.exe -m pip install cryptography
# ⚠️ Conserver la clé en lieu sûr : sans elle, les dossiers sont illisibles.
# =============================================================================

ENCRYPT_KEY = os.environ.get("AMIIN_ENCRYPT_KEY", "")
_fernet = None
if ENCRYPT_KEY:
    try:
        from cryptography.fernet import Fernet
        _fernet = Fernet(ENCRYPT_KEY.encode())
        logging.info("[Chiffrement] Activé (Fernet).")
    except ImportError:
        logging.warning("[Chiffrement] AMIIN_ENCRYPT_KEY définie mais 'cryptography' non installé — désactivé.")
    except Exception as e:
        logging.warning(f"[Chiffrement] Clé invalide — désactivé : {e}")

_ENC_PREFIX = "enc::"

def _chiffrer(texte: Optional[str]) -> Optional[str]:
    if texte is None or _fernet is None:
        return texte
    return _ENC_PREFIX + _fernet.encrypt(texte.encode("utf-8")).decode("ascii")

def _dechiffrer(texte: Optional[str]) -> Optional[str]:
    if texte is None or not isinstance(texte, str) or not texte.startswith(_ENC_PREFIX):
        return texte
    if _fernet is None:
        return "[CONTENU CHIFFRÉ — clé AMIIN_ENCRYPT_KEY absente]"
    try:
        return _fernet.decrypt(texte[len(_ENC_PREFIX):].encode("ascii")).decode("utf-8")
    except Exception:
        return "[CONTENU CHIFFRÉ — déchiffrement impossible (mauvaise clé ?)]"

COLONNES_SENSIBLES = ("dossier_markdown", "lettre_client", "resume_executif")


# =============================================================================
# PERSISTANCE — SQLite (source de vérité) + Drive + FS (backups optionnels)
# =============================================================================

SQLITE_DB_PATH   = os.environ.get("AMIIN_SQLITE_PATH", "./amiin_legal_dossiers.db")
FS_BACKUP_DIR    = os.environ.get("AMIIN_FS_BACKUP_DIR", "")
GDRIVE_FOLDER_ID = os.environ.get("GOOGLE_DRIVE_FOLDER_ID", "")
MODE_DEMO        = os.environ.get("AMIIN_DEMO", "") == "1"


def _init_sqlite():
    with sqlite3.connect(SQLITE_DB_PATH) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS dossiers_validation (
                dossier_id         TEXT PRIMARY KEY,
                version            INTEGER NOT NULL DEFAULT 1,
                type_affaire       TEXT NOT NULL,
                type_affaire_label TEXT NOT NULL,
                date_generation    TEXT NOT NULL,
                date_saisine       TEXT,
                nom_affaire        TEXT,
                collaborateur      TEXT,
                resume_executif    TEXT,
                lettre_client      TEXT,
                dossier_markdown   TEXT,
                statut             TEXT NOT NULL DEFAULT 'en_attente',
                statut_docx        TEXT NOT NULL DEFAULT 'aucun',
                annotation_senior  TEXT,
                date_validation    TEXT,
                valide_par         TEXT,
                est_demo           INTEGER NOT NULL DEFAULT 0,
                metadata_json      TEXT
            )
        """)
        # Historique de versions (conserve les anciennes générations)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS dossiers_historique (
                id                 INTEGER PRIMARY KEY AUTOINCREMENT,
                dossier_id         TEXT NOT NULL,
                version            INTEGER NOT NULL,
                date_archivage     TEXT NOT NULL,
                dossier_markdown   TEXT,
                lettre_client      TEXT,
                statut             TEXT,
                annotation_senior  TEXT
            )
        """)
        conn.commit()
    logger.info(f"[SQLite] Base initialisée : {SQLITE_DB_PATH}")

_init_sqlite()


@contextmanager
def _sqlite_conn():
    conn = sqlite3.connect(SQLITE_DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _row_to_dict(row: sqlite3.Row, dechiffrer: bool = True) -> dict:
    d = dict(row)
    if d.get("metadata_json"):
        try:
            d["metadata"] = json.loads(d["metadata_json"])
        except Exception:
            d["metadata"] = {}
    d.pop("metadata_json", None)
    if dechiffrer:
        for col in COLONNES_SENSIBLES:
            if col in d:
                d[col] = _dechiffrer(d[col])
    return d


# ── CRUD ──────────────────────────────────────────────────────────────────────

def db_sauvegarder_dossier(dossier: dict, archiver_ancienne_version: bool = True):
    """
    Sauvegarde (insert ou update). Si le dossier existe déjà et que le contenu
    change, l'ancienne version est archivée dans dossiers_historique et le
    numéro de version est incrémenté.
    """
    with _sqlite_conn() as conn:
        existant = conn.execute(
            "SELECT * FROM dossiers_validation WHERE dossier_id = ?",
            (dossier["dossier_id"],)
        ).fetchone()

        version = 1
        if existant:
            version = existant["version"]
            contenu_change = (
                _dechiffrer(existant["dossier_markdown"]) != dossier.get("dossier_markdown")
            )
            if contenu_change and archiver_ancienne_version:
                conn.execute("""
                    INSERT INTO dossiers_historique
                    (dossier_id, version, date_archivage, dossier_markdown,
                     lettre_client, statut, annotation_senior)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (
                    existant["dossier_id"], existant["version"],
                    datetime.now().isoformat(),
                    existant["dossier_markdown"], existant["lettre_client"],
                    existant["statut"], existant["annotation_senior"],
                ))
                version = existant["version"] + 1

        conn.execute("""
            INSERT OR REPLACE INTO dossiers_validation
            (dossier_id, version, type_affaire, type_affaire_label, date_generation,
             date_saisine, nom_affaire, collaborateur, resume_executif, lettre_client,
             dossier_markdown, statut, statut_docx, annotation_senior, date_validation,
             valide_par, est_demo, metadata_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            dossier["dossier_id"],
            version,
            dossier["type_affaire"],
            dossier["type_affaire_label"],
            dossier["date_generation"],
            dossier.get("date_saisine"),
            dossier.get("nom_affaire"),
            dossier.get("collaborateur"),
            _chiffrer(dossier.get("resume_executif")),
            _chiffrer(dossier.get("lettre_client")),
            _chiffrer(dossier.get("dossier_markdown")),
            dossier.get("statut", "en_attente"),
            dossier.get("statut_docx", "aucun"),
            dossier.get("annotation_senior"),
            dossier.get("date_validation"),
            dossier.get("valide_par"),
            1 if dossier.get("est_demo") else 0,
            json.dumps(dossier.get("metadata", {}), ensure_ascii=False),
        ))


def db_lire_dossier(dossier_id: str) -> Optional[dict]:
    with _sqlite_conn() as conn:
        row = conn.execute(
            "SELECT * FROM dossiers_validation WHERE dossier_id = ?", (dossier_id,)
        ).fetchone()
    return _row_to_dict(row) if row else None


def db_mettre_a_jour_champs(dossier_id: str, champs: dict):
    """Met à jour des champs ciblés (chiffre les colonnes sensibles)."""
    if not champs:
        return
    sets, vals = [], []
    for k, v in champs.items():
        sets.append(f"{k} = ?")
        vals.append(_chiffrer(v) if k in COLONNES_SENSIBLES else v)
    vals.append(dossier_id)
    with _sqlite_conn() as conn:
        conn.execute(
            f"UPDATE dossiers_validation SET {', '.join(sets)} WHERE dossier_id = ?",
            vals
        )


def db_lister_dossiers(statut: Optional[str] = None, complet: bool = False) -> list[dict]:
    """
    Liste les dossiers. Par défaut (complet=False), exclut dossier_markdown
    pour alléger les réponses de liste.
    """
    cols = "*" if complet else """
        dossier_id, version, type_affaire, type_affaire_label, date_generation,
        date_saisine, nom_affaire, collaborateur, resume_executif, lettre_client,
        statut, statut_docx, annotation_senior, date_validation, valide_par,
        est_demo, metadata_json
    """
    with _sqlite_conn() as conn:
        if statut:
            rows = conn.execute(
                f"SELECT {cols} FROM dossiers_validation WHERE statut = ? ORDER BY date_generation DESC",
                (statut,)
            ).fetchall()
        else:
            rows = conn.execute(
                f"SELECT {cols} FROM dossiers_validation ORDER BY date_generation DESC"
            ).fetchall()
    return [_row_to_dict(r) for r in rows]


def db_compter_statuts() -> dict:
    with _sqlite_conn() as conn:
        rows = conn.execute(
            "SELECT statut, COUNT(*) as n FROM dossiers_validation GROUP BY statut"
        ).fetchall()
    counts = {"en_attente": 0, "valide": 0, "renvoye": 0, "brouillon": 0}
    for row in rows:
        counts[row["statut"]] = row["n"]
    return counts


def db_historique(dossier_id: str) -> list[dict]:
    with _sqlite_conn() as conn:
        rows = conn.execute(
            "SELECT * FROM dossiers_historique WHERE dossier_id = ? ORDER BY version DESC",
            (dossier_id,)
        ).fetchall()
    return [_row_to_dict(r) for r in rows]


# ── Backups secondaires (non bloquants) ──────────────────────────────────────

def _sauvegarder_drive(dossier_id: str, dossier_dict: dict):
    if not GDRIVE_FOLDER_ID:
        return
    try:
        from google.oauth2 import service_account
        from googleapiclient.discovery import build
        from googleapiclient.http import MediaInMemoryUpload

        creds_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")
        if not creds_path or not Path(creds_path).exists():
            logger.warning("[Drive] GOOGLE_APPLICATION_CREDENTIALS non configuré — skip.")
            return

        # Sur Drive : si chiffrement actif, on envoie le contenu chiffré
        # (le Drive ne doit jamais contenir de données clients en clair).
        export = dict(dossier_dict)
        for col in COLONNES_SENSIBLES:
            if col in export:
                export[col] = _chiffrer(export[col]) if _fernet else export[col]

        creds   = service_account.Credentials.from_service_account_file(
            creds_path, scopes=["https://www.googleapis.com/auth/drive.file"],
        )
        service   = build("drive", "v3", credentials=creds)
        filename  = f"dossier_{dossier_id}_{datetime.now().strftime('%Y%m%d')}.json"
        content   = json.dumps(export, ensure_ascii=False, indent=2).encode("utf-8")
        media     = MediaInMemoryUpload(content, mimetype="application/json")
        file_meta = {"name": filename, "parents": [GDRIVE_FOLDER_ID]}
        service.files().create(body=file_meta, media_body=media, fields="id").execute()
        logger.info(f"[Drive] Dossier {dossier_id} sauvegardé.")
    except ImportError:
        logger.warning("[Drive] google-api-python-client non installé — skip.")
    except Exception as e:
        logger.warning(f"[Drive] Sauvegarde échouée pour {dossier_id} : {e}")


def _sauvegarder_fs(dossier_id: str, dossier_dict: dict):
    if not FS_BACKUP_DIR:
        return
    try:
        backup_path = Path(FS_BACKUP_DIR)
        backup_path.mkdir(parents=True, exist_ok=True)
        export = dict(dossier_dict)
        for col in COLONNES_SENSIBLES:
            if col in export:
                export[col] = _chiffrer(export[col]) if _fernet else export[col]
        filename = backup_path / f"dossier_{dossier_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(filename, "w", encoding="utf-8") as f:
            json.dump(export, f, ensure_ascii=False, indent=2)
        logger.info(f"[FS] Dossier {dossier_id} sauvegardé : {filename}")
    except Exception as e:
        logger.warning(f"[FS] Sauvegarde échouée pour {dossier_id} : {e}")


# ── Façade unifiée ────────────────────────────────────────────────────────────

def persistence_sauvegarder(dossier: dict):
    db_sauvegarder_dossier(dossier)
    _sauvegarder_drive(dossier["dossier_id"], dossier)
    _sauvegarder_fs(dossier["dossier_id"], dossier)


def persistence_lire(dossier_id: str) -> Optional[dict]:
    return db_lire_dossier(dossier_id)


def persistence_lister(statut: Optional[str] = None) -> list[dict]:
    return db_lister_dossiers(statut)


def persistence_compter() -> dict:
    return db_compter_statuts()


# ── Mode démo ─────────────────────────────────────────────────────────────────

DEMO_DOSSIERS = [
    {"dossier_id": "DEMO0001", "type_affaire": "licenciement_abusif",
     "nom_affaire": "[DÉMO] Ahmed c/ DJIB IMPORT SARL",
     "date_saisine": (datetime.now() - timedelta(days=3*365 - 6)).strftime("%Y-%m-%d"),
     "statut": "en_attente", "collaborateur": "Me Khadija O. (junior)"},
    {"dossier_id": "DEMO0002", "type_affaire": "licenciement_abusif",
     "nom_affaire": "[DÉMO] Farah c/ Entreprise BTP",
     "date_saisine": (datetime.now() - timedelta(days=3*365 - 18)).strftime("%Y-%m-%d"),
     "statut": "brouillon", "collaborateur": None},
    {"dossier_id": "DEMO0003", "type_affaire": "contentieux_commercial",
     "nom_affaire": "[DÉMO] Société ABC c/ Fournisseur XYZ",
     "date_saisine": (datetime.now() - timedelta(days=5*365 - 23)).strftime("%Y-%m-%d"),
     "statut": "valide", "collaborateur": "Me Khadija O. (junior)"},
    {"dossier_id": "DEMO0004", "type_affaire": "recouvrement_creance",
     "nom_affaire": "[DÉMO] Houssein c/ Débiteur",
     "date_saisine": (datetime.now() - timedelta(days=5*365 - 42)).strftime("%Y-%m-%d"),
     "statut": "brouillon", "collaborateur": None},
]

def _seed_demo():
    """Insère des dossiers de démonstration clairement marqués si la base est vide."""
    if not MODE_DEMO:
        return
    if db_lister_dossiers():
        return  # ne jamais polluer une base contenant de vrais dossiers
    for d in DEMO_DOSSIERS:
        record = {
            "dossier_id":         d["dossier_id"],
            "type_affaire":       d["type_affaire"],
            "type_affaire_label": TYPES_AFFAIRES[d["type_affaire"]]["label"],
            "date_generation":    datetime.now().strftime("%d/%m/%Y à %Hh%M"),
            "date_saisine":       d["date_saisine"],
            "nom_affaire":        d["nom_affaire"],
            "collaborateur":      d["collaborateur"],
            "resume_executif":    "Dossier de démonstration — données fictives à des fins de présentation.",
            "lettre_client":      "Lettre de démonstration (contenu fictif).",
            "dossier_markdown":   "# DOSSIER DE DÉMONSTRATION\n\nContenu fictif — mode démo Amiin Legal.",
            "statut":             d["statut"],
            "statut_docx":        "aucun",
            "est_demo":           True,
            "metadata":           {"demo": True, "date_saisine": d["date_saisine"]},
        }
        db_sauvegarder_dossier(record, archiver_ancienne_version=False)
    logger.info("[Démo] 4 dossiers de démonstration insérés.")

_seed_demo()


# =============================================================================
# SCHÉMAS PYDANTIC
# =============================================================================

class Partie(BaseModel):
    nom:       str
    qualite:   str
    domicile:  Optional[str] = None
    telephone: Optional[str] = None
    email:     Optional[str] = None


class PartiesDossier(BaseModel):
    demandeur: Partie
    defendeur: Partie
    tiers:     Optional[list[Partie]] = None


class DossierRequest(BaseModel):
    type_affaire:  str = Field(
        ...,
        description=(
            "Type d'affaire parmi : licenciement_abusif | recouvrement_creance | "
            "divorce | creation_societe | contentieux_commercial | penal_delit | "
            "penal_crime | penal_defense | contentieux_administratif | "
            "refere_urgence | autre"
        )
    )
    faits:         str  = Field(..., min_length=50)
    parties:       PartiesDossier
    date_saisine:  str  = Field(..., description="Format YYYY-MM-DD")
    instructions:  Optional[str] = None
    export_docx:   bool = Field(True)
    envoyer_validation: bool = Field(False)


class ChunkRAG(BaseModel):
    source:   str
    titre:    str
    contenu:  str
    distance: float


class AlertePrescription(BaseModel):
    delai_label:    str
    action:         str
    article:        str
    jours_ecoules:  Optional[int]
    jours_restants: Optional[int]
    date_limite:    Optional[str]
    niveau_alerte:  str
    message:        str


class DossierResponse(BaseModel):
    dossier_id:           str
    type_affaire:         str
    type_affaire_label:   str
    date_generation:      str
    dossier_markdown:     str
    lettre_client:        str
    prescription:         AlertePrescription
    sources_rag:          list[ChunkRAG]
    nb_chunks_utilises:   int
    docx_url:             Optional[str]
    validation_url:       Optional[str]
    avertissements:       list[str]


class TypesAffairesResponse(BaseModel):
    types: dict[str, str]


class ValidationRequest(BaseModel):
    dossier_id:        str
    action:            str  = Field(..., description="'valider' ou 'renvoyer'")
    annotation_senior: Optional[str] = None
    nom_senior:        Optional[str] = None


class PrescriptionRequest(BaseModel):
    type_affaire:  str
    date_saisine:  str  = Field(..., description="Format YYYY-MM-DD")


class AlerteDossier(BaseModel):
    """Une ligne du radar de prescription."""
    dossier_id:         str
    nom_affaire:        Optional[str]
    type_affaire:       str
    type_affaire_label: str
    statut:             str
    date_saisine:       Optional[str]
    prescription:       AlertePrescription
    est_demo:           bool


# =============================================================================
# APPELS CLAUDE — ASYNC + RETRY
# =============================================================================

ERREURS_TRANSITOIRES = (
    anthropic.RateLimitError,
    anthropic.InternalServerError,
    anthropic.APIConnectionError,
    anthropic.APITimeoutError,
)

async def _appel_claude_avec_retry(**kwargs) -> anthropic.types.Message:
    """
    Appelle l'API Anthropic en async avec retry exponentiel sur les erreurs
    transitoires (surcharge 529, rate limit 429, timeouts réseau).
    """
    derniere_erreur = None
    for tentative in range(1, CLAUDE_MAX_RETRIES + 1):
        try:
            return await client_claude.messages.create(**kwargs)
        except ERREURS_TRANSITOIRES as e:
            derniere_erreur = e
            if tentative < CLAUDE_MAX_RETRIES:
                attente = CLAUDE_RETRY_BASE_S * (2 ** (tentative - 1))
                logger.warning(
                    f"[Claude] Erreur transitoire (tentative {tentative}/{CLAUDE_MAX_RETRIES}) : "
                    f"{type(e).__name__} — nouvelle tentative dans {attente:.0f}s"
                )
                await asyncio.sleep(attente)
    raise derniere_erreur


async def _appel_claude_expansion(situation: str, type_affaire: str) -> dict:
    prompt = PROMPT_EXPANSION_JURIDIQUE.format(
        situation=situation[:1500],
        type_affaire=type_affaire,
    )
    try:
        response = await _appel_claude_avec_retry(
            model=MODEL_EXPANSION,
            max_tokens=500,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
        queries = json.loads(raw)
        required = {"requete_textes", "requete_procedure", "requete_preuve", "requete_sanctions"}
        if not required.issubset(queries.keys()):
            raise ValueError("Clés manquantes dans la réponse d'expansion")
        return queries
    except Exception as e:
        logger.warning(f"Expansion échouée ({e}), fallback brut")
        return {
            "requete_textes":    f"{type_affaire} loi code article Djibouti",
            "requete_procedure": f"{type_affaire} procédure juridiction délai Djibouti",
            "requete_preuve":    f"{type_affaire} preuve éléments constitutifs conditions",
            "requete_sanctions": f"{type_affaire} sanctions indemnités réparation montant",
        }


async def _appel_claude_generation(system: str, user: str) -> str:
    response = await _appel_claude_avec_retry(
        model=MODEL_GENERATION,
        max_tokens=MAX_TOKENS_DOSSIER,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return response.content[0].text


def _erreur_claude_lisible(e: Exception) -> str:
    """Message d'erreur en français exploitable par le frontend."""
    if isinstance(e, anthropic.RateLimitError):
        return "Le serveur IA est temporairement saturé. Réessayez dans une minute."
    if isinstance(e, anthropic.AuthenticationError):
        return "Clé API Anthropic invalide ou absente. Vérifier ANTHROPIC_API_KEY sur le serveur."
    if isinstance(e, (anthropic.APIConnectionError, anthropic.APITimeoutError)):
        return "Impossible de joindre le serveur IA. Vérifier la connexion internet du serveur."
    if isinstance(e, anthropic.InternalServerError):
        return "Le serveur IA rencontre un incident temporaire. Réessayez dans quelques minutes."
    return f"Erreur lors de la génération : {str(e)}"


# =============================================================================
# RAG (synchrone — exécuté dans un thread pour ne pas bloquer l'event loop)
# =============================================================================

def _recherche_rag_multi_sync(queries: dict) -> tuple[str, list[ChunkRAG]]:
    if not RAG_DISPONIBLE:
        return (
            "⚠️ Base RAG non disponible — réponse basée sur les connaissances natives de Claude.",
            []
        )
    try:
        collection  = get_collection()
        embed_model = get_embedding_model()
        seen_ids    = set()
        all_chunks: list[ChunkRAG] = []

        for requete in queries.values():
            resultats = recherche_semantique(
                collection=collection,
                embed_model=embed_model,
                query=requete,
                n_results=N_CHUNKS_PAR_REQUETE,
            )
            for r in resultats:
                chunk_id = r.get("id", "")
                if chunk_id in seen_ids:
                    continue
                seen_ids.add(chunk_id)
                meta = r.get("metadata", {})
                all_chunks.append(ChunkRAG(
                    source   = meta.get("source", "?"),
                    titre    = meta.get("titre", meta.get("title", "Sans titre")),
                    contenu  = r.get("document", ""),
                    distance = round(r.get("distance", 0.0), 4),
                ))

        all_chunks.sort(key=lambda c: c.distance)
        all_chunks = all_chunks[:20]

        lignes = []
        for i, c in enumerate(all_chunks, 1):
            lignes.append(
                f"[SOURCE {i}] {c.source} — {c.titre} (score: {c.distance})\n"
                f"{c.contenu}\n{'─'*60}"
            )
        contexte = "\n".join(lignes) if lignes else "Aucun contexte pertinent trouvé."
        return contexte, all_chunks

    except Exception as e:
        logger.error(f"Erreur RAG : {e}")
        return f"⚠️ Erreur RAG : {str(e)}", []


async def _recherche_rag_multi(queries: dict) -> tuple[str, list[ChunkRAG]]:
    """Le RAG (embeddings + ChromaDB) est CPU-bound : on l'exécute hors event loop."""
    return await asyncio.to_thread(_recherche_rag_multi_sync, queries)


# =============================================================================
# POST-TRAITEMENT DU DOSSIER
# =============================================================================

def _detecter_avertissements(dossier_markdown: str) -> list[str]:
    avertissements = []
    seen_source = False
    for ligne in dossier_markdown.split("\n"):
        if "⚠️ POINT À VÉRIFIER" in ligne:
            texte = ligne.replace("⚠️ POINT À VÉRIFIER :", "").strip()
            if texte:
                avertissements.append(f"⚠️ {texte}")
        if "🔴 DÉLAI CRITIQUE" in ligne:
            texte = ligne.replace("🔴 DÉLAI CRITIQUE :", "").strip()
            if texte:
                avertissements.append(f"🔴 DÉLAI : {texte}")
        if "[source à vérifier par l'avocat]" in ligne and not seen_source:
            avertissements.append("⚠️ Des articles cités nécessitent vérification manuelle")
            seen_source = True
    return avertissements


def _extraire_lettre_client(dossier_markdown: str) -> str:
    DEBUT = "<!-- DEBUT_LETTRE_CLIENT -->"
    FIN   = "<!-- FIN_LETTRE_CLIENT -->"
    try:
        debut = dossier_markdown.index(DEBUT) + len(DEBUT)
        fin   = dossier_markdown.index(FIN)
        contenu = dossier_markdown[debut:fin]
    except ValueError:
        return (
            "La lettre client n'a pas pu être extraite du dossier.\n"
            "Consulter la Section 7 du dossier Markdown complet."
        )

    lignes_nettoyees = []
    skip_sep = False
    for ligne in contenu.split("\n"):
        if "⚠️ À RELIRE ET SIGNER" in ligne:
            skip_sep = True
            continue
        if skip_sep:
            if not ligne.strip():
                continue  # les lignes vides ne réinitialisent pas le flag
            if ligne.strip() == "---":
                skip_sep = False
                continue  # supprimer le séparateur qui suit l'avertissement
            skip_sep = False  # première vraie ligne de contenu : on la garde
        lignes_nettoyees.append(ligne)

    return "\n".join(lignes_nettoyees).strip()


def _extraire_resume_executif(dossier_markdown: str) -> str:
    lignes = dossier_markdown.split("\n")
    in_section1 = False
    paragraphe = []
    for ligne in lignes:
        stripped = ligne.strip()
        if not in_section1:
            if stripped.startswith("#") and ("1." in stripped or "I." in stripped or
               any(kw in stripped.lower() for kw in ("qualification", "faits", "résumé", "contexte"))):
                in_section1 = True
            continue
        if stripped.startswith("#"):
            break
        if stripped and not stripped.startswith("*") and not stripped.startswith("-"):
            paragraphe.append(stripped)
        if len(" ".join(paragraphe)) >= 200:
            break

    if paragraphe:
        return " ".join(paragraphe)[:300]

    for ligne in lignes:
        stripped = ligne.strip()
        if stripped and not stripped.startswith("#") and not stripped.startswith("*") and not stripped.startswith("-"):
            return stripped[:300]

    return "Résumé non disponible."


# ── Calendrier ICS ────────────────────────────────────────────────────────────

_REGEX_DATE_FR = re.compile(r"\b(\d{2})/(\d{2})/(\d{4})\b")

def _extraire_evenements_calendrier(dossier_markdown: str, nom_affaire: str) -> list[dict]:
    """
    Extrait les lignes du tableau de la Section 8 (Calendrier procédural)
    contenant une date au format DD/MM/YYYY.
    """
    evenements = []
    in_section8 = False
    for ligne in dossier_markdown.split("\n"):
        stripped = ligne.strip()
        if stripped.startswith("#") and ("SECTION 8" in stripped.upper() or "CALENDRIER" in stripped.upper()):
            in_section8 = True
            continue
        if in_section8 and stripped.startswith("#"):
            break
        if not in_section8 or not stripped.startswith("|"):
            continue
        m = _REGEX_DATE_FR.search(stripped)
        if not m:
            continue
        jour, mois, annee = m.groups()
        try:
            dt = datetime(int(annee), int(mois), int(jour))
        except ValueError:
            continue
        cells = [c.strip() for c in stripped.split("|") if c.strip()]
        action = next(
            (c for c in cells if not _REGEX_DATE_FR.fullmatch(c)
             and c not in ("⬜ À faire", "⬜ À planifier") and not c.isdigit()
             and c.lower() not in ("avocat", "—", "client")),
            "Échéance procédurale"
        )
        evenements.append({"date": dt, "action": action})
    return evenements


def _construire_ics(evenements: list[dict], dossier_id: str, nom_affaire: str) -> str:
    now = datetime.now().strftime("%Y%m%dT%H%M%S")
    lignes = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Amiin Legal//Calendrier Procedural//FR",
        "CALSCALE:GREGORIAN",
    ]
    for i, ev in enumerate(evenements):
        d = ev["date"].strftime("%Y%m%d")
        resume = ev["action"].replace(",", "\\,").replace(";", "\\;")
        lignes += [
            "BEGIN:VEVENT",
            f"UID:amiin-{dossier_id}-{i}@amiin.dj",
            f"DTSTAMP:{now}",
            f"DTSTART;VALUE=DATE:{d}",
            f"SUMMARY:[Amiin] {resume} — {nom_affaire}",
            f"DESCRIPTION:Échéance du dossier {dossier_id} (Amiin Legal). À vérifier par l'avocat responsable.",
            "BEGIN:VALARM",
            "TRIGGER:-P7D",
            "ACTION:DISPLAY",
            f"DESCRIPTION:Rappel J-7 : {resume}",
            "END:VALARM",
            "END:VEVENT",
        ]
    lignes.append("END:VCALENDAR")
    return "\r\n".join(lignes)


# =============================================================================
# ENDPOINTS
# =============================================================================

@router.get("/types", response_model=TypesAffairesResponse, summary="Types d'affaires supportés")
async def get_types_affaires():
    return TypesAffairesResponse(
        types={code: info["label"] for code, info in TYPES_AFFAIRES.items()}
    )


@router.post(
    "/prescription",
    response_model=AlertePrescription,
    summary="Calculer l'alerte de prescription (instantané, sans Claude)",
)
async def calculer_prescription(request: PrescriptionRequest):
    if request.type_affaire not in TYPES_AFFAIRES:
        raise HTTPException(
            status_code=422,
            detail=f"Type d'affaire non reconnu : {request.type_affaire}"
        )
    resultat = calculer_alerte_prescription(request.type_affaire, request.date_saisine)
    return AlertePrescription(**resultat)


# ── RADAR DE PRESCRIPTION (nouveau v2.3) ─────────────────────────────────────

@router.get(
    "/alertes",
    summary="Radar de prescription — tous les dossiers, recalculés à la date du jour",
    description=(
        "Recalcule la prescription de chaque dossier persisté à la date du jour. "
        "Trié par urgence (jours restants croissants). C'est l'endpoint du "
        "dashboard : il garantit qu'aucune forclusion ne passe inaperçue."
    ),
)
async def radar_prescriptions(inclure_valides: bool = True):
    dossiers = persistence_lister()
    alertes: list[dict] = []

    for d in dossiers:
        if not inclure_valides and d.get("statut") == "valide":
            continue
        date_saisine = d.get("date_saisine") or (d.get("metadata") or {}).get("date_saisine")
        if not date_saisine:
            continue
        presc = calculer_alerte_prescription(d["type_affaire"], date_saisine)
        alertes.append({
            "dossier_id":         d["dossier_id"],
            "nom_affaire":        d.get("nom_affaire"),
            "type_affaire":       d["type_affaire"],
            "type_affaire_label": d["type_affaire_label"],
            "statut":             d.get("statut"),
            "date_saisine":       date_saisine,
            "prescription":       presc,
            "est_demo":           bool(d.get("est_demo")),
        })

    # Tri par urgence : expirées d'abord, puis jours restants croissants,
    # les dossiers sans délai (info) en dernier
    def cle_urgence(a):
        jr = a["prescription"].get("jours_restants")
        niveau = a["prescription"].get("niveau_alerte")
        if niveau == "expiree":
            return (-1, jr if jr is not None else 0)
        if jr is None:
            return (2, 0)
        return (0, jr)
    alertes.sort(key=cle_urgence)

    compteurs = {"expiree": 0, "rouge": 0, "orange": 0, "vert": 0, "info": 0}
    for a in alertes:
        n = a["prescription"]["niveau_alerte"]
        compteurs[n] = compteurs.get(n, 0) + 1

    return {
        "date_calcul": datetime.now().strftime("%d/%m/%Y à %Hh%M"),
        "total":       len(alertes),
        "compteurs":   compteurs,
        "alertes":     alertes,
        "mode_demo":   MODE_DEMO,
    }


# ── LISTE DES DOSSIERS (nouveau v2.3) ────────────────────────────────────────

@router.get(
    "/dossiers",
    summary="Lister tous les dossiers persistés",
    description="Liste allégée (sans le markdown complet). Filtrable par statut.",
)
async def lister_dossiers(statut: Optional[str] = None):
    dossiers = db_lister_dossiers(statut)
    # Alléger : retirer le markdown complet des réponses de liste
    for d in dossiers:
        d.pop("dossier_markdown", None)
        d.pop("lettre_client", None)
    counts = persistence_compter()
    return {
        "total":     len(dossiers),
        "compteurs": counts,
        "dossiers":  dossiers,
        "mode_demo": MODE_DEMO,
    }


@router.get("/dossiers/{dossier_id}/historique", summary="Historique des versions d'un dossier")
async def historique_dossier(dossier_id: str):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    return {
        "dossier_id":      dossier_id,
        "version_actuelle": dossier.get("version", 1),
        "historique":       db_historique(dossier_id),
    }


# ── ENDPOINT PRINCIPAL — Génération dossier ──────────────────────────────────

@router.post(
    "/dossier",
    response_model=DossierResponse,
    summary="Générer un dossier juridique complet",
    description=(
        "Pipeline : expansion RAG → recherche ChromaDB → génération Claude Sonnet → "
        "extraction lettre client → calcul prescription → export DOCX. "
        "Durée estimée : 20-45 secondes."
    ),
)
async def generer_dossier(
    request: DossierRequest,
    background_tasks: BackgroundTasks,
):
    dossier_id      = str(uuid.uuid4())[:8].upper()
    date_generation = datetime.now().strftime("%d/%m/%Y à %Hh%M")
    avertissements  = []

    # ── 1. Validation ────────────────────────────────────────────────────────
    if request.type_affaire not in TYPES_AFFAIRES:
        raise HTTPException(
            status_code=422,
            detail=f"Type d'affaire non reconnu. Valides : {list(TYPES_AFFAIRES.keys())}"
        )
    type_label = TYPES_AFFAIRES[request.type_affaire]["label"]

    # ── 2. Prescription (instantané) ─────────────────────────────────────────
    alerte_presc_dict = calculer_alerte_prescription(
        request.type_affaire, request.date_saisine
    )
    alerte_presc = AlertePrescription(**alerte_presc_dict)
    if alerte_presc.niveau_alerte in ("rouge", "expiree"):
        avertissements.append(alerte_presc.message)

    # ── 3. Expansion (async + retry) ─────────────────────────────────────────
    logger.info(f"[{dossier_id}] Expansion — type: {request.type_affaire}")
    queries = await _appel_claude_expansion(request.faits, request.type_affaire)

    # ── 4. RAG (thread, hors event loop) ─────────────────────────────────────
    logger.info(f"[{dossier_id}] RAG — {len(queries)} requêtes")
    contexte_rag, chunks = await _recherche_rag_multi(queries)
    if not chunks:
        avertissements.append(
            "⚠️ Aucun contexte RAG — dossier basé sur les connaissances générales de Claude."
        )

    # ── 5. Génération (async + retry) ────────────────────────────────────────
    logger.info(f"[{dossier_id}] Génération — {len(chunks)} chunks RAG")
    parties_dict = {
        "demandeur": request.parties.demandeur.model_dump(exclude_none=True),
        "defendeur": request.parties.defendeur.model_dump(exclude_none=True),
    }
    if request.parties.tiers:
        parties_dict["tiers"] = [t.model_dump(exclude_none=True) for t in request.parties.tiers]

    try:
        prompts = build_legal_prompt(
            type_affaire    = request.type_affaire,
            faits           = request.faits,
            parties         = parties_dict,
            date_saisine    = request.date_saisine,
            contexte_rag    = contexte_rag,
            instructions    = request.instructions or "Aucune instruction spécifique.",
            date_generation = date_generation,
        )
        dossier_markdown = await _appel_claude_generation(
            system = prompts["system"],
            user   = prompts["user"],
        )
    except Exception as e:
        logger.error(f"[{dossier_id}] Génération échouée : {e}")
        raise HTTPException(status_code=502, detail=_erreur_claude_lisible(e))

    # ── 6. Post-traitement ───────────────────────────────────────────────────
    avertissements  += _detecter_avertissements(dossier_markdown)
    lettre_client    = _extraire_lettre_client(dossier_markdown)
    resume_executif  = _extraire_resume_executif(dossier_markdown)
    nom_affaire      = parties_dict["demandeur"].get("nom", "Dossier")

    # ── 7. Export DOCX (background, statut suivi en base) ────────────────────
    docx_url    = None
    statut_docx = "aucun"
    if request.export_docx:
        docx_filename = f"dossier_{dossier_id}_{request.type_affaire}.docx"
        docx_path     = os.path.join(DOCX_OUTPUT_DIR, docx_filename)
        statut_docx   = "en_cours"
        background_tasks.add_task(
            _docx_task_wrapper, dossier_id, dossier_markdown, lettre_client,
            docx_path, type_label, date_generation,
        )
        docx_url = f"/v1/legal/dossier/{dossier_id}/docx"

    # ── 8. Persistance ───────────────────────────────────────────────────────
    validation_url = None
    dossier_record = {
        "dossier_id":         dossier_id,
        "type_affaire":       request.type_affaire,
        "type_affaire_label": type_label,
        "date_generation":    date_generation,
        "date_saisine":       request.date_saisine,
        "nom_affaire":        nom_affaire,
        "collaborateur":      None,
        "resume_executif":    resume_executif,
        "lettre_client":      lettre_client,
        "dossier_markdown":   dossier_markdown,
        "statut":             "en_attente" if request.envoyer_validation else "brouillon",
        "statut_docx":        statut_docx,
        "est_demo":           False,
        "metadata":           {
            "type_affaire":  request.type_affaire,
            "date_saisine":  request.date_saisine,
            "nb_chunks_rag": len(chunks),
        },
    }
    persistence_sauvegarder(dossier_record)

    if request.envoyer_validation:
        validation_url = f"/v1/legal/validation/{dossier_id}"
        logger.info(f"[{dossier_id}] Soumis en validation")

    # ── 9. Réponse ───────────────────────────────────────────────────────────
    logger.info(f"[{dossier_id}] Terminé — {len(dossier_markdown)} caractères")
    return DossierResponse(
        dossier_id           = dossier_id,
        type_affaire         = request.type_affaire,
        type_affaire_label   = type_label,
        date_generation      = date_generation,
        dossier_markdown     = dossier_markdown,
        lettre_client        = lettre_client,
        prescription         = alerte_presc,
        sources_rag          = chunks,
        nb_chunks_utilises   = len(chunks),
        docx_url             = docx_url,
        validation_url       = validation_url,
        avertissements       = avertissements,
    )


def _docx_task_wrapper(dossier_id, dossier_markdown, lettre_client,
                        docx_path, type_label, date_generation):
    """Background task DOCX avec suivi du statut en base."""
    try:
        db_mettre_a_jour_champs(dossier_id, {"statut_docx": "en_cours"})
        generer_docx_dossier(
            dossier_markdown = dossier_markdown,
            lettre_client    = lettre_client,
            output_path      = docx_path,
            type_affaire     = type_label,
            dossier_id       = dossier_id,
            date_generation  = date_generation,
        )
        db_mettre_a_jour_champs(dossier_id, {"statut_docx": "pret"})
        logger.info(f"[{dossier_id}] DOCX prêt.")
    except Exception as e:
        db_mettre_a_jour_champs(dossier_id, {"statut_docx": "erreur"})
        logger.error(f"[{dossier_id}] Génération DOCX échouée : {e}")


# ── Prescription sur dossier existant ────────────────────────────────────────

@router.get(
    "/dossier/{dossier_id}/prescription",
    response_model=AlertePrescription,
    summary="Recalculer l'alerte de prescription d'un dossier",
)
async def recalculer_prescription_dossier(dossier_id: str,
                                           type_affaire: Optional[str] = None,
                                           date_saisine: Optional[str] = None):
    # Si non fournis, lire depuis la base (nouveau v2.3)
    if not type_affaire or not date_saisine:
        dossier = persistence_lire(dossier_id)
        if not dossier:
            raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
        type_affaire = type_affaire or dossier["type_affaire"]
        date_saisine = date_saisine or dossier.get("date_saisine") or ""
    if type_affaire not in TYPES_AFFAIRES:
        raise HTTPException(status_code=422, detail=f"Type non reconnu : {type_affaire}")
    resultat = calculer_alerte_prescription(type_affaire, date_saisine)
    return AlertePrescription(**resultat)


# ── Lettre client seule ───────────────────────────────────────────────────────

@router.get("/dossier/{dossier_id}/lettre-client", summary="Récupérer la lettre client")
async def get_lettre_client(dossier_id: str):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    return {
        "dossier_id":    dossier_id,
        "nom_affaire":   dossier.get("nom_affaire"),
        "lettre_client": dossier.get("lettre_client"),
        "statut":        dossier.get("statut"),
        "avertissement": "À relire et signer par l'avocat responsable avant envoi au client.",
    }


# ── Calendrier ICS (nouveau v2.3) ────────────────────────────────────────────

@router.get(
    "/dossier/{dossier_id}/calendrier.ics",
    summary="Exporter le calendrier procédural au format iCalendar (.ics)",
    description=(
        "Extrait les échéances datées de la Section 8 du dossier et les exporte "
        "en .ics importable dans Outlook, Google Calendar ou Thunderbird. "
        "Chaque événement inclut un rappel J-7."
    ),
)
async def exporter_calendrier_ics(dossier_id: str):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    markdown = dossier.get("dossier_markdown") or ""
    evenements = _extraire_evenements_calendrier(markdown, dossier.get("nom_affaire") or "Dossier")
    if not evenements:
        raise HTTPException(
            status_code=404,
            detail="Aucune échéance datée trouvée dans le calendrier procédural (Section 8) de ce dossier."
        )
    ics = _construire_ics(evenements, dossier_id, dossier.get("nom_affaire") or "Dossier")
    return Response(
        content=ics,
        media_type="text/calendar",
        headers={"Content-Disposition": f'attachment; filename="amiin_{dossier_id}_calendrier.ics"'},
    )


# ── File de validation ────────────────────────────────────────────────────────

@router.get("/validation", summary="Lister les dossiers en validation")
async def lister_dossiers_validation(statut: Optional[str] = None):
    dossiers = persistence_lister(statut)
    # La file de validation n'affiche pas les brouillons
    if not statut:
        dossiers = [d for d in dossiers if d.get("statut") != "brouillon"]
    counts = persistence_compter()
    return {
        "total":      len(dossiers),
        "en_attente": counts.get("en_attente", 0),
        "valides":    counts.get("valide", 0),
        "renvoyes":   counts.get("renvoye", 0),
        "dossiers":   dossiers,
        "mode_demo":  MODE_DEMO,
    }


@router.get("/validation/{dossier_id}", summary="Détail d'un dossier en validation")
async def get_dossier_validation(dossier_id: str):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    return dossier


@router.post("/validation/{dossier_id}", summary="Valider ou renvoyer un dossier")
async def action_validation(dossier_id: str, request: ValidationRequest):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    if request.action not in ("valider", "renvoyer"):
        raise HTTPException(
            status_code=422,
            detail="Action invalide. Valeurs acceptées : 'valider' ou 'renvoyer'."
        )
    if dossier.get("statut") == "valide":
        raise HTTPException(status_code=409, detail=f"Le dossier {dossier_id} est déjà validé.")

    nouveau_statut = "valide" if request.action == "valider" else "renvoye"
    date_val       = datetime.now().strftime("%d/%m/%Y à %Hh%M")

    db_mettre_a_jour_champs(dossier_id, {
        "statut":            nouveau_statut,
        "annotation_senior": request.annotation_senior,
        "date_validation":   date_val,
        "valide_par":        request.nom_senior,
    })
    # Synchroniser les backups
    maj = persistence_lire(dossier_id)
    if maj:
        _sauvegarder_drive(dossier_id, maj)
        _sauvegarder_fs(dossier_id, maj)

    logger.info(f"[{dossier_id}] Validation : {nouveau_statut} par {request.nom_senior or 'senior'}")
    return {
        "dossier_id":        dossier_id,
        "statut":            nouveau_statut,
        "annotation_senior": request.annotation_senior,
        "date_validation":   date_val,
        "message": (
            f"Dossier {dossier_id} validé avec succès."
            if nouveau_statut == "valide"
            else f"Dossier {dossier_id} renvoyé au collaborateur avec annotations."
        ),
    }


@router.post("/dossier/{dossier_id}/soumettre-validation", summary="Soumettre un dossier en validation")
async def soumettre_validation(dossier_id: str, collaborateur: Optional[str] = None):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    db_mettre_a_jour_champs(dossier_id, {
        "statut":        "en_attente",
        "collaborateur": collaborateur,
    })
    return {
        "dossier_id":     dossier_id,
        "statut":         "en_attente",
        "validation_url": f"/v1/legal/validation/{dossier_id}",
        "message":        f"Dossier {dossier_id} soumis en validation.",
    }


# ── DOCX download (avec statut, v2.3) ────────────────────────────────────────

@router.get("/dossier/{dossier_id}/docx", summary="Télécharger le DOCX d'un dossier")
async def telecharger_docx(dossier_id: str):
    for filename in os.listdir(DOCX_OUTPUT_DIR):
        if filename.startswith(f"dossier_{dossier_id}") and filename.endswith(".docx"):
            filepath = os.path.join(DOCX_OUTPUT_DIR, filename)
            return FileResponse(
                path       = filepath,
                filename   = filename,
                media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            )
    # Fichier absent : expliquer pourquoi grâce au statut en base
    dossier = persistence_lire(dossier_id)
    if dossier:
        statut_docx = dossier.get("statut_docx", "aucun")
        if statut_docx == "en_cours":
            raise HTTPException(status_code=425, detail="Le DOCX est en cours de génération. Réessayez dans quelques secondes.")
        if statut_docx == "erreur":
            raise HTTPException(status_code=500, detail="La génération du DOCX a échoué. Régénérer le dossier ou contacter le support.")
        if statut_docx == "aucun":
            raise HTTPException(status_code=404, detail="Aucun export DOCX n'a été demandé pour ce dossier.")
    raise HTTPException(status_code=404, detail=f"DOCX du dossier {dossier_id} non trouvé.")


@router.get("/dossier/{dossier_id}/docx/statut", summary="Statut de génération du DOCX")
async def statut_docx(dossier_id: str):
    dossier = persistence_lire(dossier_id)
    if not dossier:
        raise HTTPException(status_code=404, detail=f"Dossier {dossier_id} non trouvé.")
    return {"dossier_id": dossier_id, "statut_docx": dossier.get("statut_docx", "aucun")}


# ── Health check ──────────────────────────────────────────────────────────────

@router.get("/health", summary="État du service Amiin Legal")
async def health_check():
    counts = persistence_compter()
    return {
        "service":          "amiin_legal",
        "version":          "2.3",
        "statut":           "ok" if RAG_DISPONIBLE else "dégradé",
        "rag_disponible":   RAG_DISPONIBLE,
        "model_expansion":  MODEL_EXPANSION,
        "model_generation": MODEL_GENERATION,
        "types_affaires":   len(TYPES_AFFAIRES),
        "mode_demo":        MODE_DEMO,
        "chiffrement":      "actif" if _fernet else "inactif",
        "persistance": {
            "sqlite":       SQLITE_DB_PATH,
            "google_drive": "activé" if GDRIVE_FOLDER_ID else "désactivé",
            "fs_backup":    FS_BACKUP_DIR if FS_BACKUP_DIR else "désactivé",
        },
        "dossiers_en_attente": counts.get("en_attente", 0),
        "ameliorations_actives": [
            "prescription_auto",
            "validation_senior_junior",
            "lettre_client",
            "persistance_sqlite",
            "backup_drive_fs",
            "radar_prescription",
            "claude_async_retry",
            "versionnage_dossiers",
            "statut_docx",
            "calendrier_ics",
            "chiffrement_optionnel" if _fernet else "chiffrement_disponible_non_actif",
        ],
        "timestamp": datetime.now().isoformat(),
    }


# =============================================================================
# INTÉGRATION & CONFIGURATION
# =============================================================================
#
# Intégration dans amiin_api.py :
#   from amiin_legal_api import router as legal_router
#   app.include_router(legal_router)
#
# Variables d'environnement :
#   ANTHROPIC_API_KEY              — REQUIS
#   AMIIN_SQLITE_PATH              — chemin SQLite (défaut ./amiin_legal_dossiers.db)
#   AMIIN_FS_BACKUP_DIR            — répertoire backup JSON (ex: D:/backups/amiin)
#   GOOGLE_DRIVE_FOLDER_ID         — ID dossier Drive (backup Drive)
#   GOOGLE_APPLICATION_CREDENTIALS — JSON compte de service Google
#   AMIIN_ENCRYPT_KEY              — clé Fernet (chiffrement au repos)
#   AMIIN_DEMO                     — "1" pour insérer des dossiers démo si base vide
#
# Dépendances optionnelles :
#   python.exe -m pip install cryptography                              (chiffrement)
#   python.exe -m pip install google-api-python-client google-auth     (Drive)
#
# Nouveaux endpoints v2.3 :
#   GET /v1/legal/alertes                          ← RADAR DE PRESCRIPTION
#   GET /v1/legal/dossiers                         ← liste complète
#   GET /v1/legal/dossiers/{id}/historique         ← versions archivées
#   GET /v1/legal/dossier/{id}/calendrier.ics      ← export calendrier
#   GET /v1/legal/dossier/{id}/docx/statut         ← suivi génération DOCX
# =============================================================================
