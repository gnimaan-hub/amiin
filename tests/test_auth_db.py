# -*- coding: utf-8 -*-
"""Comptes contre une vraie base PostgreSQL : vérification d'e-mail, admins,
comptes désactivés, limites persistantes.

Ignorés sans base de test :
    TEST_DATABASE_URL=postgresql://user:pass@localhost/amiin_test python -m pytest tests
La base est modifiée (tables créées, comptes de test) : jamais la production.
"""

import os
import uuid

import pytest

DB_URL = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DB_URL, reason="TEST_DATABASE_URL non définie")

# Schéma de base tel qu'en production (créé à la main à l'origine) ; les
# colonnes ajoutées ensuite le sont par ensure_auth_schema().
_BASE_SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name  TEXT NOT NULL DEFAULT '',
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked    BOOLEAN NOT NULL DEFAULT FALSE
);
"""

ADMIN = "admin@amiin.test"


@pytest.fixture
def env(api, monkeypatch):
    import auth
    monkeypatch.setattr(auth, "DATABASE_URL", DB_URL)
    monkeypatch.setenv("SMTP_FROM", "Amiin <no-reply@amiin.test>")
    monkeypatch.setenv("SMTP_HOST", "smtp.invalid")
    monkeypatch.delenv("BREVO_API_KEY", raising=False)
    monkeypatch.delenv("EMAIL_VERIFICATION", raising=False)
    monkeypatch.setenv("ADMIN_EMAILS", ADMIN)
    sent = []
    monkeypatch.setattr(auth, "_send_email", lambda to, subject, body: sent.append((to, body)))
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(_BASE_SCHEMA)
            cur.execute("DELETE FROM users WHERE email LIKE '%%@amiin.test'")
    auth.ensure_auth_schema()
    auth._auth_buckets.clear()
    auth._status_cache.clear()
    from fastapi.testclient import TestClient
    return auth, TestClient(api.app), sent


def _register(client, email=None, password="motdepasse123"):
    email = email or f"u{uuid.uuid4().hex[:10]}@amiin.test"
    r = client.post("/v1/auth/register", json={"email": email, "password": password})
    assert r.status_code == 201, r.text
    return email, {"Authorization": f"Bearer {r.json()['access_token']}"}, r.json()


def _code(sent, email):
    import re
    return re.search(r"\b(\d{6})\b", [b for to, b in sent if to == email][-1]).group(1)


def test_inscription_puis_verification(env):
    auth, client, sent = env
    email, h, _ = _register(client)

    me = client.get("/v1/auth/me", headers=h).json()
    assert me["email_verified"] is False and me["role"] == "user"
    # Chat et voix fermés tant que l'adresse n'est pas vérifiée
    # (corps vide : la dépendance répond avant la validation du corps)
    assert client.post("/v1/chat", json={}, headers=h).status_code == 403
    assert client.post("/v1/tts", json={}, headers=h).status_code == 403

    assert client.post("/v1/auth/verify-email", json={"code": "000000"}, headers=h).status_code in (400,)
    r = client.post("/v1/auth/verify-email", json={"code": _code(sent, email)}, headers=h)
    assert r.status_code == 200 and r.json()["email_verified"] is True
    # Vérifié : la dépendance laisse passer, on tombe sur la validation du corps
    assert client.post("/v1/chat", json={}, headers=h).status_code == 422


def test_code_verification_tentatives_limitees(env):
    auth, client, sent = env
    email, h, _ = _register(client)
    good = _code(sent, email)
    wrong = "111111" if good != "111111" else "222222"
    for _ in range(auth.VERIFY_MAX_ATTEMPTS):
        assert client.post("/v1/auth/verify-email", json={"code": wrong}, headers=h).status_code == 400
    # Même le bon code est refusé une fois le plafond atteint
    assert client.post("/v1/auth/verify-email", json={"code": good}, headers=h).status_code == 400


def test_renvoi_du_code_limite(env):
    auth, client, sent = env
    _, h, _ = _register(client)
    # Code envoyé à l'inscription : renvoi refusé dans la minute
    assert client.post("/v1/auth/verify-email/send", headers=h).status_code == 429
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE auth_rate_events SET at = at - INTERVAL '2 minutes'")
    assert client.post("/v1/auth/verify-email/send", headers=h).status_code == 202


def test_code_de_verification_inutilisable_pour_reset(env):
    auth, client, sent = env
    email, h, _ = _register(client)
    r = client.post("/v1/auth/reset-password",
                    json={"email": email, "code": _code(sent, email), "new_password": "nouveau-mdp-123"})
    assert r.status_code == 400


def test_admin_verifie_et_sans_limite(env):
    auth, client, sent = env
    _, h, _ = _register(client, ADMIN)
    # Pas d'admin avant d'avoir prouvé la possession de l'adresse
    me = client.get("/v1/auth/me", headers=h).json()
    assert me["role"] == "user" and me["email_verified"] is False
    r = client.post("/v1/auth/verify-email", json={"code": _code(sent, ADMIN)}, headers=h)
    me = r.json()
    assert me["role"] == "admin" and me["email_verified"] is True
    auth._status_cache.clear()
    import amiin_api
    user = auth.get_current_user(type("C", (), {"credentials": h["Authorization"][7:]})())
    for _ in range(100):                                   # plafond normal : 30/min
        amiin_api.chat_user(user)


def test_admin_non_verifie_jamais_promu(env):
    auth, client, _ = env
    _, h, _ = _register(client, ADMIN)          # quelqu'un d'autre prend l'adresse
    auth.ensure_auth_schema()                     # redémarrage du serveur
    auth._status_cache.clear()
    assert client.get("/v1/auth/me", headers=h).json()["role"] == "user"


def test_admin_retire_de_la_liste(env, monkeypatch):
    auth, client, sent = env
    _, h, _ = _register(client, ADMIN)
    client.post("/v1/auth/verify-email", json={"code": _code(sent, ADMIN)}, headers=h)
    monkeypatch.setenv("ADMIN_EMAILS", "")
    auth.ensure_auth_schema()
    assert client.get("/v1/auth/me", headers=h).json()["role"] == "user"


def test_compte_desactive_coupe_immediatement(env):
    auth, client, _ = env
    email, h, tokens = _register(client)
    assert client.get("/v1/auth/me", headers=h).status_code == 200
    with auth._get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE users SET is_active = FALSE WHERE email = %s", (email,))
    auth._status_cache.clear()          # en production : au plus 60 s
    assert client.get("/v1/auth/me", headers=h).status_code == 401
    r = client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 401


def test_echecs_de_connexion_persistants(env):
    auth, client, _ = env
    email, _, _ = _register(client)
    for _ in range(auth.LOGIN_FAIL_MAX):
        r = client.post("/v1/auth/login", json={"email": email, "password": "mauvais-mdp"})
        assert r.status_code == 401
    auth._auth_buckets.clear()          # simule un redémarrage du serveur
    r = client.post("/v1/auth/login", json={"email": email, "password": "motdepasse123"})
    assert r.status_code == 429


def test_verification_desactivee(env, monkeypatch):
    auth, client, sent = env
    monkeypatch.setenv("EMAIL_VERIFICATION", "off")
    email, h, _ = _register(client)
    assert not sent
    assert client.get("/v1/auth/me", headers=h).json()["email_verified"] is True
    assert client.post("/v1/chat", json={}, headers=h).status_code == 422


def test_suppression_du_compte(env):
    auth, client, _ = env
    _, h, _ = _register(client)
    r = client.request("DELETE", "/v1/auth/me", json={"password": "motdepasse123"}, headers=h)
    assert r.status_code == 204
    assert client.get("/v1/auth/me", headers=h).status_code == 401


# ── Appareils connectés (sessions) ────────────────────────────────────────────

def _login(client, email, device, password="motdepasse123"):
    r = client.post("/v1/auth/login", json={"email": email, "password": password},
                    headers={"X-Amiin-Device": device})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}, r.json()["refresh_token"]


def test_sessions_par_appareil(env):
    auth, client, _ = env
    email, _, _ = _register(client)
    h_tel, rt_tel = _login(client, email, "Android 14")
    h_tab, rt_tab = _login(client, email, "Tablette")

    sessions = client.get("/v1/auth/sessions", headers=h_tel).json()
    devices = {s["device"]: s for s in sessions}
    assert {"Android 14", "Tablette"} <= set(devices)
    assert devices["Android 14"]["current"] and not devices["Tablette"]["current"]

    # Le renouvellement garde la même session (et le même appareil)
    r = client.post("/v1/auth/refresh", json={"refresh_token": rt_tel})
    assert r.status_code == 200
    h_tel = {"Authorization": f"Bearer {r.json()['access_token']}"}
    again = client.get("/v1/auth/sessions", headers=h_tel).json()
    assert len(again) == len(sessions)
    assert next(s for s in again if s["current"])["device"] == "Android 14"

    # Fermer la tablette depuis le téléphone
    tab_id = devices["Tablette"]["id"]
    assert client.delete(f"/v1/auth/sessions/{tab_id}", headers=h_tel).status_code == 204
    auth._session_cache.clear()                  # en production : au plus 60 s
    assert client.get("/v1/auth/me", headers=h_tab).status_code == 401
    # …et pas de délai de grâce pour un token révoqué volontairement
    assert client.post("/v1/auth/refresh", json={"refresh_token": rt_tab}).status_code == 401
    assert client.get("/v1/auth/me", headers=h_tel).status_code == 200
    assert client.delete(f"/v1/auth/sessions/{tab_id}", headers=h_tel).status_code == 404


def test_session_d_un_autre_compte_intouchable(env):
    _, client, _ = env
    a, _, _ = _register(client)
    b, _, _ = _register(client)
    h_a, _ = _login(client, a, "A")
    h_b, _ = _login(client, b, "B")
    sid_b = client.get("/v1/auth/sessions", headers=h_b).json()[0]["id"]
    assert client.delete(f"/v1/auth/sessions/{sid_b}", headers=h_a).status_code == 404


def test_deconnexion_sans_delai_de_grace(env):
    _, client, _ = env
    email, _, _ = _register(client)
    _, rt = _login(client, email, "Android")
    assert client.post("/v1/auth/logout", json={"refresh_token": rt}).status_code == 204
    # Avant : un token rejoué dans la minute ressuscitait la session
    assert client.post("/v1/auth/refresh", json={"refresh_token": rt}).status_code == 401


def test_changement_de_mot_de_passe_ferme_les_autres_appareils(env):
    auth, client, _ = env
    email, _, _ = _register(client)
    h_tel, _ = _login(client, email, "Telephone")
    h_pc, _ = _login(client, email, "Web")
    r = client.post("/v1/auth/change-password", headers=h_tel,
                    json={"current_password": "motdepasse123", "new_password": "nouveau-mdp-456"})
    assert r.status_code == 200
    auth._session_cache.clear()
    h_new = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/v1/auth/me", headers=h_pc).status_code == 401
    sessions = client.get("/v1/auth/sessions", headers=h_new).json()
    assert len(sessions) == 1 and sessions[0]["current"]
