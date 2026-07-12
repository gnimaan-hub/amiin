# -*- coding: utf-8 -*-
"""
auth.py — Module d'authentification pour Amiin API
Endpoints : POST /auth/register, /auth/login, /auth/refresh, /auth/logout
            GET  /auth/me
"""

import os
import uuid
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr, field_validator
from passlib.context import CryptContext
from jose import JWTError, jwt
import psycopg2
from psycopg2.extras import RealDictCursor

# ── Config ─────────────────────────────────────────────────────────────────────

JWT_SECRET     = os.environ.get("JWT_SECRET_KEY", "")
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET_KEY manquante — définir cette variable d'environnement "
        "(chaîne aléatoire longue, ex: `openssl rand -hex 32`) avant de démarrer l'API."
    )
JWT_ALGORITHM  = "HS256"
ACCESS_TTL     = timedelta(minutes=30)
REFRESH_TTL    = timedelta(days=30)
DATABASE_URL   = os.environ.get("DATABASE_URL", "")

pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
bearer  = HTTPBearer(auto_error=False)
router  = APIRouter(prefix="/auth", tags=["auth"])

# ── DB helper ──────────────────────────────────────────────────────────────────

def _get_conn():
    return psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)

# ── Schemas ────────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    email: str
    password: str
    display_name: str = ""

    @field_validator("password")
    @classmethod
    def _pw_len(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Le mot de passe doit comporter au moins 8 caractères.")
        return v

    @field_validator("email")
    @classmethod
    def _email_lower(cls, v: str) -> str:
        return v.strip().lower()


class LoginRequest(BaseModel):
    email: str
    password: str

    @field_validator("email")
    @classmethod
    def _email_lower(cls, v: str) -> str:
        return v.strip().lower()


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int = int(ACCESS_TTL.total_seconds())


class UserResponse(BaseModel):
    id: str
    email: str
    display_name: str
    created_at: str


class RefreshRequest(BaseModel):
    refresh_token: str


# ── Token helpers ──────────────────────────────────────────────────────────────

def _make_access_token(user_id: str, email: str) -> str:
    now = datetime.now(tz=timezone.utc)
    payload = {
        "sub": user_id,
        "email": email,
        "iat": now,
        "exp": now + ACCESS_TTL,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _hash_refresh(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _issue_refresh(user_id: str) -> str:
    """Génère un refresh token opaque, le stocke hashé, retourne le raw."""
    raw = secrets.token_urlsafe(48)
    h   = _hash_refresh(raw)
    exp = datetime.now(tz=timezone.utc) + REFRESH_TTL
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES (%s, %s, %s)",
                (user_id, h, exp),
            )
        conn.commit()
    return raw


def _verify_access_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Token invalide ou expiré.")


# ── Auth dependency ────────────────────────────────────────────────────────────

def get_current_user(creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)) -> dict:
    if not creds:
        raise HTTPException(status_code=401, detail="Authentification requise.")
    return _verify_access_token(creds.credentials)


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/register", response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest):
    pw_hash = pwd_ctx.hash(body.password)
    display = body.display_name or body.email.split("@")[0]
    try:
        with _get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO users (email, password_hash, display_name)
                       VALUES (%s, %s, %s) RETURNING id::text""",
                    (body.email, pw_hash, display),
                )
                row = cur.fetchone()
            conn.commit()
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail="Cet email est déjà utilisé.")

    uid = row["id"]
    return TokenResponse(
        access_token=_make_access_token(uid, body.email),
        refresh_token=_issue_refresh(uid),
    )


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest):
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id::text, password_hash, is_active FROM users WHERE email = %s",
                (body.email,),
            )
            row = cur.fetchone()

    if not row or not pwd_ctx.verify(body.password, row["password_hash"]):
        raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect.")
    if not row["is_active"]:
        raise HTTPException(status_code=403, detail="Compte désactivé.")

    uid = row["id"]
    return TokenResponse(
        access_token=_make_access_token(uid, body.email),
        refresh_token=_issue_refresh(uid),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(body: RefreshRequest):
    h = _hash_refresh(body.refresh_token)
    now = datetime.now(tz=timezone.utc)

    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT rt.id::text, rt.user_id::text, u.email
                   FROM refresh_tokens rt
                   JOIN users u ON u.id = rt.user_id
                   WHERE rt.token_hash = %s
                     AND rt.revoked = FALSE
                     AND rt.expires_at > %s""",
                (h, now),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=401, detail="Refresh token invalide ou expiré.")

            # Rotation : on révoque l'ancien et on en émet un nouveau
            cur.execute("UPDATE refresh_tokens SET revoked = TRUE WHERE id = %s", (row["id"],))
        conn.commit()

    uid = row["user_id"]
    return TokenResponse(
        access_token=_make_access_token(uid, row["email"]),
        refresh_token=_issue_refresh(uid),
    )


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest):
    """Révoque le refresh token fourni (le client doit aussi supprimer le JWT localement)."""
    h = _hash_refresh(body.refresh_token)
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = %s", (h,))
        conn.commit()


@router.get("/me", response_model=UserResponse)
def me(current_user: dict = Depends(get_current_user)):
    uid = current_user["sub"]
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id::text, email, display_name, created_at FROM users WHERE id = %s",
                (uid,),
            )
            row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return UserResponse(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["created_at"].isoformat(),
    )
