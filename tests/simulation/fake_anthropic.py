# -*- coding: utf-8 -*-
"""
Faux serveur de l'API Anthropic (POST /v1/messages, normal et streaming SSE)
pour simuler Amiin sans clé ni coût.

Ce qui est réaliste :
  - le format exact des réponses (le SDK `anthropic` du serveur les lit tel quel) ;
  - la CONSOMMATION : les tokens d'entrée sont comptés à partir de la taille
    réelle de la requête envoyée par Amiin (instructions, catalogue des
    démarches, historique, résultats d'outils), ~4 caractères par token ;
  - le cache de prompt : préfixe (outils + blocs système marqués
    cache_control) lu depuis le cache s'il a été écrit il y a moins de 5 min,
    écrit sinon ; pas de cache sous le minimum du modèle ;
  - les appels d'outils (créer une note, lire les notes, suivre une démarche,
    détail d'une démarche), donc les tâches en plusieurs passes.

Chaque appel est journalisé (JSONL) pour comparer avec la table usage_events.
Lancement : python fake_anthropic.py --port 8765 --log calls.jsonl
"""

import argparse
import hashlib
import json
import random
import re
import time
import uuid

import uvicorn
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

CHARS_PER_TOKEN = 4.0
CACHE_TTL_S = 300
# Minimums de mise en cache (documentation Anthropic) ; Haiku 5.5 : nouveau
# tokeniseur, ~30 % de tokens en plus pour le même texte.
MIN_CACHEABLE = {"claude-haiku-4-5": 4096, "claude-haiku-5-5": 512, "claude-sonnet-5": 1024}
TOKENIZER_FACTOR = {"claude-haiku-5-5": 1.3}

app = FastAPI()
_cache_seen: dict = {}
LOG_PATH = "calls.jsonl"


_FACTOR = [1.0]   # facteur du modèle de la requête en cours


def _tokens(obj) -> int:
    text = obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)
    return max(1, round(len(text) / CHARS_PER_TOKEN * _FACTOR[0]))


def _min_cache(model: str) -> int:
    for k, v in MIN_CACHEABLE.items():
        if model.startswith(k):
            return v
    return 1024


def _usage_for(body: dict) -> dict:
    """Tokens d'entrée répartis entre cache (lu/écrit) et entrée normale."""
    model = body.get("model", "")
    tools = body.get("tools") or []
    system = body.get("system") or []
    if isinstance(system, str):
        system = [{"type": "text", "text": system}]
    messages = body.get("messages") or []

    # Préfixe cachable : outils + blocs système jusqu'au dernier cache_control
    last = max((i for i, b in enumerate(system) if b.get("cache_control")), default=-1)
    prefix_parts = [tools] + system[: last + 1]
    rest_parts = system[last + 1:] + [messages]
    prefix_tokens = sum(_tokens(p) for p in prefix_parts) if last >= 0 else 0
    rest_tokens = sum(_tokens(p) for p in rest_parts) + (0 if last >= 0 else _tokens(tools))

    cache_read = cache_write = 0
    if prefix_tokens >= _min_cache(model):
        key = hashlib.sha256((model + json.dumps(prefix_parts, ensure_ascii=False)).encode()).hexdigest()
        seen = _cache_seen.get(key)
        if seen and time.time() - seen < CACHE_TTL_S:
            cache_read = prefix_tokens
        else:
            cache_write = prefix_tokens
        _cache_seen[key] = time.time()
    else:
        rest_tokens += prefix_tokens
    return {"input_tokens": rest_tokens, "cache_creation_input_tokens": cache_write,
            "cache_read_input_tokens": cache_read}


# ── Réponses simulées ─────────────────────────────────────────────────────────

_INFO_EN = [
    "In Djibouti, this procedure is handled by the relevant office. Bring your identity "
    "card and a recent proof of address. It usually takes a few working days. Ask for a "
    "receipt when you submit the file: it proves your application until the final "
    "document is ready. Fees are paid on site in Djibouti francs.",
    "Djibouti's Labour Code sets the legal working week at 40 hours. Overtime is paid at "
    "a higher rate set by law and collective agreements. In a dispute, the labour "
    "inspectorate can be contacted before going to the labour court.",
]

_INFO = [
    "À Djibouti, cette démarche se fait auprès du service concerné, muni de votre "
    "carte d'identité et d'un justificatif de domicile récent. Comptez en général "
    "quelques jours ouvrables. Pensez à demander un récépissé lors du dépôt : il vous "
    "servira de preuve en attendant le document définitif. Les frais sont à régler "
    "sur place, en francs Djibouti, et un reçu vous est remis.",
    "Le Code du travail djiboutien prévoit une durée légale de 40 heures par semaine. "
    "Les heures supplémentaires donnent droit à une majoration fixée par la loi et "
    "par les conventions collectives. En cas de litige, l'inspection du travail peut "
    "être saisie avant tout recours devant le tribunal du travail.",
    "Pour créer une SARL, il faut rédiger les statuts, déposer le capital social, puis "
    "immatriculer la société au registre du commerce. Le guichet unique de l'ANPI "
    "centralise la plupart des formalités, ce qui réduit nettement les délais.",
]


def _last_user(messages) -> tuple:
    """(texte du dernier message utilisateur, contient des résultats d'outils ?)"""
    for m in reversed(messages):
        if m.get("role") != "user":
            continue
        c = m.get("content")
        if isinstance(c, str):
            return c, False
        texts, has_tool = [], False
        for b in c or []:
            if b.get("type") == "tool_result":
                has_tool = True
            elif b.get("type") == "text":
                texts.append(b.get("text", ""))
        return " ".join(texts), has_tool
    return "", False


def _plan(body: dict) -> tuple:
    """Retourne (texte, [blocs tool_use], stop_reason)."""
    messages = body.get("messages") or []
    text, has_tool_result = _last_user(messages)
    t = text.lower()
    system_text = json.dumps(body.get("system") or "", ensure_ascii=False)
    english = "ONLY in English" in system_text
    info = _INFO_EN if english else _INFO

    if not body.get("tools"):                    # reformulation de la question
        return json.dumps({"v1": text[:80] + " ?", "v2": "démarche " + text[:60],
                           "v3": "procédure Djibouti " + text[:50]}, ensure_ascii=False), [], "end_turn"
    if has_tool_result:                          # 2e passe : réponse avec les résultats
        if english:
            return ("Based on your information, here is what I found. " + random.choice(info)[:260]
                    + " Would you like help with the next step?"), [], "end_turn"
        return ("D'après vos informations, voici ce que je trouve. " + random.choice(info)[:260]
                + " Souhaitez-vous que je vous aide pour la suite ?"), [], "end_turn"

    def tool(name, inp, intro):
        return intro, [{"type": "tool_use", "id": "toolu_" + uuid.uuid4().hex[:20],
                        "name": name, "input": inp}], "tool_use"

    if (re.search(r"(note|retiens|rappelle-toi)", t) and re.search(r"(crée|créer|prends|ajoute|retiens|note que|create|take a note|write down)", t)):
        title = re.sub(r"^.*?:\s*", "", text)[:60] or "Note"
        return tool("create_note", {"title": title, "content": text}, "Je crée cette note pour vous.")
    if "mes notes" in t or "my notes" in t:
        return tool("get_notes", {}, "Je regarde vos notes.")
    m = re.search(r"egouv_(\d+)", t)
    if m and re.search(r"(suivre|commence|démarre|ajoute|follow|start|add)", t):
        return tool("start_demarche", {"demarche_id": f"egouv_{m.group(1)}"},
                    "J'ajoute cette démarche à votre suivi.")
    if ("passeport" in t or "passport" in t) and re.search(r"(détail|documents|pièces|detail)", t):
        return tool("get_demarche_detail", {"demarche_id": "egouv_103"},
                    "Je consulte la fiche détaillée.")
    if len(t) < 25:
        return ("Hello! I'm Amiin. How can I help you today?" if english else
                "Bonjour ! Je suis Amiin. Comment puis-je vous aider aujourd'hui ?"), [], "end_turn"
    return random.choice(info), [], "end_turn"


def _log(entry: dict) -> None:
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


@app.post("/v1/messages")
async def messages(request: Request):
    body = await request.json()
    model = body.get("model", "")
    # Règles de l'API pour Haiku 5.5 (doc de migration) : on les fait respecter
    if model.startswith("claude-haiku-5"):
        bad = [k for k in ("temperature", "top_p", "top_k") if k in body]
        th = body.get("thinking") or {}
        if bad or th.get("type") == "enabled" or "budget_tokens" in th:
            return JSONResponse(status_code=400, content={"type": "error", "error": {
                "type": "invalid_request_error",
                "message": f"claude-haiku-5-5: paramètres refusés {bad or ['budget_tokens']}"}})
    _FACTOR[0] = next((f for k, f in TOKENIZER_FACTOR.items() if model.startswith(k)), 1.0)
    usage = _usage_for(body)
    text, tools, stop = _plan(body)
    out_tokens = _tokens(text) + sum(_tokens(b["input"]) + 10 for b in tools)
    _log({"ts": time.time(), "model": model, "stream": bool(body.get("stream")),
          "tools": [b["name"] for b in tools], "output_tokens": out_tokens, **usage})
    msg_id = "msg_" + uuid.uuid4().hex[:24]

    if not body.get("stream"):
        content = ([{"type": "text", "text": text}] if text else []) + tools
        return JSONResponse({"id": msg_id, "type": "message", "role": "assistant", "model": model,
                             "content": content, "stop_reason": stop, "stop_sequence": None,
                             "usage": {**usage, "output_tokens": out_tokens}})

    def sse(event, data):
        return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"

    async def gen():
        yield sse("message_start", {"type": "message_start", "message": {
            "id": msg_id, "type": "message", "role": "assistant", "model": model, "content": [],
            "stop_reason": None, "stop_sequence": None, "usage": {**usage, "output_tokens": 1}}})
        idx = 0
        if text:
            yield sse("content_block_start", {"type": "content_block_start", "index": idx,
                                              "content_block": {"type": "text", "text": ""}})
            for piece in re.findall(r"\S+\s*", text):
                yield sse("content_block_delta", {"type": "content_block_delta", "index": idx,
                                                  "delta": {"type": "text_delta", "text": piece}})
            yield sse("content_block_stop", {"type": "content_block_stop", "index": idx})
            idx += 1
        for b in tools:
            yield sse("content_block_start", {"type": "content_block_start", "index": idx,
                                              "content_block": {**b, "input": {}}})
            yield sse("content_block_delta", {"type": "content_block_delta", "index": idx,
                                              "delta": {"type": "input_json_delta",
                                                        "partial_json": json.dumps(b["input"], ensure_ascii=False)}})
            yield sse("content_block_stop", {"type": "content_block_stop", "index": idx})
            idx += 1
        yield sse("message_delta", {"type": "message_delta",
                                    "delta": {"stop_reason": stop, "stop_sequence": None},
                                    "usage": {"output_tokens": out_tokens}})
        yield sse("message_stop", {"type": "message_stop"})

    return StreamingResponse(gen(), media_type="text/event-stream")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--log", default="calls.jsonl")
    a = ap.parse_args()
    LOG_PATH = a.log
    random.seed(42)
    uvicorn.run(app, host="127.0.0.1", port=a.port, log_level="warning")
