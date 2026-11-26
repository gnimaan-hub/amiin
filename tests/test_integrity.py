# -*- coding: utf-8 -*-
"""Play Integrity : évaluation du verdict, modes off / report / enforce."""

import os
import time
import uuid
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

import integrity

DB_URL = os.environ.get("TEST_DATABASE_URL")


def _payload(action="login", email="ali@amiin.dj", **over):
    p = {
        "requestDetails": {"requestPackageName": "dj.amiin.app",
                           "requestHash": integrity.request_hash(action, email),
                           "timestampMillis": str(int(time.time() * 1000))},
        "appIntegrity": {"appRecognitionVerdict": "PLAY_RECOGNIZED"},
        "deviceIntegrity": {"deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"]},
    }
    for k, v in over.items():
        p[k] = v
    return p


def test_empreinte_identique_a_l_app():
    # Même calcul que MainActivity.kt : SHA-256 hexadécimal de « action:adresse »
    import hashlib
    assert integrity.request_hash("login", " Ali@Amiin.DJ ") == \
        hashlib.sha256(b"login:ali@amiin.dj").hexdigest()


def test_verdict_valide():
    assert integrity.evaluate(_payload(), "login", "ali@amiin.dj") == []


@pytest.mark.parametrize("over,probleme", [
    ({"requestDetails": {"requestPackageName": "com.pirate", "requestHash": "x",
                         "timestampMillis": "0"}}, "paquet"),
    ({"appIntegrity": {"appRecognitionVerdict": "UNRECOGNIZED_VERSION"}}, "app_non_reconnue"),
    ({"deviceIntegrity": {"deviceRecognitionVerdict": []}}, "appareil_non_integre"),
])
def test_verdicts_refuses(over, probleme):
    assert probleme in integrity.evaluate(_payload(**over), "login", "ali@amiin.dj")


def test_jeton_d_une_autre_adresse_ou_action():
    p = _payload("login", "ali@amiin.dj")
    assert "empreinte" in integrity.evaluate(p, "login", "autre@amiin.dj")
    assert "empreinte" in integrity.evaluate(p, "register", "ali@amiin.dj")


def test_jeton_perime():
    p = _payload()
    p["requestDetails"]["timestampMillis"] = str(int((time.time() - 600) * 1000))
    assert "jeton_perime" in integrity.evaluate(p, "login", "ali@amiin.dj")


def _req(token=None):
    return SimpleNamespace(headers={"x-amiin-integrity": token} if token else {})


def test_modes(monkeypatch):
    monkeypatch.setenv("INTEGRITY_MODE", "off")
    assert integrity.check(_req(), "login", "a@b.dj") == "off"
    monkeypatch.setenv("INTEGRITY_MODE", "report")
    assert integrity.check(_req(), "login", "a@b.dj") == "absent"          # ne bloque pas
    monkeypatch.setenv("INTEGRITY_MODE", "enforce")
    with pytest.raises(HTTPException) as e:
        integrity.check(_req(), "login", "a@b.dj")
    assert e.value.status_code == 403
    assert integrity.check(_req(), "login", "a@b.dj", is_admin_email=True) == "absent"
    monkeypatch.setattr(integrity, "decode", lambda t: _payload("login", "a@b.dj"))
    assert integrity.check(_req("jeton"), "login", "a@b.dj") == "ok"
    monkeypatch.setattr(integrity, "decode", lambda t: _payload("login", "pirate@b.dj"))
    with pytest.raises(HTTPException):
        integrity.check(_req("jeton"), "login", "a@b.dj")

    def panne(t):
        raise RuntimeError("Google injoignable")
    monkeypatch.setattr(integrity, "decode", panne)
    assert integrity.check(_req("jeton"), "login", "a@b.dj") == "erreur"     # panne : on laisse passer


@pytest.mark.skipif(not DB_URL, reason="TEST_DATABASE_URL non définie")
def test_inscription_en_mode_enforce(api, monkeypatch):
    import auth
    from test_auth_db import _BASE_SCHEMA
    from fastapi.testclient import TestClient
    monkeypatch.setattr(auth, "DATABASE_URL", DB_URL)
    monkeypatch.setenv("EMAIL_VERIFICATION", "off")
    monkeypatch.setenv("ADMIN_EMAILS", "")
    monkeypatch.setenv("INTEGRITY_MODE", "enforce")
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(_BASE_SCHEMA)
    auth.ensure_auth_schema()
    client = TestClient(api.app)
    email = f"i{uuid.uuid4().hex[:8]}@amiin.test"
    body = {"email": email, "password": "motdepasse123"}
    r = client.post("/v1/auth/register", json=body)
    assert r.status_code == 403 and r.headers["x-amiin-error"] == "integrity_required"
    monkeypatch.setattr(integrity, "decode", lambda t: _payload("register", email))
    r = client.post("/v1/auth/register", json=body, headers={"X-Amiin-Integrity": "jeton"})
    assert r.status_code == 201
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/v1/auth/sessions", headers=h).json()[0]["verified"] is True
    # Connexion sans jeton refusée, avec jeton de connexion acceptée
    assert client.post("/v1/auth/login", json=body).status_code == 403
    monkeypatch.setattr(integrity, "decode", lambda t: _payload("login", email))
    assert client.post("/v1/auth/login", json=body,
                       headers={"X-Amiin-Integrity": "jeton"}).status_code == 200
