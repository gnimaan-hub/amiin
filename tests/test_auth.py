# -*- coding: utf-8 -*-
"""Mots de passe, JWT et limites de débit du module d'authentification."""

import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi import HTTPException
from pydantic import ValidationError

import auth


def test_hash_et_verification():
    h = auth.hash_password("motdepasse123")
    assert h.startswith("$2b$")
    assert auth.verify_password("motdepasse123", h)
    assert not auth.verify_password("autre", h)
    assert not auth.verify_password("x", "pas-un-hash")


def test_mot_de_passe_long_tronque_a_72_octets():
    # Comportement historique de passlib : seuls les 72 premiers octets comptent
    long_pw = "é" * 100
    assert auth.verify_password(long_pw, auth.hash_password(long_pw))


def test_compatible_hashes_passlib_existants():
    # Hash produit par l'ancienne pile de production (passlib 1.7.4 + bcrypt 3.2.2)
    old_hash = "$2b$12$n8gwyD.UaBayMBqItRBnOehzgAnepBYNhMiau.pjhYTNDXHJKrQBG"
    assert auth.verify_password("ancien-mot-de-passe", old_hash)
    assert not auth.verify_password("autre", old_hash)


def test_jwt_valide_expire_et_falsifie():
    token = auth._make_access_token("u1", "a@b.dj")
    assert auth._verify_access_token(token)["sub"] == "u1"

    expired = jwt.encode({"sub": "u1", "exp": datetime.now(timezone.utc) - timedelta(minutes=1)},
                         auth.JWT_SECRET, algorithm="HS256")
    forged = jwt.encode({"sub": "u1", "exp": datetime.now(timezone.utc) + timedelta(minutes=5)},
                        "mauvaise-cle-mauvaise-cle-mauvaise-cle", algorithm="HS256")
    unsigned = jwt.encode({"sub": "u1"}, None, algorithm="none")
    for bad in (expired, forged, unsigned, "pas.un.jwt"):
        with pytest.raises(HTTPException) as e:
            auth._verify_access_token(bad)
        assert e.value.status_code == 401


def test_jwt_sans_exp_refuse():
    token = jwt.encode({"sub": "u1"}, auth.JWT_SECRET, algorithm="HS256")
    with pytest.raises(HTTPException):
        auth._verify_access_token(token)


def test_rate_limit():
    key = f"test:{time.monotonic()}"
    for _ in range(3):
        auth._hit(key, max_calls=3, window_s=60)
    with pytest.raises(HTTPException) as e:
        auth._hit(key, max_calls=3, window_s=60)
    assert e.value.status_code == 429


def test_ip_client_derriere_proxy():
    class Req:
        headers = {"x-forwarded-for": "6.6.6.6, 41.189.1.1"}
        client = None
    assert auth._client_ip(Req()) == "41.189.1.1"


def test_plafond_echecs_login_par_email():
    email = f"x{time.monotonic()}@b.dj"
    for _ in range(10):
        auth._auth_buckets[f"login_fail:{email}"].append(time.monotonic())
    assert auth._login_failures_exceeded(email)
    assert not auth._login_failures_exceeded("autre@b.dj")


# ── Profil, changement et réinitialisation du mot de passe ────────────────────

def test_code_reinitialisation_hmac():
    h = auth._hash_reset_code("u1", "123456")
    assert h == auth._hash_reset_code("u1", "123456")
    assert h != auth._hash_reset_code("u2", "123456")   # lié à l'utilisateur
    assert "123456" not in h


@pytest.mark.parametrize("code", ["12345", "1234567", "abcdef", "12 456"])
def test_code_format_invalide(code):
    with pytest.raises(ValidationError):
        auth.ResetPasswordRequest(email="a@b.dj", code=code, new_password="motdepasse")


def test_nouveau_mot_de_passe_trop_court():
    with pytest.raises(ValidationError):
        auth.ResetPasswordRequest(email="a@b.dj", code="123456", new_password="court")
    with pytest.raises(ValidationError):
        auth.ChangePasswordRequest(current_password="x", new_password="court")


def test_nom_affiche_normalise():
    assert auth.UpdateProfileRequest(display_name="  Ali \n Hassan ").display_name == "Ali Hassan"
    with pytest.raises(ValidationError):
        auth.UpdateProfileRequest(display_name="   ")


def test_mot_de_passe_oublie_sans_smtp_503(api, monkeypatch):
    from fastapi.testclient import TestClient
    monkeypatch.delenv("SMTP_HOST", raising=False)
    resp = TestClient(api.app).post("/v1/auth/forgot-password", json={"email": "a@b.dj"})
    assert resp.status_code == 503
