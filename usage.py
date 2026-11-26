# -*- coding: utf-8 -*-
"""
usage.py — Mesure de l'usage et quota quotidien d'Amiin.

Chaque appel payant (modèle de langage, embeddings, reconnaissance et synthèse
vocales) est converti en COÛT RÉEL (micro-dollars) à partir de l'usage renvoyé
par le fournisseur, puis inscrit dans la table `usage_events`. Le quota est
une enveloppe quotidienne en dollars, commune au chat et à la voix, remise à
zéro à minuit heure de Djibouti.

Une grande question, un long historique, une tâche en plusieurs passes ou une
réponse en somali (Sonnet) coûtent plus cher et consomment donc plus : rien à
pondérer à la main, c'est le vrai tarif qui décide.

Variables d'environnement :
  QUOTA_DAILY_USD           enveloppe gratuite par jour (défaut 0.10)
  QUOTA_ENFORCE             "0" : mesure seulement, ne bloque personne (défaut "1")
  STT_USD_PER_HOUR          tarif reconnaissance vocale (défaut 0.111, Groq whisper-large-v3)
  STT_MIN_SECONDS           durée minimale facturée par requête (défaut 10)
  TTS_USD_PER_MILLION_CHARS tarif retenu pour la synthèse vocale (défaut 4.0 — Edge TTS
                            est gratuit ; tarif volontairement modéré pour que l'oral
                            consomme un peu plus que l'écrit sans pénaliser la voix)
  JINA_USD_PER_MILLION      tarif embeddings (défaut 0.05)
"""

import logging
import os
import threading
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import HTTPException

from auth import _get_conn, is_admin

# ── Tarifs (dollars par million de tokens) ────────────────────────────────────
# Lecture du cache : 0,1 × l'entrée ; écriture (cache 5 min) : 1,25 × l'entrée.
MODEL_PRICES = {
    "claude-haiku-4-5": {"input": 1.00, "output": 5.00},
    "claude-sonnet-5":  {"input": 2.00, "output": 10.00},
    "claude-haiku-5-5": {"input": 0.10, "output": 0.50},
    "claude-sonnet-5-5": {"input": 2.00, "output": 10.00},
}
_FALLBACK_PRICE = {"input": 2.00, "output": 10.00}   # modèle inconnu : tarif prudent
CACHE_READ_RATIO  = 0.10
CACHE_WRITE_RATIO = 1.25

DJIBOUTI_TZ = timezone(timedelta(hours=3))           # UTC+3, sans heure d'été


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return default


def daily_quota_usd() -> float:
    return _env_float("QUOTA_DAILY_USD", 0.10)


def quota_enforced() -> bool:
    return os.environ.get("QUOTA_ENFORCE", "1").strip().lower() not in ("0", "false", "off", "non")


def _model_price(model: str) -> dict:
    # Préfixe le plus long d'abord : « claude-sonnet-5-5 » avant « claude-sonnet-5 »
    for prefix, price in sorted(MODEL_PRICES.items(), key=lambda kv: -len(kv[0])):
        if model == prefix or model.startswith(prefix + "-"):
            return price
    logging.warning("Tarif inconnu pour le modèle %s : tarif prudent appliqué", model)
    return _FALLBACK_PRICE


# ── Compteur d'une requête ────────────────────────────────────────────────────

class UsageMeter:
    """Cumule le coût de tous les appels déclenchés par UNE requête (réponse
    principale, reformulation, embeddings…). Sûr entre threads : la
    reformulation et la recherche tournent en parallèle."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.cost_usd = 0.0
        self.input_tokens = 0
        self.output_tokens = 0
        self.cache_read_tokens = 0
        self.cache_write_tokens = 0
        self.jina_tokens = 0
        self.audio_seconds = 0.0
        self.tts_chars = 0
        self.models: set = set()
        self.estimated = False

    def add_claude(self, model: str, usage) -> None:
        if usage is None:
            return
        p = _model_price(model)
        inp = getattr(usage, "input_tokens", 0) or 0
        out = getattr(usage, "output_tokens", 0) or 0
        cr = getattr(usage, "cache_read_input_tokens", 0) or 0
        cw = getattr(usage, "cache_creation_input_tokens", 0) or 0
        cost = (inp * p["input"] + out * p["output"]
                + cr * p["input"] * CACHE_READ_RATIO
                + cw * p["input"] * CACHE_WRITE_RATIO) / 1_000_000
        with self._lock:
            self.cost_usd += cost
            self.input_tokens += inp
            self.output_tokens += out
            self.cache_read_tokens += cr
            self.cache_write_tokens += cw
            self.models.add(model)

    def add_claude_estimate(self, model: str, prompt_chars: int, output_chars: int) -> None:
        """Réponse interrompue (l'utilisateur a arrêté, réseau coupé) : l'usage
        exact n'est pas connu mais les tokens ont été facturés. Estimation
        prudente : ~4 caractères par token, contexte compté plein tarif."""
        p = _model_price(model)
        inp, out = prompt_chars // 4, output_chars // 4
        with self._lock:
            self.cost_usd += (inp * p["input"] + out * p["output"]) / 1_000_000
            self.input_tokens += inp
            self.output_tokens += out
            self.models.add(model)
            self.estimated = True

    def add_jina(self, tokens: int) -> None:
        with self._lock:
            self.jina_tokens += tokens or 0
            self.cost_usd += (tokens or 0) * _env_float("JINA_USD_PER_MILLION", 0.05) / 1_000_000

    def add_stt(self, seconds: float) -> None:
        billed = max(seconds or 0.0, _env_float("STT_MIN_SECONDS", 10))
        with self._lock:
            self.audio_seconds += billed
            self.cost_usd += billed * _env_float("STT_USD_PER_HOUR", 0.111) / 3600

    def add_tts(self, chars: int) -> None:
        with self._lock:
            self.tts_chars += chars or 0
            self.cost_usd += (chars or 0) * _env_float("TTS_USD_PER_MILLION_CHARS", 4.0) / 1_000_000


# ── Base de données ───────────────────────────────────────────────────────────

def ensure_usage_schema() -> None:
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS usage_events (
                    id                 BIGSERIAL PRIMARY KEY,
                    user_id            TEXT NOT NULL,
                    at                 TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    kind               TEXT NOT NULL,
                    cost_micro_usd     BIGINT NOT NULL,
                    models             TEXT NOT NULL DEFAULT '',
                    input_tokens       INTEGER NOT NULL DEFAULT 0,
                    output_tokens      INTEGER NOT NULL DEFAULT 0,
                    cache_read_tokens  INTEGER NOT NULL DEFAULT 0,
                    cache_write_tokens INTEGER NOT NULL DEFAULT 0,
                    jina_tokens        INTEGER NOT NULL DEFAULT 0,
                    audio_seconds      REAL NOT NULL DEFAULT 0,
                    tts_chars          INTEGER NOT NULL DEFAULT 0,
                    estimated          BOOLEAN NOT NULL DEFAULT FALSE
                )""")
            cur.execute("CREATE INDEX IF NOT EXISTS usage_events_user_at "
                        "ON usage_events (user_id, at)")


def record(user_id: str, kind: str, meter: UsageMeter) -> None:
    """Inscrit le coût d'une requête. Ne lève jamais : un échec d'écriture ne
    doit pas casser la réponse déjà servie (il est journalisé)."""
    if meter.cost_usd <= 0 and not meter.models:
        return
    try:
        with _get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO usage_events
                       (user_id, kind, cost_micro_usd, models, input_tokens, output_tokens,
                        cache_read_tokens, cache_write_tokens, jina_tokens, audio_seconds,
                        tts_chars, estimated)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                    (user_id, kind, round(meter.cost_usd * 1_000_000),
                     ",".join(sorted(meter.models)), meter.input_tokens, meter.output_tokens,
                     meter.cache_read_tokens, meter.cache_write_tokens, meter.jina_tokens,
                     meter.audio_seconds, meter.tts_chars, meter.estimated),
                )
    except Exception:
        logging.exception("Enregistrement de l'usage impossible (%s, %s)", user_id, kind)


def day_window(now: Optional[datetime] = None) -> tuple:
    """(début du jour, prochaine remise à zéro) en heure de Djibouti, exprimés en UTC."""
    local = (now or datetime.now(timezone.utc)).astimezone(DJIBOUTI_TZ)
    start = local.replace(hour=0, minute=0, second=0, microsecond=0)
    return start.astimezone(timezone.utc), (start + timedelta(days=1)).astimezone(timezone.utc)


def used_today_usd(user_id: str) -> float:
    start, _ = day_window()
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT COALESCE(SUM(cost_micro_usd), 0) AS s FROM usage_events "
                        "WHERE user_id = %s AND at >= %s", (user_id, start))
            # SUM(BIGINT) revient en Decimal : converti pour les calculs en float
            return float(cur.fetchone()["s"]) / 1_000_000


def summary(user: dict) -> dict:
    """État du quota du jour, pour la jauge de l'app."""
    _, reset = day_window()
    used = used_today_usd(user["sub"])
    limit = daily_quota_usd()
    unlimited = is_admin(user) or not quota_enforced()
    percent = 0.0 if limit <= 0 else min(100.0, used / limit * 100)
    return {
        "used_usd": round(used, 6),
        "limit_usd": limit,
        "percent": round(percent, 1),
        "exhausted": (not unlimited) and used >= limit,
        "unlimited": unlimited,
        "resets_at": reset.isoformat(),
    }


QUOTA_EXCEEDED_DETAIL = ("Limite d'utilisation du jour atteinte. Elle se recharge à minuit "
                         "(heure de Djibouti).")


def ensure_quota(user: dict, grace: float = 0.0) -> None:
    """402 si l'enveloppe du jour est épuisée. Admins et mode mesure seule :
    jamais bloqués. [grace] : marge tolérée (ex. 0.25 = +25 %), pour lire à
    voix haute la réponse qui vient de faire franchir le seuil.
    Base injoignable : on laisse passer (le coût sera tout de même enregistré)."""
    if is_admin(user) or not quota_enforced():
        return
    try:
        used = used_today_usd(user["sub"])
    except Exception:
        logging.exception("Lecture du quota impossible")
        return
    if used >= daily_quota_usd() * (1 + grace):
        raise HTTPException(status_code=402, detail=QUOTA_EXCEEDED_DETAIL,
                            headers={"X-Amiin-Error": "quota_exceeded"})
