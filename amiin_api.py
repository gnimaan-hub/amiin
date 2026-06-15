# -*- coding: utf-8 -*-
"""
amiin_api.py - Serveur API FastAPI pour l'app mobile Amiin
Connecte l'app Flutter au pipeline RAG (ChromaDB + Claude)
v2.2 : streaming SSE, skip expand auto, cache LRU embedding, parallélisation.
"""

import os
import json
import math
import time
import asyncio
import logging
import functools
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from logging.handlers import RotatingFileHandler
from typing import Optional, List, Any, Dict
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

import requests as _requests
from dotenv import load_dotenv
load_dotenv()   # charge .env en local ; no-op sur Render (env vars injectées)

from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, Filter, FieldCondition, MatchValue, MatchAny
from anthropic import Anthropic, AsyncAnthropic

# ══════════════════════════════════════════════════════════════════════════════
# LOGGER FICHIER — trace complète de chaque requête (diagnostic + debug)
# ══════════════════════════════════════════════════════════════════════════════

_req_logger = logging.getLogger('amiin.requests')
_req_logger.setLevel(logging.DEBUG)
_req_logger.propagate = False   # ne remonte pas dans le logger root de FastAPI

# Handler fichier (historique persistant en session)
_req_fh = RotatingFileHandler(
    'amiin_requests.log', maxBytes=5 * 1024 * 1024, backupCount=5, encoding='utf-8'
)
_req_fh.setFormatter(logging.Formatter('%(message)s'))
_req_logger.addHandler(_req_fh)

# Handler stdout (visible dans le dashboard Render en temps réel)
_req_sh = logging.StreamHandler()
_req_sh.setFormatter(logging.Formatter('[REQ] %(message)s'))
_req_logger.addHandler(_req_sh)

def _log_request(data: dict) -> None:
    """Écrit une ligne JSON dans amiin_requests.log ET sur stdout (Render dashboard)."""
    _req_logger.info(json.dumps(data, ensure_ascii=False))

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

DB_PATH        = './amiin_db'            # Conservé pour fallback local uniquement
COLLECTION     = 'djibouti_knowledge'
JINA_MODEL     = 'jina-embeddings-v3'   # API Jina AI — remplace SentenceTransformers local
JINA_EMBED_DIM = 1024                   # dimension du modèle jina-embeddings-v3
QDRANT_COLLECTION = 'djibouti_knowledge'
MODEL_CLAUDE   = 'claude-haiku-4-5-20251001'
EXPAND_MODEL   = 'claude-haiku-4-5-20251001'
TOP_K          = 10
TOP_K_FINAL    = 12
MAX_TOKENS     = 2048
TEMPERATURE    = 0.3

HOST = '0.0.0.0'
PORT = int(os.environ.get('PORT', 8000))   # Render injecte $PORT automatiquement

# Préfixes conversationnels → on skip l'expand pour économiser ~3s
_FOLLOWUP_PREFIXES = (
    "et ", "mais ", "ok", "merci", "oui", "non ", "ah ", "super",
    "parfait", "d'accord", "bien sûr", "ça ", "c'est ", "donc ",
    "pourquoi ", "comment ", "combien", "quand ", "où ", "qui ",
    "dis-moi", "explique", "donne",
)

# ══════════════════════════════════════════════════════════════════════════════
# PROMPTS
# ══════════════════════════════════════════════════════════════════════════════

SYSTEM_PROMPT_BASE = """Tu es Amiin, un assistant IA de confiance sur Djibouti. Tu parles comme un ami bien informé, pas comme un manuel.

Tu aides avec les lois djiboutiennes, les démarches administratives, la vie pratique, le tourisme et les services publics.

STYLE — RÈGLES STRICTES :
- Réponds en 3-4 phrases maximum, comme dans une conversation WhatsApp.
- AUCUNE liste à puces, AUCUN titre markdown, AUCUN gras. Texte continu uniquement.
- Exception unique : si la réponse exige une liste d'étapes ou de documents obligatoires, tu peux faire une liste numérotée courte (4 items max). Seulement si c'est vraiment inévitable.
- Termine par UNE SEULE question ou suggestion de suivi, la plus naturelle. Pas plusieurs options. Si rien n'est pertinent, ne demande rien.
- Réponse simple à question simple. Pas de contexte ou d'historique non demandé.
- Numéro de téléphone, adresse, prix : donne-les directement, sans introduction.
- JURIDIQUE — règle impérative : dès que ta réponse porte sur le droit djiboutien (civil, pénal, du travail, commercial, de la famille, administratif…), tu dois citer le texte de référence et le(s) numéro(s) d'article exacts. Format court en fin de phrase : (Code du travail djiboutien, art. 45) ou (Code pénal, art. 162). Si tu n'es pas certain du numéro exact, dis-le honnêtement — ne jamais inventer un article.
- Ton chaleureux, direct, naturel.

CONTENU :
- Utilise en priorité le CONTEXTE ci-dessous (base de connaissances juridique et pratique sur Djibouti).
- Complète avec tes connaissances si le contexte est insuffisant.
- Ne fabrique jamais de données spécifiques absentes du contexte.
- Pour create_event : la description interne doit être détaillée (documents, contacts, étapes), mais ta réponse textuelle reste courte.

AGENDA ET NOTES — RÈGLE ABSOLUE (sans aucune exception) :
Tu n'as PAS accès au contenu de l'agenda ni des notes en mémoire. Sans appel d'outil, tu ignores totalement ce que l'utilisateur a planifié ou écrit. Ne devine jamais, ne suppose jamais, n'invente jamais.

Agenda — quand appeler get_events :
- Dès que la question mentionne : rendez-vous, événement, planning, disponibilité, "quand", "est-ce que j'ai", "qu'est-ce que j'ai de prévu", horaires, semaine, agenda.
- Utilise la plage de dates la plus logique selon la question (aujourd'hui, cette semaine, ce mois…).

Notes — quand appeler get_notes :
- Dès que la question mentionne : "mes notes", "une note", "j'ai noté", "relis", "relis-la", "relis-moi ça", "relis la moi", "tu m'en avais parlé", "retrouve", "est-ce qu'il y a une note", "qu'est-ce que j'ai écrit".
- Si l'utilisateur dit "relis-la" ou "relis la moi" sans préciser, appelle get_notes avec le sujet de la dernière note mentionnée dans la conversation comme query.
- Même si tu crois te souvenir d'une note citée plus tôt dans la conversation : appelle quand même get_notes pour en obtenir le contenu exact avant de le citer ou de l'analyser.
- Sans get_notes, tu ne connais ni le titre, ni le contenu, ni l'existence d'une note."""

EXPAND_PROMPT = """Tu es un expert en recherche d'information sur Djibouti.
L'utilisateur pose une question. Tu dois la reformuler en EXACTEMENT 3 variantes pour maximiser les chances de trouver l'information dans une base de données juridique et pratique.

Règles :
- Variante 1 : reformulation en termes JURIDIQUES/TECHNIQUES
- Variante 2 : reformulation en termes PRATIQUES/QUOTIDIENS
- Variante 3 : MOTS-CLÉS essentiels (5-8 mots maximum)

Réponds UNIQUEMENT en JSON, sans backticks :
{"v1": "...", "v2": "...", "v3": "..."}

Question : {query}"""

# ─── Outils ───────────────────────────────────────────────────────────────────

TOOLS = [
    {
        "name": "create_event",
        "description": "Créer un événement dans l'agenda (réunion, rappel, rendez-vous)",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "Titre de l'événement"},
                "description": {"type": "string", "description": "Description détaillée (documents, contacts, étapes)"},
                "start_date": {"type": "string", "description": "Date de début (ISO 8601)"},
                "end_date": {"type": "string", "description": "Date de fin (ISO 8601)"},
                "category": {
                    "type": "string",
                    "enum": ["admin", "personal", "health", "education", "other"]
                },
                "location": {"type": "string"},
                "reminder_minutes": {"type": "integer"}
            },
            "required": ["title", "start_date", "end_date", "category"]
        }
    },
    {
        "name": "update_event",
        "description": "Modifier un événement existant dans l'agenda",
        "input_schema": {
            "type": "object",
            "properties": {
                "event_id": {"type": "string"},
                "title": {"type": "string"},
                "description": {"type": "string"},
                "start_date": {"type": "string"},
                "end_date": {"type": "string"},
                "category": {"type": "string", "enum": ["admin", "personal", "health", "education", "other"]},
                "location": {"type": "string"},
                "reminder_minutes": {"type": "integer"}
            },
            "required": ["event_id"]
        }
    },
    {
        "name": "delete_event",
        "description": "Supprimer un événement de l'agenda",
        "input_schema": {
            "type": "object",
            "properties": {"event_id": {"type": "string"}},
            "required": ["event_id"]
        }
    },
    {
        "name": "create_note",
        "description": "Créer une nouvelle note",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "content": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "is_pinned": {"type": "boolean"}
            },
            "required": ["title", "content"]
        }
    },
    {
        "name": "update_note",
        "description": "Modifier une note existante",
        "input_schema": {
            "type": "object",
            "properties": {
                "note_id": {"type": "string"},
                "title": {"type": "string"},
                "content": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
                "is_pinned": {"type": "boolean"}
            },
            "required": ["note_id"]
        }
    },
    {
        "name": "delete_note",
        "description": "Supprimer une note",
        "input_schema": {
            "type": "object",
            "properties": {"note_id": {"type": "string"}},
            "required": ["note_id"]
        }
    },
    {
        "name": "get_events",
        "description": "Récupérer les événements de l'agenda de l'utilisateur pour une plage de dates donnée",
        "input_schema": {
            "type": "object",
            "properties": {
                "from_date": {"type": "string", "description": "Date de début (ISO 8601, ex: 2026-06-09T00:00:00)"},
                "to_date": {"type": "string", "description": "Date de fin (ISO 8601, ex: 2026-06-16T23:59:59)"}
            },
            "required": ["from_date", "to_date"]
        }
    },
    {
        "name": "get_notes",
        "description": "Récupérer les notes de l'utilisateur",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "tag": {"type": "string"}
            },
            "required": []
        }
    },
    {
        "name": "start_demarche",
        "description": "Démarrer une démarche administrative",
        "input_schema": {
            "type": "object",
            "properties": {
                "demarche_id": {"type": "string"},
                "notes": {"type": "string"}
            },
            "required": ["demarche_id"]
        }
    },
    {
        "name": "search_services",
        "description": "Rechercher un service public dans l'annuaire",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "category": {
                    "type": "string",
                    "enum": ["ministere", "mairie", "sante", "education", "justice", "securite", "transport", "economie", "autre"]
                }
            },
            "required": ["query"]
        }
    },
]

# ══════════════════════════════════════════════════════════════════════════════
# MODÈLES PYDANTIC
# ══════════════════════════════════════════════════════════════════════════════

class ChatMessage(BaseModel):
    role: str
    content: str

class ChatRequest(BaseModel):
    message: str
    history: Optional[List[ChatMessage]] = None
    system: Optional[str] = None
    expand: Optional[bool] = True
    pending_tool_uses: Optional[List[Dict[str, Any]]] = None
    tool_results: Optional[List[Dict[str, Any]]] = None
    lat: Optional[float] = None
    lon: Optional[float] = None

class ToolCall(BaseModel):
    id: str
    name: str
    input: Dict[str, Any]

class ChatResponse(BaseModel):
    reply: str
    tool_calls: List[ToolCall] = []
    sources: List[Dict[str, Any]] = []
    processing_time: float

class HealthResponse(BaseModel):
    status: str
    chunks_count: int
    model_embed: str
    model_llm: str

class StatsResponse(BaseModel):
    total_chunks: int
    categories: dict
    sources: dict

class ServiceAddressOut(BaseModel):
    street: str = ""
    district: str = ""
    city: str = "Djibouti-ville"
    coordinates: Optional[Dict[str, float]] = None

class AmiinServiceOut(BaseModel):
    id: str
    name: str
    ministry: Optional[str] = None
    category: str = "autre"
    description: Optional[str] = None
    phone: Optional[str] = None
    email: Optional[str] = None
    website: Optional[str] = None
    address: ServiceAddressOut
    hours: Optional[List[Dict]] = None
    isFavorite: bool = False
    distanceKm: Optional[float] = None

# ══════════════════════════════════════════════════════════════════════════════
# COMPOSANTS GLOBAUX
# ══════════════════════════════════════════════════════════════════════════════

jina_api_key: str = ""
qdrant_client: QdrantClient = None
collection = None          # ChromaDB — conservé pour compatibilité stats locale
claude_client: Anthropic = None
async_claude: AsyncAnthropic = None

_favorites: set = set()

_owm_api_key: str = ""
_weather_cache: dict = {}   # {cache_key: (context_str, fetched_at_unix)}
_WEATHER_TTL = 900           # 15 min

def _load_env_key(key_name: str) -> str:
    """Lit une clé depuis les variables d'environnement ou le fichier .env."""
    val = os.environ.get(key_name, '')
    if not val:
        env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
        if os.path.exists(env_path):
            with open(env_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith(f'{key_name}='):
                        val = line.split('=', 1)[1].strip().strip('"').strip("'")
                        break
    return val

def load_components():
    global jina_api_key, qdrant_client, collection, claude_client, async_claude

    # ── Jina AI (embeddings) ──────────────────────────────────────────────────
    logging.info("Chargement de la clé Jina AI...")
    jina_key = _load_env_key('JINA_API_KEY')
    if not jina_key or 'REMPLIR' in jina_key:
        raise RuntimeError("JINA_API_KEY manquante ! Ajouter dans .env : JINA_API_KEY=jina_...")
    jina_api_key = jina_key
    logging.info("✅ Clé Jina AI chargée.")

    # ── Qdrant Cloud (base vectorielle) ──────────────────────────────────────
    logging.info("Connexion à Qdrant Cloud...")
    qdrant_url = _load_env_key('QDRANT_URL')
    qdrant_api_key = _load_env_key('QDRANT_API_KEY')
    if not qdrant_url or 'REMPLIR' in qdrant_url:
        raise RuntimeError("QDRANT_URL manquante ! Ajouter dans .env : QDRANT_URL=https://...")
    qdrant_client = QdrantClient(url=qdrant_url, api_key=qdrant_api_key, timeout=30)
    info = qdrant_client.get_collection(QDRANT_COLLECTION)
    logging.info(f"✅ Qdrant connecté : {info.points_count} chunks dans '{QDRANT_COLLECTION}'.")

    # ── Anthropic (LLM) ───────────────────────────────────────────────────────
    logging.info("Initialisation du client Anthropic...")
    api_key = _load_env_key('ANTHROPIC_API_KEY')
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY manquante ! Créer .env avec ANTHROPIC_API_KEY=sk-ant-...")
    claude_client = Anthropic(api_key=api_key)
    async_claude = AsyncAnthropic(api_key=api_key)
    logging.info("✅ Tous les composants chargés.")

    # ── OpenWeatherMap (météo optionnelle) ────────────────────────────────────
    global _owm_api_key
    _owm_api_key = _load_env_key('OWM_API_KEY')
    if _owm_api_key:
        logging.info("✅ Clé OWM chargée — météo activée.")
    else:
        logging.warning("⚠️  OWM_API_KEY absente — météo désactivée.")

# ══════════════════════════════════════════════════════════════════════════════
# PIPELINE RAG
# ══════════════════════════════════════════════════════════════════════════════

# ── B : skip expand pour requêtes courtes ou de suivi ────────────────────────

def _should_expand(query: str) -> bool:
    q = query.strip().lower()
    if len(q) < 55:
        return False
    if any(q.startswith(p) for p in _FOLLOWUP_PREFIXES):
        return False
    return True

# ── C : cache LRU sur les embeddings ─────────────────────────────────────────

def _jina_embed_batch(texts: list, task: str = "retrieval.query") -> tuple:
    """Appel API Jina AI — retourne (list_of_embeddings, total_tokens_used)."""
    resp = _requests.post(
        "https://api.jina.ai/v1/embeddings",
        headers={
            "Authorization": f"Bearer {jina_api_key}",
            "Content-Type": "application/json"
        },
        json={"model": JINA_MODEL, "input": texts, "task": task},
        timeout=15
    )
    resp.raise_for_status()
    data = resp.json()
    tokens = data.get("usage", {}).get("total_tokens", 0)
    return [item["embedding"] for item in data["data"]], tokens

# Cache manuel (remplace @lru_cache) pour permettre le suivi des tokens Jina
_embed_cache: dict = {}   # {text: embedding_list}
_EMBED_CACHE_MAX = 256

def _cached_embed(text: str, token_acc: list = None) -> tuple:
    """Retourne l'embedding (tuple).  Si token_acc=[0], cumule les tokens Jina consommés."""
    if text in _embed_cache:
        return tuple(_embed_cache[text])   # cache hit — aucun appel Jina
    embeddings, tokens = _jina_embed_batch([text])
    result = embeddings[0]
    if len(_embed_cache) >= _EMBED_CACHE_MAX:
        del _embed_cache[next(iter(_embed_cache))]   # éviction FIFO
    _embed_cache[text] = result
    if token_acc is not None:
        token_acc[0] += tokens
    return tuple(result)

def _search_with_embedding(embedding: list, top_k: int, category: str = None,
                           query_filter=None) -> list:
    """Recherche vectorielle dans Qdrant. Retourne des chunks triés par distance (plus petit = meilleur)."""
    if query_filter is None and category and category != 'autre':
        query_filter = Filter(
            must=[FieldCondition(key="category", match=MatchValue(value=category))]
        )
    hits = qdrant_client.search(
        collection_name=QDRANT_COLLECTION,
        query_vector=embedding,
        limit=top_k,
        query_filter=query_filter,
        with_payload=True
    )
    return [
        {
            'id': str(hit.id),
            'document': hit.payload.get('document', ''),
            'metadata': {k: v for k, v in hit.payload.items() if k != 'document'},
            'distance': 1.0 - hit.score,  # score cosine → distance (0=identique, 2=opposé)
        }
        for hit in hits
    ]

def expand_query(query: str) -> list:
    try:
        response = claude_client.messages.create(
            model=EXPAND_MODEL,
            max_tokens=300,
            temperature=0.0,
            messages=[{"role": "user", "content": EXPAND_PROMPT.replace("{query}", query)}]
        )
        _log_usage(response.usage, "[expand] ")
        texte = response.content[0].text.strip().replace('```json', '').replace('```', '').strip()
        variantes = json.loads(texte)
        return [query, variantes.get('v1', ''), variantes.get('v2', ''), variantes.get('v3', '')]
    except Exception as e:
        logging.warning(f"Expansion échouée: {e}")
        return [query]

def build_context(chunks: list) -> str:
    parts = []
    for i, chunk in enumerate(chunks, 1):
        meta = chunk['metadata']
        parts.append(
            f"[Source {i}: {meta.get('source', '')} | {meta.get('title', '')} | {meta.get('category', '')}]\n"
            f"{chunk['document']}"
        )
    return '\n\n---\n\n'.join(parts)

def _log_usage(usage, label: str = ""):
    cache_write = getattr(usage, 'cache_creation_input_tokens', 0) or 0
    cache_read  = getattr(usage, 'cache_read_input_tokens', 0) or 0
    logging.info(
        f"Tokens {label}| input: {usage.input_tokens} "
        f"(cache_write: {cache_write}, cache_hit: {cache_read}) | "
        f"output: {usage.output_tokens}"
    )

def _fetch_weather_context(lat: float, lon: float) -> str:
    """Retourne un bloc météo OWM formaté pour le system prompt, ou '' si indisponible."""
    if not _owm_api_key:
        return ""
    cache_key = f"{lat:.2f},{lon:.2f}"
    cached = _weather_cache.get(cache_key)
    if cached:
        ctx, ts = cached
        if time.time() - ts < _WEATHER_TTL:
            return ctx
    try:
        from datetime import datetime as _dt
        base = "https://api.openweathermap.org/data/2.5"
        params = {"lat": lat, "lon": lon, "appid": _owm_api_key, "units": "metric", "lang": "fr"}
        cw = _requests.get(f"{base}/weather", params=params, timeout=5).json()
        temp = round(cw["main"]["temp"])
        desc = cw["weather"][0]["description"] if cw.get("weather") else ""
        buf = [f"Météo actuelle : {temp}°C, {desc}"]
        fc = _requests.get(f"{base}/forecast", params=params, timeout=5).json()
        today = _dt.utcnow().date()
        days: dict = {}
        for item in fc.get("list", []):
            d = _dt.utcfromtimestamp(item["dt"]).date()
            if d >= today:
                days.setdefault(d, []).append(item)
        buf.append("Prévisions météo :")
        for day in sorted(days)[:3]:
            slots = days[day]
            temps = [s["main"]["temp"] for s in slots]
            pm = next(
                (s for s in slots if 12 <= _dt.utcfromtimestamp(s["dt"]).hour <= 15),
                slots[len(slots) // 2],
            )
            desc_day = pm["weather"][0]["description"] if pm.get("weather") else ""
            diff = (day - today).days
            if diff == 0:
                label = "Aujourd'hui"
            elif diff == 1:
                label = "Demain"
            else:
                label = ["lundi","mardi","mercredi","jeudi","vendredi","samedi","dimanche"][day.weekday()]
            buf.append(f"- {label} : {round(min(temps))}–{round(max(temps))}°C, {desc_day}")
        ctx = "\n".join(buf)
        _weather_cache[cache_key] = (ctx, time.time())
        return ctx
    except Exception as e:
        logging.warning(f"Météo OWM indisponible: {e}")
        return ""


def _build_system(context: str, system_override: str = None) -> list:
    dynamic_parts = []
    if context:
        dynamic_parts.append(f"CONTEXTE (base de connaissances) :\n{context}")
    if system_override:
        dynamic_parts.append(f"## Contexte temps réel de l'utilisateur :\n{system_override}")

    blocks = [
        {
            "type": "text",
            "text": SYSTEM_PROMPT_BASE,
            "cache_control": {"type": "ephemeral"}
        }
    ]
    if dynamic_parts:
        blocks.append({"type": "text", "text": "\n\n".join(dynamic_parts)})
    return blocks

def _build_messages(query: str, history, pending_tool_uses=None, tool_results=None) -> list:
    msgs = []
    if history:
        for msg in history[-10:]:
            msgs.append({"role": msg.role, "content": msg.content})
    msgs.append({"role": "user", "content": query})

    if pending_tool_uses and tool_results:
        # 2e passe : ajouter le message assistant avec tool_use + le résultat utilisateur
        msgs.append({
            "role": "assistant",
            "content": [
                {"type": "tool_use", "id": tc["id"], "name": tc["name"], "input": tc["input"]}
                for tc in pending_tool_uses
            ]
        })
        msgs.append({
            "role": "user",
            "content": [
                {"type": "tool_result", "tool_use_id": tr["tool_use_id"], "content": tr["content"]}
                for tr in tool_results
            ]
        })

    return msgs

# ── D : pipeline synchrone avec parallélisation ──────────────────────────────

def run_pipeline(query: str, history=None, expand: bool = True, system: str = None,
                 lat: float = None, lon: float = None,
                 pending_tool_uses=None, tool_results=None) -> dict:
    t0 = time.time()
    chunks = []

    if lat is not None and lon is not None:
        weather_ctx = _fetch_weather_context(lat, lon)
        if weather_ctx:
            system = f"{system}\n{weather_ctx}" if system else weather_ctx

    if tool_results:
        # 2e passe : pas de RAG, on répond avec les résultats d'outils
        context = ""
    else:
        should_exp = expand and _should_expand(query)
        direct_embedding = list(_cached_embed(query))

        if should_exp:
            with ThreadPoolExecutor(max_workers=2) as ex:
                expand_future = ex.submit(expand_query, query)
                direct_future = ex.submit(_search_with_embedding, direct_embedding, TOP_K)
                direct_chunks = direct_future.result()
                queries = expand_future.result()

            extras = [q for q in queries[1:] if q.strip()]
            all_chunks: dict = {c['id']: c for c in direct_chunks}
            if extras:
                extra_embeddings, _ = _jina_embed_batch(extras)
                for emb in extra_embeddings:
                    for chunk in _search_with_embedding(emb, TOP_K):
                        cid = chunk['id']
                        if cid not in all_chunks or chunk['distance'] < all_chunks[cid]['distance']:
                            all_chunks[cid] = chunk
            chunks = sorted(all_chunks.values(), key=lambda c: c['distance'])[:TOP_K_FINAL]
        else:
            chunks = _search_with_embedding(direct_embedding, TOP_K_FINAL)

        context = build_context(chunks)

    response = claude_client.messages.create(
        model=MODEL_CLAUDE,
        max_tokens=MAX_TOKENS,
        temperature=TEMPERATURE,
        system=_build_system(context, system),
        tools=TOOLS,
        messages=_build_messages(query, history, pending_tool_uses, tool_results),
        extra_headers={"anthropic-beta": "prompt-caching-2024-07-31"},
    )

    _log_usage(response.usage, "[sync] ")

    reply_text = ""
    tool_calls = []
    for block in response.content:
        if block.type == "text":
            reply_text = block.text
        elif block.type == "tool_use":
            tool_calls.append({"id": block.id, "name": block.name, "input": block.input})

    sources = [
        {"title": c['metadata'].get('title', '?'), "source": c['metadata'].get('source', '?'),
         "category": c['metadata'].get('category', '?'), "distance": round(c['distance'], 4)}
        for c in chunks
    ] if chunks else []
    return {"reply": reply_text, "tool_calls": tool_calls, "sources": sources,
            "processing_time": round(time.time() - t0, 2)}

# ── A : pipeline streaming (async) ───────────────────────────────────────────

async def _stream_pipeline(query: str, history=None, expand: bool = True, system: str = None,
                           lat: float = None, lon: float = None,
                           pending_tool_uses=None, tool_results=None):
    t0 = time.time()
    loop = asyncio.get_event_loop()
    chunks = []
    jina_acc = [0]   # accumulateur de tokens Jina pour cette requête
    is_second_pass = bool(tool_results)

    if lat is not None and lon is not None:
        weather_ctx = await loop.run_in_executor(None, _fetch_weather_context, lat, lon)
        if weather_ctx:
            system = f"{system}\n{weather_ctx}" if system else weather_ctx

    if tool_results:
        # 2e passe : pas de RAG, réponse directe avec les résultats d'outils
        context = ""
        yield f'data: {json.dumps({"type": "status", "text": "Amiin réfléchit…"})}\n\n'
    else:
        # 1re passe : pipeline RAG complet
        should_exp = expand and _should_expand(query)
        direct_embedding = list(_cached_embed(query, token_acc=jina_acc))
        yield f'data: {json.dumps({"type": "status", "text": "Recherche…"})}\n\n'

        if should_exp:
            expand_task = loop.run_in_executor(None, expand_query, query)
            direct_task = loop.run_in_executor(None, _search_with_embedding, direct_embedding, TOP_K)
            queries, direct_chunks = await asyncio.gather(expand_task, direct_task)

            extras = [q for q in queries[1:] if q.strip()]
            all_chunks: dict = {c['id']: c for c in direct_chunks}
            if extras:
                extra_embs_raw, extra_tokens = await loop.run_in_executor(
                    None, lambda: _jina_embed_batch(extras)
                )
                jina_acc[0] += extra_tokens
                for emb in extra_embs_raw:
                    for chunk in _search_with_embedding(emb, TOP_K):
                        cid = chunk['id']
                        if cid not in all_chunks or chunk['distance'] < all_chunks[cid]['distance']:
                            all_chunks[cid] = chunk
            chunks = sorted(all_chunks.values(), key=lambda c: c['distance'])[:TOP_K_FINAL]
        else:
            chunks = await loop.run_in_executor(None, _search_with_embedding, direct_embedding, TOP_K_FINAL)

        context = build_context(chunks)
        yield f'data: {json.dumps({"type": "status", "text": "Amiin réfléchit…"})}\n\n'

    tool_calls = []
    final_usage = None
    async with async_claude.messages.stream(
        model=MODEL_CLAUDE,
        max_tokens=MAX_TOKENS,
        temperature=TEMPERATURE,
        system=_build_system(context, system),
        tools=TOOLS,
        messages=_build_messages(query, history, pending_tool_uses, tool_results),
        extra_headers={"anthropic-beta": "prompt-caching-2024-07-31"},
    ) as stream:
        async for text in stream.text_stream:
            yield f'data: {json.dumps({"type": "token", "text": text})}\n\n'
        final_msg = await stream.get_final_message()
        final_usage = final_msg.usage
        _log_usage(final_usage, "[stream] ")
        for block in final_msg.content:
            if block.type == "tool_use":
                tool_calls.append({"id": block.id, "name": block.name, "input": block.input})

    sources = [
        {"title": c['metadata'].get('title', '?'), "source": c['metadata'].get('source', '?'),
         "category": c['metadata'].get('category', '?'), "distance": round(c['distance'], 4)}
        for c in chunks
    ] if chunks else []

    # ── Métriques usage ───────────────────────────────────────────────────────
    claude_in  = getattr(final_usage, 'input_tokens', 0) if final_usage else 0
    claude_out = getattr(final_usage, 'output_tokens', 0) if final_usage else 0
    cache_read = getattr(final_usage, 'cache_read_input_tokens', 0) or 0
    cache_write = getattr(final_usage, 'cache_creation_input_tokens', 0) or 0
    usage = {
        "claude_input":      claude_in,
        "claude_output":     claude_out,
        "claude_cache_read": cache_read,
        "jina_tokens":       jina_acc[0],
        "tools":             [tc["name"] for tc in tool_calls],
        "pass":              2 if is_second_pass else 1,
    }

    # ── Log fichier ───────────────────────────────────────────────────────────
    _log_request({
        "ts":              time.strftime("%Y-%m-%dT%H:%M:%S"),
        "query":           query[:300],
        "history_len":     len(history) if history else 0,
        "pass":            usage["pass"],
        "expand":          expand and not is_second_pass,
        "jina_tokens":     jina_acc[0],
        "claude_input":    claude_in,
        "claude_output":   claude_out,
        "claude_cache_read":  cache_read,
        "claude_cache_write": cache_write,
        "tools":           usage["tools"],
        "sources_count":   len(sources),
        "processing_time": round(time.time() - t0, 2),
    })

    yield f'data: {json.dumps({"type": "done", "tool_calls": tool_calls, "sources": sources, "processing_time": round(time.time() - t0, 2), "usage": usage})}\n\n'

# ══════════════════════════════════════════════════════════════════════════════
# ANNUAIRE
# ══════════════════════════════════════════════════════════════════════════════

def _haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat, dlon = math.radians(lat2 - lat1), math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return round(R * 2 * math.asin(math.sqrt(a)), 2)

def _chunk_to_service(chunk_id, document, metadata, ref_lat=None, ref_lng=None, is_favorite=False):
    svc_lat = metadata.get('latitude') or metadata.get('lat')
    svc_lng = metadata.get('longitude') or metadata.get('lng')
    coords = {"lat": float(svc_lat), "lng": float(svc_lng)} if svc_lat and svc_lng else None
    dist = _haversine_km(ref_lat, ref_lng, float(svc_lat), float(svc_lng)) if (ref_lat and ref_lng and svc_lat and svc_lng) else None
    # Préfère le nom et la catégorie du nouveau format annuaire
    name     = metadata.get('nom') or metadata.get('title') or metadata.get('name') or document[:60]
    cat_full = metadata.get('categorie') or metadata.get('category', 'autre')
    sous_cat = metadata.get('sous_categorie') or metadata.get('sous_category') or ''
    quartier = metadata.get('quartier') or metadata.get('district') or ''
    ville    = metadata.get('ville_region') or metadata.get('city') or 'Djibouti-ville'
    return {
        "id":           chunk_id,
        "name":         name,
        "ministry":     metadata.get('ministry') or metadata.get('ministere'),
        "category":     cat_full,
        "sous_categorie": sous_cat,
        "quartier":     quartier,
        "description":  document[:300] if document else None,
        "phone":        metadata.get('telephone') or metadata.get('phone'),
        "email":        metadata.get('email'),
        "website":      metadata.get('site_web') or metadata.get('website') or metadata.get('url'),
        "hours":        metadata.get('horaires'),
        "address": {
            "street":      metadata.get('adresse') or metadata.get('address') or '',
            "district":    quartier,
            "city":        ville,
            "coordinates": coords,
        },
        "isFavorite": is_favorite,
        "distanceKm": dist,
    }

# ══════════════════════════════════════════════════════════════════════════════
# APPLICATION FASTAPI
# ══════════════════════════════════════════════════════════════════════════════

@asynccontextmanager
async def lifespan(app: FastAPI):
    load_components()
    yield

app = FastAPI(
    title="Amiin API",
    description="Assistant IA Djibouti — RAG + outils + streaming SSE",
    version="2.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Health ───────────────────────────────────────────────────────────────────

@app.get("/v1/logs")
async def get_logs(n: int = 100, secret: Optional[str] = None):
    """Retourne les n dernières lignes de amiin_requests.log.
    Protégé par la variable d'env LOG_SECRET si elle est définie."""
    log_secret = os.environ.get("LOG_SECRET", "")
    if log_secret and secret != log_secret:
        raise HTTPException(status_code=401, detail="Secret invalide. Ajouter ?secret=… dans l'URL.")
    log_path = "amiin_requests.log"
    if not os.path.exists(log_path):
        return {"lines": [], "total": 0, "message": "Aucun log encore — le fichier est créé dès le premier message."}
    with open(log_path, encoding="utf-8") as f:
        all_lines = f.readlines()
    last_n = all_lines[-n:] if len(all_lines) > n else all_lines
    parsed = []
    for line in reversed(last_n):   # plus récent en premier
        line = line.strip()
        if line:
            try:
                parsed.append(json.loads(line))
            except Exception:
                parsed.append({"raw": line})
    return {"lines": parsed, "total": len(all_lines), "returned": len(parsed)}

@app.get("/v1/chat/health", response_model=HealthResponse)
async def health():
    chunks_count = 0
    if qdrant_client:
        try:
            chunks_count = qdrant_client.get_collection(QDRANT_COLLECTION).points_count
        except Exception:
            pass
    return HealthResponse(status="ok", chunks_count=chunks_count,
                          model_embed=JINA_MODEL, model_llm=MODEL_CLAUDE)

# ─── Chat non-streaming (fallback) ────────────────────────────────────────────

@app.post("/v1/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Le message ne peut pas être vide.")
    try:
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            None,
            functools.partial(run_pipeline, query=request.message, history=request.history,
                              expand=request.expand if request.expand is not None else True,
                              system=request.system,
                              lat=request.lat, lon=request.lon,
                              pending_tool_uses=request.pending_tool_uses,
                              tool_results=request.tool_results),
        )
        return ChatResponse(
            reply=result["reply"],
            tool_calls=[ToolCall(id=tc["id"], name=tc["name"], input=tc["input"]) for tc in result["tool_calls"]],
            sources=result["sources"],
            processing_time=result["processing_time"],
        )
    except Exception as e:
        logging.error(f"Erreur pipeline: {e}")
        raise HTTPException(status_code=500, detail=f"Erreur interne: {str(e)}")

# ─── Chat streaming SSE ───────────────────────────────────────────────────────

@app.post("/v1/chat/stream")
async def chat_stream(request: ChatRequest):
    if not request.message.strip():
        raise HTTPException(status_code=400, detail="Le message ne peut pas être vide.")

    async def event_gen():
        try:
            async for chunk in _stream_pipeline(
                query=request.message, history=request.history,
                expand=request.expand if request.expand is not None else True,
                system=request.system,
                lat=request.lat, lon=request.lon,
                pending_tool_uses=request.pending_tool_uses,
                tool_results=request.tool_results,
            ):
                yield chunk
        except Exception as e:
            logging.error(f"Erreur streaming: {e}")
            yield f'data: {json.dumps({"type": "error", "detail": str(e)})}\n\n'

    return StreamingResponse(event_gen(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no",
                                      "Connection": "keep-alive"})

# ─── Stats ────────────────────────────────────────────────────────────────────

@app.get("/v1/stats", response_model=StatsResponse)
async def stats():
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    from collections import Counter
    all_payloads = []
    offset = None
    while True:
        results, offset = qdrant_client.scroll(
            collection_name=QDRANT_COLLECTION,
            limit=500,
            with_payload=["category", "source"],
            offset=offset
        )
        all_payloads.extend([hit.payload for hit in results])
        if offset is None:
            break
    cats = dict(Counter(p.get('category', '?') for p in all_payloads))
    srcs = dict(Counter(p.get('source', '?') for p in all_payloads).most_common(20))
    return StatsResponse(total_chunks=len(all_payloads), categories=cats, sources=srcs)

# ─── Annuaire ─────────────────────────────────────────────────────────────────

def _annuaire_filter(categorie: str = None, sous_categorie: str = None,
                     quartier: str = None, ville: str = None) -> Filter:
    """Construit un filtre Qdrant limité aux entrées annuaire avec filtres optionnels."""
    conditions = [FieldCondition(key="type", match=MatchValue(value="annuaire"))]
    if categorie:
        conditions.append(FieldCondition(key="categorie", match=MatchValue(value=categorie)))
    if sous_categorie:
        conditions.append(FieldCondition(key="sous_categorie", match=MatchValue(value=sous_categorie)))
    if quartier:
        conditions.append(FieldCondition(key="quartier", match=MatchValue(value=quartier)))
    if ville:
        conditions.append(FieldCondition(key="ville_region", match=MatchValue(value=ville)))
    return Filter(must=conditions)


@app.get("/v1/annuaire/categories")
async def annuaire_categories():
    """Retourne les catégories, sous-catégories, quartiers et villes disponibles avec comptages."""
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    loop = asyncio.get_event_loop()
    def _fetch():
        cats: dict = {}
        villes: dict = {}
        quartiers: dict = {}
        offset = None
        ann_filter = Filter(must=[FieldCondition(key="type", match=MatchValue(value="annuaire"))])
        while True:
            hits, offset = qdrant_client.scroll(
                collection_name=QDRANT_COLLECTION,
                scroll_filter=ann_filter,
                limit=500,
                with_payload=["categorie", "sous_categorie", "quartier", "ville_region"],
                offset=offset
            )
            for h in hits:
                p = h.payload
                cat  = p.get("categorie", "")
                scat = p.get("sous_categorie", "")
                q    = p.get("quartier", "")
                v    = p.get("ville_region", "")
                if cat:
                    cats.setdefault(cat, {}).setdefault(scat, 0)
                    cats[cat][scat] += 1
                if q:
                    quartiers[q] = quartiers.get(q, 0) + 1
                if v:
                    villes[v] = villes.get(v, 0) + 1
            if offset is None:
                break
        return cats, quartiers, villes
    cats, quartiers, villes = await loop.run_in_executor(None, _fetch)
    tree = [
        {"categorie": c,
         "total": sum(sc.values()),
         "sous_categories": [{"nom": sc, "count": n} for sc, n in sorted(scs.items(), key=lambda x: -x[1])]}
        for c, scs in sorted(cats.items(), key=lambda x: -sum(x[1].values()))
    ]
    return {
        "categories": tree,
        "quartiers":  [{"nom": q, "count": n} for q, n in sorted(quartiers.items(), key=lambda x: -x[1])],
        "villes":     [{"nom": v, "count": n} for v, n in sorted(villes.items(),   key=lambda x: -x[1])],
    }


@app.get("/v1/annuaire/browse")
async def annuaire_browse(
    categorie:      Optional[str] = None,
    sous_categorie: Optional[str] = None,
    quartier:       Optional[str] = None,
    ville:          Optional[str] = None,
    limit:          int = 50,
    offset:         int = 0,
):
    """Navigation paginée sans recherche sémantique — filtrage pur par métadonnées."""
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    loop = asyncio.get_event_loop()
    f = _annuaire_filter(categorie, sous_categorie, quartier, ville)
    def _fetch():
        hits, _ = qdrant_client.scroll(
            collection_name=QDRANT_COLLECTION,
            scroll_filter=f,
            limit=limit,
            offset=offset,
            with_payload=True
        )
        return hits
    hits = await loop.run_in_executor(None, _fetch)
    services = [
        _chunk_to_service(
            hit.payload.get("original_id", str(hit.id)),
            hit.payload.get("document", ""),
            {k: v for k, v in hit.payload.items() if k != "document"},
            is_favorite=(hit.payload.get("original_id", str(hit.id)) in _favorites)
        )
        for hit in hits
    ]
    return {"services": services, "count": len(services)}


@app.get("/v1/annuaire/services")
async def annuaire_search(
    q:              str,
    categorie:      Optional[str] = None,
    sous_categorie: Optional[str] = None,
    quartier:       Optional[str] = None,
    ville:          Optional[str] = None,
    category:       Optional[str] = None,   # ancien paramètre — rétrocompat
):
    if not jina_api_key or not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    loop = asyncio.get_event_loop()
    emb = await loop.run_in_executor(None, lambda: _jina_embed_batch([q])[0][0])
    # Toujours filtrer sur type=annuaire — évite que les docs juridiques dominent
    ann_filter = _annuaire_filter(categorie, sous_categorie, quartier, ville)
    chunks = await loop.run_in_executor(None, lambda: _search_with_embedding(emb, 25, query_filter=ann_filter))
    services = [
        _chunk_to_service(
            c['metadata'].get('original_id', c['id']),   # original_id stable pour le détail
            c['document'], c['metadata'],
            is_favorite=(c['metadata'].get('original_id', c['id']) in _favorites)
        )
        for c in chunks
        if c['distance'] <= 1.4   # seuil élargi — annuaire déjà filtré par type
    ]
    return {"services": services}

@app.get("/v1/annuaire/services/nearby")
async def annuaire_nearby(lat: float, lng: float, radius: int = 5,
                          categorie: Optional[str] = None):
    """Scroller TOUTES les entrées annuaire géolocalisées et filtrer par distance.
    Pas de recherche sémantique — retourne ce qui est réellement proche."""
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    loop = asyncio.get_event_loop()
    def _fetch_nearby():
        ann_filter = _annuaire_filter(categorie=categorie)
        services = []
        offset = None
        while True:
            hits, offset = qdrant_client.scroll(
                collection_name=QDRANT_COLLECTION,
                scroll_filter=ann_filter,
                limit=500,
                with_payload=True,
                offset=offset,
            )
            for hit in hits:
                p = hit.payload
                svc_lat = p.get('latitude')
                svc_lng = p.get('longitude')
                if svc_lat is None or svc_lng is None:
                    continue
                dist = _haversine_km(lat, lng, float(svc_lat), float(svc_lng))
                if dist <= radius:
                    oid = p.get('original_id', str(hit.id))
                    svc = _chunk_to_service(
                        oid, p.get('document', ''),
                        {k: v for k, v in p.items() if k != 'document'},
                        ref_lat=lat, ref_lng=lng,
                        is_favorite=(oid in _favorites)
                    )
                    services.append(svc)
            if offset is None:
                break
        services.sort(key=lambda s: s['distanceKm'] or 999)
        return services
    services = await loop.run_in_executor(None, _fetch_nearby)
    return {"services": services}

@app.get("/v1/annuaire/services/{service_id}")
async def annuaire_service_detail(service_id: str):
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    try:
        hits, _ = qdrant_client.scroll(
            collection_name=QDRANT_COLLECTION,
            scroll_filter=Filter(must=[FieldCondition(key="original_id", match=MatchValue(value=service_id))]),
            limit=1,
            with_payload=True
        )
        if not hits:
            raise HTTPException(status_code=404, detail="Service non trouvé")
        hit = hits[0]
        doc = hit.payload.get('document', '')
        meta = {k: v for k, v in hit.payload.items() if k != 'document'}
        return {"service": _chunk_to_service(service_id, doc, meta, is_favorite=(service_id in _favorites))}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Service non trouvé : {e}")

@app.get("/v1/annuaire/favorites")
async def annuaire_get_favorites():
    if not qdrant_client:
        raise HTTPException(status_code=503, detail="Base non chargée")
    if not _favorites:
        return {"services": []}
    try:
        hits, _ = qdrant_client.scroll(
            collection_name=QDRANT_COLLECTION,
            scroll_filter=Filter(must=[FieldCondition(key="original_id",
                                                       match=MatchAny(any=list(_favorites)))]),
            limit=len(_favorites) + 10,
            with_payload=True
        )
        return {"services": [
            _chunk_to_service(
                hit.payload.get('original_id', str(hit.id)),
                hit.payload.get('document', ''),
                {k: v for k, v in hit.payload.items() if k != 'document'},
                is_favorite=True
            )
            for hit in hits
        ]}
    except Exception:
        return {"services": []}

@app.post("/v1/annuaire/favorites/{service_id}")
async def annuaire_add_favorite(service_id: str):
    _favorites.add(service_id)
    return {"ok": True}

@app.delete("/v1/annuaire/favorites/{service_id}")
async def annuaire_remove_favorite(service_id: str):
    _favorites.discard(service_id)
    return {"ok": True}

# ══════════════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s | %(message)s')
    print("=" * 65)
    print("  AMIIN API SERVER v2.2  (streaming SSE activé)")
    print(f"  Adresse : http://{HOST}:{PORT}")
    print("=" * 65)
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
