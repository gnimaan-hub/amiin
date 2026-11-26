# -*- coding: utf-8 -*-
"""Quota quotidien : calcul du coût réel, journée de Djibouti, blocage."""

import asyncio
import os
import uuid
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

import usage

DB_URL = os.environ.get("TEST_DATABASE_URL")
needs_db = pytest.mark.skipif(not DB_URL, reason="TEST_DATABASE_URL non définie")


def _u(inp=0, out=0, cr=0, cw=0):
    return SimpleNamespace(input_tokens=inp, output_tokens=out,
                           cache_read_input_tokens=cr, cache_creation_input_tokens=cw)


# ── Coût ──────────────────────────────────────────────────────────────────────

def test_cout_haiku_avec_cache():
    m = usage.UsageMeter()
    # 1000 entrée (1 $/M) + 500 sortie (5 $/M) + 2000 lus en cache (0,1 $/M) + 1000 écrits (1,25 $/M)
    m.add_claude("claude-haiku-4-5-20251001", _u(1000, 500, 2000, 1000))
    assert m.cost_usd == pytest.approx((1000 * 1 + 500 * 5 + 2000 * 0.1 + 1000 * 1.25) / 1e6)


def test_somali_sonnet_coute_le_double():
    h, s = usage.UsageMeter(), usage.UsageMeter()
    h.add_claude("claude-haiku-4-5-20251001", _u(3000, 400))
    s.add_claude("claude-sonnet-5", _u(3000, 400))
    assert s.cost_usd == pytest.approx(2 * h.cost_usd)


def test_plusieurs_passes_et_historique_s_additionnent():
    court, long_ = usage.UsageMeter(), usage.UsageMeter()
    court.add_claude("claude-haiku-4-5", _u(1000, 200))
    for _ in range(3):                         # tâche en 3 passes, historique plus long
        long_.add_claude("claude-haiku-4-5", _u(4000, 300))
    assert long_.cost_usd > 5 * court.cost_usd


def test_prefixe_de_modele_le_plus_long():
    assert usage._model_price("claude-sonnet-5-5")["input"] == 2.00
    assert usage._model_price("claude-haiku-5-5")["input"] == 0.10
    assert usage._model_price("claude-haiku-4-5-20251001")["input"] == 1.00
    assert usage._model_price("modele-inconnu") == usage._FALLBACK_PRICE


def test_voix(monkeypatch):
    monkeypatch.delenv("STT_USD_PER_HOUR", raising=False)
    monkeypatch.delenv("TTS_USD_PER_MILLION_CHARS", raising=False)
    m = usage.UsageMeter()
    m.add_stt(3)                                # minimum facturé : 10 s
    assert m.audio_seconds == 10
    assert m.cost_usd == pytest.approx(10 * 0.111 / 3600)
    t = usage.UsageMeter()
    t.add_tts(500)
    assert t.cost_usd == pytest.approx(500 * 4.0 / 1e6)


def test_estimation_si_reponse_interrompue():
    m = usage.UsageMeter()
    m.add_claude_estimate("claude-haiku-4-5", prompt_chars=8000, output_chars=400)
    assert m.estimated and m.input_tokens == 2000 and m.output_tokens == 100
    assert m.cost_usd == pytest.approx((2000 * 1 + 100 * 5) / 1e6)


def test_journee_de_djibouti():
    # 26/11 22:30 UTC = 27/11 01:30 à Djibouti : la journée a commencé le 26 à 21:00 UTC
    start, reset = usage.day_window(datetime(2026, 11, 26, 22, 30, tzinfo=timezone.utc))
    assert start == datetime(2026, 11, 26, 21, 0, tzinfo=timezone.utc)
    assert reset == datetime(2026, 11, 27, 21, 0, tzinfo=timezone.utc)


# ── Pipeline streaming : réponse complète et réponse interrompue ─────────────

class _FakeStream:
    def __init__(self, chunks, usage_):
        self._chunks, self._usage = chunks, usage_

    async def __aenter__(self):
        return self

    async def __aexit__(self, *a):
        return False

    @property
    def text_stream(self):
        async def gen():
            for c in self._chunks:
                yield c
        return gen()

    async def get_final_message(self):
        return SimpleNamespace(usage=self._usage, content=[], stop_reason="end_turn")


def _fake_claude(monkeypatch, api, chunks, usage_):
    fake = SimpleNamespace(messages=SimpleNamespace(stream=lambda **kw: _FakeStream(chunks, usage_)))
    monkeypatch.setattr(api, "async_claude", fake)
    monkeypatch.setattr(api, "_log_request", lambda *a, **k: None)


def test_stream_complet_compte_l_usage_exact(api, monkeypatch):
    _fake_claude(monkeypatch, api, ["Bon", "jour"], _u(1200, 30, 4000, 0))
    meter = usage.UsageMeter()

    async def run():
        return [c async for c in api._stream_pipeline("bonjour", meter=meter)]
    asyncio.run(run())
    assert not meter.estimated
    assert meter.input_tokens == 1200 and meter.cache_read_tokens == 4000


def test_stream_interrompu_est_estime(api, monkeypatch):
    _fake_claude(monkeypatch, api, ["Bon", "jour", " à", " vous"], _u(1200, 30))
    meter = usage.UsageMeter()

    async def run():
        gen = api._stream_pipeline("bonjour", meter=meter)
        async for chunk in gen:
            if '"token"' in chunk:
                break                           # l'utilisateur arrête la réponse
        await gen.aclose()
    asyncio.run(run())
    assert meter.estimated and meter.cost_usd > 0


# ── Base de données : enveloppe du jour et blocage ───────────────────────────

@pytest.fixture
def db(api, monkeypatch):
    import auth
    from test_auth_db import _BASE_SCHEMA
    monkeypatch.setattr(auth, "DATABASE_URL", DB_URL)
    monkeypatch.setenv("EMAIL_VERIFICATION", "off")
    monkeypatch.setenv("QUOTA_DAILY_USD", "0.10")
    monkeypatch.delenv("QUOTA_ENFORCE", raising=False)
    monkeypatch.setenv("ADMIN_EMAILS", "")
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(_BASE_SCHEMA)
            cur.execute("DELETE FROM users WHERE email LIKE '%%@quota.test'")
    auth.ensure_auth_schema()
    usage.ensure_usage_schema()
    auth._status_cache.clear()
    from fastapi.testclient import TestClient
    client = TestClient(api.app)
    email = f"q{uuid.uuid4().hex[:8]}@quota.test"
    r = client.post("/v1/auth/register", json={"email": email, "password": "motdepasse123"})
    assert r.status_code == 201, r.text
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    uid = client.get("/v1/auth/me", headers=h).json()["id"]
    return auth, client, h, uid, email


def _spend(auth, uid, usd, at=None):
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO usage_events (user_id, kind, cost_micro_usd, at) "
                        "VALUES (%s, 'chat', %s, COALESCE(%s, NOW()))",
                        (uid, round(usd * 1e6), at))


@needs_db
def test_jauge_et_blocage(db):
    auth, client, h, uid, _ = db
    assert client.get("/v1/me/usage", headers=h).json()["percent"] == 0
    _spend(auth, uid, 0.06)
    state = client.get("/v1/me/usage", headers=h).json()
    assert state["percent"] == 60 and not state["exhausted"]
    # Sous la limite : la dépendance laisse passer (422 = validation du corps vide)
    assert client.post("/v1/chat", json={}, headers=h).status_code == 422

    _spend(auth, uid, 0.05)
    state = client.get("/v1/me/usage", headers=h).json()
    assert state["exhausted"] and state["percent"] == 100
    r = client.post("/v1/chat", json={"message": "Bonjour"}, headers=h)
    assert r.status_code == 402 and r.headers["x-amiin-error"] == "quota_exceeded"
    assert client.post("/v1/chat/stream", json={"message": "Bonjour"}, headers=h).status_code == 402
    assert client.post("/v1/stt", headers=h).status_code == 402
    # Lecture à voix haute : marge de 25 % (0,11 $ < 0,125 $)
    assert client.post("/v1/tts", json={}, headers=h).status_code == 422
    # Passe de suivi d'une tâche commencée (résultats d'outils) : marge de 50 %
    suite = {"message": "Quelles sont mes notes ?", "pending_tool_uses": [
        {"id": "t1", "name": "get_notes", "input": {}}],
        "tool_results": [{"tool_use_id": "t1", "content": "[]"}]}
    assert usage.used_today_usd({"sub": uid}) < 0.15
    # 0,11 $ < 0,15 $ : la passe de suivi passe (le pipeline, sans modèle ici, échoue ensuite)
    assert client.post("/v1/chat", json=suite, headers=h).status_code != 402
    _spend(auth, uid, 0.05)                      # 0,16 $ : au-delà de la marge
    assert client.post("/v1/chat/stream", json=suite, headers=h).status_code == 402


@needs_db
def test_hier_ne_compte_pas(db):
    auth, client, h, uid, _ = db
    start, _ = usage.day_window()
    _spend(auth, uid, 5.0, at=start - timedelta(minutes=1))
    assert client.get("/v1/me/usage", headers=h).json()["percent"] == 0


@needs_db
def test_admin_et_mode_mesure_jamais_bloques(db, monkeypatch):
    auth, client, h, uid, email = db
    _spend(auth, uid, 1.0)
    monkeypatch.setenv("QUOTA_ENFORCE", "0")
    assert client.post("/v1/chat", json={}, headers=h).status_code == 422
    monkeypatch.setenv("QUOTA_ENFORCE", "1")
    assert client.post("/v1/chat", json={"message": "Bonjour"}, headers=h).status_code == 402
    monkeypatch.delenv("QUOTA_ENFORCE")
    monkeypatch.setenv("ADMIN_EMAILS", email)
    auth.ensure_auth_schema()
    state = client.get("/v1/me/usage", headers=h).json()
    assert state["unlimited"] and not state["exhausted"]
    # Admin : jamais 402 (le pipeline, sans modèle branché ici, répond 500)
    assert client.post("/v1/chat", json={"message": "Bonjour"}, headers=h).status_code != 402


@needs_db
def test_record_ecrit_le_cout(db):
    auth, client, h, uid, _ = db
    m = usage.UsageMeter()
    m.add_claude("claude-haiku-4-5", _u(10_000, 2_000))       # 0,02 $
    usage.record({"sub": uid, "email": _}, "chat", m)
    assert usage.used_today_usd({"sub": uid, "email": _}) == pytest.approx(0.02)


# ── Quota rattaché à l'adresse, limites par compte, Haiku 5.5 ────────────────

def test_normalisation_email():
    assert usage.normalize_email(" Ali.Hassan+test@GMail.com ") == "alihassan@gmail.com"
    assert usage.normalize_email("a.b+x@googlemail.com") == "ab@gmail.com"
    assert usage.normalize_email("a.b+x@amiin.dj") == "a.b@amiin.dj"
    k = usage.quota_key({"sub": "u1", "email": "a.b+1@gmail.com"})
    assert k == usage.quota_key({"sub": "u2", "email": "ab@gmail.com"})   # autre compte, même adresse
    assert "gmail" not in k                                                  # haché


@needs_db
def test_supprimer_et_recreer_ne_remet_pas_le_quota_a_zero(db):
    auth, client, h, uid, email = db
    m = usage.UsageMeter()
    m.add_claude("claude-haiku-4-5", _u(100_000, 5_000))         # 0,125 $ > 0,10 $
    usage.record({"sub": uid, "email": email}, "chat", m)
    assert client.get("/v1/me/usage", headers=h).json()["exhausted"]
    assert client.request("DELETE", "/v1/auth/me", json={"password": "motdepasse123"},
                          headers=h).status_code == 204
    variante = email.replace("@", "+bis@")
    for adresse in (email, variante):
        r = client.post("/v1/auth/register", json={"email": adresse, "password": "motdepasse123"})
        assert r.status_code == 201
        h2 = {"Authorization": f"Bearer {r.json()['access_token']}"}
        assert client.get("/v1/me/usage", headers=h2).json()["exhausted"]
        assert client.post("/v1/chat", json={"message": "Bonjour"}, headers=h2).status_code == 402


def test_requetes_simultanees_par_compte(api):
    from fastapi import HTTPException
    user = {"sub": f"u-{uuid.uuid4().hex}"}
    a, b = api._inflight_acquire(user), api._inflight_acquire(user)
    with pytest.raises(HTTPException) as e:
        api._inflight_acquire(user)
    assert e.value.status_code == 429
    api._inflight_release(user, a)
    c = api._inflight_acquire(user)                  # une place s'est libérée
    api._inflight_release(user, b)
    api._inflight_release(user, c)
    assert api._inflight_acquire({"sub": "x", "role": "admin"}) is None   # admin : pas de limite


def test_parametres_haiku_5_5(api):
    kw = api._sampling_kwargs("claude-haiku-5-5")
    assert "temperature" not in kw and kw["thinking"] == {"type": "disabled"}
    assert kw["output_config"] == {"effort": "low"}
    assert api._sampling_kwargs("claude-haiku-4-5-20251001", temperature=0.0) == {"temperature": 0.0}
    assert api._model_for({"ai_language": "fr"}) == api.MODEL_CLAUDE == "claude-haiku-5-5"
    assert api._model_for({"ai_language": "en"}) == "claude-haiku-5-5"
    assert api._model_for({"ai_language": "so"}) == api.MODEL_CLAUDE_SO


def test_reformulation_lit_le_texte_par_type(api, monkeypatch):
    resp = SimpleNamespace(usage=_u(100, 20), content=[
        SimpleNamespace(type="thinking", thinking=""),
        SimpleNamespace(type="text", text='{"v1": "a", "v2": "b", "v3": "c"}')])
    seen = {}

    def create(**kw):
        seen.update(kw)
        return resp
    monkeypatch.setattr(api, "claude_client", SimpleNamespace(messages=SimpleNamespace(create=create)))
    assert api.expand_query("question") == ["question", "a", "b", "c"]
    assert "temperature" not in seen                          # refusée par Haiku 5.5
