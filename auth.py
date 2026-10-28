# -*- coding: utf-8 -*-
"""
auth.py — Module d'authentification pour Amiin API
Endpoints : POST /auth/register, /auth/login, /auth/refresh, /auth/logout,
                 /auth/logout-all, /auth/change-password,
                 /auth/forgot-password, /auth/reset-password
            GET/PATCH/DELETE /auth/me
"""

import os
import hmac
import time
import uuid
import hashlib
import logging
import secrets
import smtplib
from email.message import EmailMessage
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from contextlib import contextmanager

from pydantic import BaseModel, EmailStr, Field, field_validator
import bcrypt
import jwt
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
REFRESH_REUSE_GRACE = timedelta(seconds=60)
DATABASE_URL   = os.environ.get("DATABASE_URL", "")

bearer  = HTTPBearer(auto_error=False)
router  = APIRouter(prefix="/auth", tags=["auth"])

# ── Mots de passe (bcrypt direct, hashes $2b$ compatibles avec ceux de passlib) ─
# bcrypt ne lit que les 72 premiers octets ; passlib tronquait silencieusement,
# bcrypt ≥ 4.1 lève une erreur. On tronque explicitement pour rester compatible
# avec les hashes existants.

def _pw_bytes(password: str) -> bytes:
    return password.encode("utf-8")[:72]

def hash_password(password: str) -> str:
    return bcrypt.hashpw(_pw_bytes(password), bcrypt.gensalt()).decode()

def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(_pw_bytes(password), password_hash.encode())
    except ValueError:
        return False

# ── DB helper ──────────────────────────────────────────────────────────────────

@contextmanager
def _get_conn():
    """Connexion courte : commit si tout va bien, rollback sinon, fermeture
    garantie (le `with conn:` de psycopg2 seul ne ferme pas la connexion)."""
    conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

# ── Rate limiting (fenêtre glissante en mémoire, instance unique) ──────────────
# Seuils volontairement larges par IP : à Djibouti beaucoup d'abonnés mobiles
# sortent par la même IP (CGNAT). La vraie protection anti-force-brute est le
# plafond d'échecs par email.

_auth_buckets: dict = defaultdict(deque)

def _hit(key: str, max_calls: int, window_s: int) -> None:
    now = time.monotonic()
    bucket = _auth_buckets[key]
    while bucket and now - bucket[0] > window_s:
        bucket.popleft()
    if len(bucket) >= max_calls:
        raise HTTPException(status_code=429, detail="Trop de tentatives — réessayez plus tard.")
    bucket.append(now)

def _client_ip(request: Request) -> str:
    # Derrière le proxy Render : la dernière entrée de X-Forwarded-For est celle
    # ajoutée par le proxy (les précédentes peuvent être forgées par le client).
    fwd = request.headers.get("x-forwarded-for", "")
    if fwd:
        return fwd.split(",")[-1].strip()
    return request.client.host if request.client else "unknown"

def _login_failures_exceeded(email: str) -> bool:
    bucket = _auth_buckets[f"login_fail:{email}"]
    now = time.monotonic()
    while bucket and now - bucket[0] > 15 * 60:
        bucket.popleft()
    return len(bucket) >= 10

# ── Schemas ────────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)
    display_name: str = Field("", max_length=60)

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
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)

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
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM],
                          options={"require": ["exp", "sub"]})
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Token invalide ou expiré.")


def ensure_auth_schema() -> None:
    """Migrations idempotentes, appelées au démarrage de l'API."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS password_reset_codes (
                    user_id    TEXT PRIMARY KEY,
                    code_hash  TEXT NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    attempts   INTEGER NOT NULL DEFAULT 0
                )""")


def _revoke_all(cur, user_id: str) -> None:
    cur.execute(
        "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW() "
        "WHERE user_id = %s AND revoked = FALSE",
        (user_id,),
    )


# ── Auth dependency ────────────────────────────────────────────────────────────

def get_current_user(creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)) -> dict:
    if not creds:
        raise HTTPException(status_code=401, detail="Authentification requise.")
    return _verify_access_token(creds.credentials)


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/register", response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest, request: Request):
    _hit(f"register:{_client_ip(request)}", max_calls=20, window_s=3600)
    pw_hash = hash_password(body.password)
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
def login(body: LoginRequest, request: Request):
    _hit(f"login:{_client_ip(request)}", max_calls=30, window_s=60)
    if _login_failures_exceeded(body.email):
        raise HTTPException(status_code=429, detail="Trop de tentatives — réessayez dans 15 minutes.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id::text, password_hash, is_active FROM users WHERE email = %s",
                (body.email,),
            )
            row = cur.fetchone()

    if not row or not verify_password(body.password, row["password_hash"]):
        _auth_buckets[f"login_fail:{body.email}"].append(time.monotonic())
        raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect.")
    if not row["is_active"]:
        raise HTTPException(status_code=403, detail="Compte désactivé.")

    uid = row["id"]
    return TokenResponse(
        access_token=_make_access_token(uid, body.email),
        refresh_token=_issue_refresh(uid),
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(body: RefreshRequest, request: Request):
    _hit(f"refresh:{_client_ip(request)}", max_calls=60, window_s=60)
    h = _hash_refresh(body.refresh_token)
    now = datetime.now(tz=timezone.utc)

    invalid = HTTPException(status_code=401, detail="Refresh token invalide ou expiré.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT rt.id::text, rt.user_id::text, u.email, rt.revoked, rt.revoked_at
                   FROM refresh_tokens rt
                   JOIN users u ON u.id = rt.user_id
                   WHERE rt.token_hash = %s
                     AND rt.expires_at > %s""",
                (h, now),
            )
            row = cur.fetchone()
            if not row:
                raise invalid

            if row["revoked"]:
                # Délai de grâce : sur mobile, la réponse d'un refresh réussi
                # peut se perdre et l'app rejoue l'ancien token. Au-delà, un
                # token déjà tourné qui réapparaît signale un vol probable :
                # on coupe toutes les sessions de l'utilisateur.
                revoked_at = row["revoked_at"]
                if revoked_at is None or now - revoked_at > REFRESH_REUSE_GRACE:
                    _revoke_all(cur, row["user_id"])
                    conn.commit()
                    raise invalid
            else:
                # Rotation : on révoque l'ancien et on en émet un nouveau
                cur.execute(
                    "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW() WHERE id = %s",
                    (row["id"],),
                )
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
            cur.execute(
                "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW() "
                "WHERE token_hash = %s AND revoked = FALSE",
                (h,),
            )
        conn.commit()


@router.post("/logout-all", status_code=204)
def logout_all(current_user: dict = Depends(get_current_user)):
    """Révoque toutes les sessions (refresh tokens) de l'utilisateur, sur tous
    ses appareils. Les access tokens déjà émis expirent d'eux-mêmes (30 min)."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            _revoke_all(cur, current_user["sub"])


class DeleteAccountRequest(BaseModel):
    password: str = Field(max_length=128)


@router.delete("/me", status_code=204)
def delete_account(body: DeleteAccountRequest, request: Request,
                   current_user: dict = Depends(get_current_user)):
    """Suppression définitive du compte et des données serveur associées
    (exigée par Google Play et l'App Store). Mot de passe requis."""
    _hit(f"delete:{_client_ip(request)}", max_calls=10, window_s=3600)
    uid = current_user["sub"]
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT password_hash FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
            if not verify_password(body.password, row["password_hash"]):
                raise HTTPException(status_code=401, detail="Mot de passe incorrect.")
            cur.execute("SELECT to_regclass('annuaire_favorites') IS NOT NULL AS ok")
            if cur.fetchone()["ok"]:
                cur.execute("DELETE FROM annuaire_favorites WHERE user_id = %s", (uid,))
            cur.execute("SELECT to_regclass('password_reset_codes') IS NOT NULL AS ok")
            if cur.fetchone()["ok"]:
                cur.execute("DELETE FROM password_reset_codes WHERE user_id = %s", (uid,))
            cur.execute("DELETE FROM refresh_tokens WHERE user_id = %s", (uid,))
            cur.execute("DELETE FROM users WHERE id = %s", (uid,))


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


# ── Profil & mot de passe ──────────────────────────────────────────────────────

def _check_new_password(v: str) -> str:
    if len(v) < 8:
        raise ValueError("Le mot de passe doit comporter au moins 8 caractères.")
    return v


class UpdateProfileRequest(BaseModel):
    display_name: str = Field(min_length=1, max_length=60)

    @field_validator("display_name")
    @classmethod
    def _strip(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("Le nom ne peut pas être vide.")
        return v


@router.patch("/me", response_model=UserResponse)
def update_me(body: UpdateProfileRequest, current_user: dict = Depends(get_current_user)):
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE users SET display_name = %s WHERE id = %s
                   RETURNING id::text, email, display_name, created_at""",
                (body.display_name, current_user["sub"]),
            )
            row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return UserResponse(id=row["id"], email=row["email"], display_name=row["display_name"],
                        created_at=row["created_at"].isoformat())


class ChangePasswordRequest(BaseModel):
    current_password: str = Field(max_length=128)
    new_password: str = Field(max_length=128)

    @field_validator("new_password")
    @classmethod
    def _pw_len(cls, v: str) -> str:
        return _check_new_password(v)


@router.post("/change-password", response_model=TokenResponse)
def change_password(body: ChangePasswordRequest, request: Request,
                    current_user: dict = Depends(get_current_user)):
    """Change le mot de passe, coupe toutes les autres sessions et renvoie de
    nouveaux tokens pour l'appareil courant."""
    _hit(f"chpw:{_client_ip(request)}", max_calls=10, window_s=3600)
    uid = current_user["sub"]
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT email, password_hash FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
            if not verify_password(body.current_password, row["password_hash"]):
                raise HTTPException(status_code=401, detail="Mot de passe actuel incorrect.")
            cur.execute("UPDATE users SET password_hash = %s WHERE id = %s",
                        (hash_password(body.new_password), uid))
            _revoke_all(cur, uid)
    return TokenResponse(
        access_token=_make_access_token(uid, row["email"]),
        refresh_token=_issue_refresh(uid),
    )


# ── Mot de passe oublié (code à 6 chiffres par e-mail) ─────────────────────────
# Un code plutôt qu'un lien : pas besoin de page web ni de deep link, l'app
# saisit le code directement. Variables d'environnement : SMTP_HOST,
# SMTP_PORT (587 STARTTLS, 465 SSL), SMTP_USER, SMTP_PASSWORD, SMTP_FROM.

RESET_CODE_TTL     = timedelta(minutes=30)
RESET_MAX_ATTEMPTS = 5


def _smtp_configured() -> bool:
    return bool(os.environ.get("SMTP_HOST") and os.environ.get("SMTP_FROM"))


def _hash_reset_code(user_id: str, code: str) -> str:
    # HMAC avec le secret serveur : un dump de la table ne permet pas de
    # retrouver les codes par force brute hors ligne (10^6 possibilités).
    return hmac.new(JWT_SECRET.encode(), f"{user_id}:{code}".encode(), hashlib.sha256).hexdigest()


def _send_reset_email(to: str, code: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = "Amiin — code de réinitialisation du mot de passe"
    msg["From"] = os.environ["SMTP_FROM"]
    msg["To"] = to
    msg.set_content(
        f"Bonjour,\n\nVotre code de réinitialisation Amiin est : {code}\n\n"
        "Il est valable 30 minutes. Si vous n'êtes pas à l'origine de cette "
        "demande, ignorez ce message : votre mot de passe reste inchangé.\n\n— Amiin"
    )
    host = os.environ["SMTP_HOST"]
    port = int(os.environ.get("SMTP_PORT", "587"))
    user, password = os.environ.get("SMTP_USER"), os.environ.get("SMTP_PASSWORD")
    try:
        if port == 465:
            server = smtplib.SMTP_SSL(host, port, timeout=15)
        else:
            server = smtplib.SMTP(host, port, timeout=15)
            server.starttls()
        with server:
            if user:
                server.login(user, password or "")
            server.send_message(msg)
    except Exception:
        logging.exception("Envoi de l'e-mail de réinitialisation impossible")


class ForgotPasswordRequest(BaseModel):
    email: str = Field(max_length=254)

    @field_validator("email")
    @classmethod
    def _email_lower(cls, v: str) -> str:
        return v.strip().lower()


class ResetPasswordRequest(ForgotPasswordRequest):
    code: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(max_length=128)

    @field_validator("new_password")
    @classmethod
    def _pw_len(cls, v: str) -> str:
        return _check_new_password(v)


@router.post("/forgot-password", status_code=202)
def forgot_password(body: ForgotPasswordRequest, request: Request, background: BackgroundTasks):
    """Envoie un code si le compte existe. Réponse identique dans tous les cas
    (pas d'énumération des comptes) ; l'e-mail part en tâche de fond pour que
    le temps de réponse ne trahisse rien non plus."""
    if not _smtp_configured():
        raise HTTPException(status_code=503,
                            detail="Réinitialisation indisponible pour le moment. Contactez le support.")
    _hit(f"forgot:{_client_ip(request)}", max_calls=10, window_s=3600)
    _hit(f"forgot_email:{body.email}", max_calls=3, window_s=3600)
    code = f"{secrets.randbelow(10**6):06d}"
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id::text FROM users WHERE email = %s AND is_active", (body.email,))
            row = cur.fetchone()
            if row:
                cur.execute(
                    """INSERT INTO password_reset_codes (user_id, code_hash, expires_at, attempts)
                       VALUES (%s, %s, %s, 0)
                       ON CONFLICT (user_id) DO UPDATE
                       SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
                           attempts = 0""",
                    (row["id"], _hash_reset_code(row["id"], code),
                     datetime.now(tz=timezone.utc) + RESET_CODE_TTL),
                )
    if row:
        background.add_task(_send_reset_email, body.email, code)
    return {"detail": "Si un compte existe pour cet e-mail, un code vient d'y être envoyé."}


@router.post("/reset-password", status_code=204)
def reset_password(body: ResetPasswordRequest, request: Request):
    _hit(f"reset:{_client_ip(request)}", max_calls=20, window_s=3600)
    invalid = HTTPException(status_code=400, detail="Code invalide ou expiré.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT u.id::text AS uid, r.code_hash, r.expires_at, r.attempts
                   FROM users u JOIN password_reset_codes r ON r.user_id = u.id::text
                   WHERE u.email = %s""",
                (body.email,),
            )
            row = cur.fetchone()
            if (not row or row["attempts"] >= RESET_MAX_ATTEMPTS
                    or row["expires_at"] < datetime.now(tz=timezone.utc)):
                raise invalid
            if not hmac.compare_digest(row["code_hash"], _hash_reset_code(row["uid"], body.code)):
                cur.execute(
                    "UPDATE password_reset_codes SET attempts = attempts + 1 WHERE user_id = %s",
                    (row["uid"],),
                )
                conn.commit()
                raise invalid
            cur.execute("UPDATE users SET password_hash = %s WHERE id = %s",
                        (hash_password(body.new_password), row["uid"]))
            cur.execute("DELETE FROM password_reset_codes WHERE user_id = %s", (row["uid"],))
            _revoke_all(cur, row["uid"])
