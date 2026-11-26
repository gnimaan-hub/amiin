# -*- coding: utf-8 -*-
"""
auth.py — Module d'authentification pour Amiin API
Endpoints : POST /auth/register, /auth/login, /auth/refresh, /auth/logout,
                 /auth/logout-all, /auth/change-password,
                 /auth/forgot-password, /auth/reset-password,
                 /auth/verify-email, /auth/verify-email/send
            GET/PATCH/DELETE /auth/me

Variables d'environnement liées aux comptes :
  ADMIN_EMAILS        e-mails (séparés par des virgules) des administrateurs : aucune
                      limite d'usage. Le rôle n'est accordé qu'une fois l'adresse
                      VÉRIFIÉE (code reçu par e-mail), pour qu'on ne puisse pas le
                      prendre en s'inscrivant avec l'adresse d'un admin. Un e-mail
                      retiré de la liste redevient simple utilisateur.
  EMAIL_VERIFICATION  "required" | "off". Par défaut : exigée dès qu'un envoi
                      d'e-mails est configuré (BREVO_API_KEY ou SMTP_HOST).
  BREVO_API_KEY       envoi via l'API HTTP Brevo (prioritaire sur SMTP).
  SMTP_FROM           expéditeur, ex. "Amiin <no-reply@amiin.dj>" (requis).
  SMTP_HOST/PORT/USER/PASSWORD  envoi SMTP classique.
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
from email.utils import parseaddr
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
import requests

import integrity
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

# ── Limites persistantes (PostgreSQL) ──────────────────────────────────────────
# Pour tout ce qui vise un COMPTE (échecs de connexion, envois de codes,
# vérification d'e-mail) : ces compteurs survivent aux redémarrages et aux
# mises en veille de Render, contrairement aux buckets en mémoire ci-dessus
# qui restent réservés aux plafonds grossiers par IP.

LOGIN_FAIL_MAX    = 10
LOGIN_FAIL_WINDOW = 15 * 60

def _db_recent_count(cur, key: str, window_s: int) -> int:
    cur.execute(
        "SELECT COUNT(*) AS n FROM auth_rate_events "
        "WHERE key = %s AND at > NOW() - make_interval(secs => %s)",
        (key, window_s),
    )
    return cur.fetchone()["n"]

def _db_record(cur, key: str) -> None:
    cur.execute("INSERT INTO auth_rate_events (key) VALUES (%s)", (key,))

def _db_hit(cur, key: str, max_calls: int, window_s: int,
            detail: str = "Trop de tentatives — réessayez plus tard.") -> None:
    """Compte un appel pour `key` ; 429 si le plafond de la fenêtre est atteint."""
    if _db_recent_count(cur, key, window_s) >= max_calls:
        raise HTTPException(status_code=429, detail=detail)
    _db_record(cur, key)

def _account_hit(key: str, max_calls: int, window_s: int) -> None:
    """Comme _db_hit, dans sa propre transaction : la tentative reste comptée
    même si la requête échoue ensuite (mauvais mot de passe…)."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            _db_hit(cur, key, max_calls, window_s)


def _login_failures_exceeded(cur, email: str) -> bool:
    return _db_recent_count(cur, f"login_fail:{email}", LOGIN_FAIL_WINDOW) >= LOGIN_FAIL_MAX

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
    email_verified: bool = True
    role: str = "user"


class RefreshRequest(BaseModel):
    refresh_token: str


# ── Token helpers ──────────────────────────────────────────────────────────────

def _make_access_token(user_id: str, email: str, session_id: Optional[str] = None) -> str:
    now = datetime.now(tz=timezone.utc)
    payload = {
        "sub": user_id,
        "email": email,
        "iat": now,
        "exp": now + ACCESS_TTL,
    }
    if session_id:
        payload["sid"] = session_id   # session (appareil) d'où vient ce jeton
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _hash_refresh(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ── Sessions (une par appareil connecté) ────────────────────────────────────────
# Une connexion ouvre une SESSION (family_id). Chaque renouvellement du refresh
# token crée une nouvelle ligne dans la même session ; la session vit tant
# qu'elle a un refresh token non révoqué et non expiré. Le JWT porte l'id de
# session (`sid`) : l'appareil courant est reconnu dans la liste des sessions,
# et une session fermée depuis un autre appareil perd l'accès en 1 min au plus.

def _device_label(request: Optional[Request]) -> str:
    """Nom d'appareil envoyé par l'app (en-tête X-Amiin-Device), nettoyé."""
    raw = request.headers.get("x-amiin-device", "") if request is not None else ""
    label = "".join(ch for ch in raw if ch.isprintable()).strip()[:60]
    return label or "Appareil inconnu"


def _issue_refresh(user_id: str, session_id: Optional[str] = None,
                   device: Optional[str] = None,
                   started_at: Optional[datetime] = None,
                   integrity_status: Optional[str] = None) -> tuple:
    """Génère un refresh token opaque, le stocke hashé.
    Retourne (token brut, id de session) ; nouvelle session si session_id est None."""
    raw = secrets.token_urlsafe(48)
    h   = _hash_refresh(raw)
    now = datetime.now(tz=timezone.utc)
    exp = now + REFRESH_TTL
    session_id = session_id or str(uuid.uuid4())
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO refresh_tokens
                   (user_id, token_hash, expires_at, family_id, device_label, family_started_at,
                    integrity)
                   VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                (user_id, h, exp, session_id, device or "Appareil inconnu", started_at or now,
                 integrity_status),
            )
        conn.commit()
    return raw, session_id


def _new_tokens(user_id: str, email: str, request: Optional[Request] = None,
                session_id: Optional[str] = None, device: Optional[str] = None,
                started_at: Optional[datetime] = None,
                integrity_status: Optional[str] = None) -> "TokenResponse":
    raw, sid = _issue_refresh(user_id, session_id,
                              device or _device_label(request), started_at, integrity_status)
    return TokenResponse(access_token=_make_access_token(user_id, email, sid),
                         refresh_token=raw)


def _verify_access_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM],
                          options={"require": ["exp", "sub"]})
    except jwt.PyJWTError:
        raise HTTPException(status_code=401, detail="Token invalide ou expiré.")


# ── Administrateurs et vérification d'e-mail ───────────────────────────────────

def admin_emails() -> list:
    return sorted({e.strip().lower() for e in os.environ.get("ADMIN_EMAILS", "").split(",")
                   if e.strip()})


def mail_configured() -> bool:
    return bool(os.environ.get("SMTP_FROM")
                and (os.environ.get("BREVO_API_KEY") or os.environ.get("SMTP_HOST")))


def email_verification_required() -> bool:
    mode = os.environ.get("EMAIL_VERIFICATION", "").strip().lower()
    if mode in ("off", "0", "false", "non"):
        return False
    if mode in ("required", "on", "1", "true", "oui"):
        return True
    # Par défaut : on n'exige la vérification que si l'on peut envoyer le code,
    # sinon plus personne ne pourrait utiliser l'application.
    return mail_configured()


def _effective_verified(row: dict) -> bool:
    """Vérification « effective » : un admin ou un mode sans vérification
    valent une adresse vérifiée."""
    return (not email_verification_required()
            or row.get("role") == "admin"
            or bool(row.get("email_verified")))


def ensure_auth_schema() -> None:
    """Migrations idempotentes, appelées au démarrage de l'API."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ")
            # Sessions par appareil (voir _issue_refresh). Les tokens d'avant
            # deviennent chacun leur propre session.
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS family_id TEXT")
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS device_label TEXT")
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS "
                        "created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()")
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS "
                        "family_started_at TIMESTAMPTZ")
            # 'rotated' (renouvellement normal) ou 'revoked' (déconnexion,
            # session fermée) : seul un token tourné bénéficie du délai de grâce.
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS revoked_reason TEXT")
            # Résultat Play Integrity à l'ouverture de la session (integrity.py)
            cur.execute("ALTER TABLE refresh_tokens ADD COLUMN IF NOT EXISTS integrity TEXT")
            cur.execute("UPDATE refresh_tokens SET family_id = id::text, "
                        "family_started_at = COALESCE(family_started_at, created_at) "
                        "WHERE family_id IS NULL")
            cur.execute("CREATE INDEX IF NOT EXISTS refresh_tokens_family "
                        "ON refresh_tokens (family_id)")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS password_reset_codes (
                    user_id    TEXT PRIMARY KEY,
                    code_hash  TEXT NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    attempts   INTEGER NOT NULL DEFAULT 0
                )""")
            # Comptes existants : non vérifiés. Ils saisiront un code une fois,
            # dès que la vérification sera active (envoi d'e-mails configuré).
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified "
                        "BOOLEAN NOT NULL DEFAULT FALSE")
            cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS role "
                        "TEXT NOT NULL DEFAULT 'user'")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS email_verification_codes (
                    user_id    TEXT PRIMARY KEY,
                    code_hash  TEXT NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    attempts   INTEGER NOT NULL DEFAULT 0
                )""")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS auth_rate_events (
                    key TEXT NOT NULL,
                    at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )""")
            cur.execute("CREATE INDEX IF NOT EXISTS auth_rate_events_key_at "
                        "ON auth_rate_events (key, at)")
            cur.execute("DELETE FROM auth_rate_events WHERE at < NOW() - INTERVAL '2 days'")
            # ADMIN_EMAILS est la source de vérité des administrateurs.
            admins = admin_emails()
            # Promotion seulement pour une adresse prouvée (ou quand aucune
            # vérification n'est possible faute d'envoi d'e-mails).
            cur.execute("UPDATE users SET role = 'admin' WHERE email = ANY(%s::text[]) "
                        "AND (email_verified OR %s)",
                        (admins, not email_verification_required()))
            cur.execute("UPDATE users SET role = 'user' "
                        "WHERE role = 'admin' AND NOT (email = ANY(%s::text[]))", (admins,))
    _status_cache.clear()
    if admins:
        logging.info("Administrateurs Amiin : %d adresse(s) configurée(s)", len(admins))
    if email_verification_required() and not mail_configured():
        logging.warning("EMAIL_VERIFICATION=required mais aucun envoi d'e-mails configuré : "
                        "les nouveaux comptes ne pourront pas être vérifiés.")


def _revoke_all(cur, user_id: str) -> None:
    cur.execute(
        "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW(), revoked_reason = 'revoked' "
        "WHERE user_id = %s AND revoked = FALSE",
        (user_id,),
    )
    _session_cache.clear()


# ── Auth dependency ────────────────────────────────────────────────────────────

# État du compte relu en base (désactivé/supprimé, vérifié, rôle), mis en cache
# 60 s par processus : un compte désactivé ou supprimé perd l'accès en 1 min au
# plus, au lieu d'attendre l'expiration du JWT (30 min).
_STATUS_TTL_S = 60
_status_cache: dict = {}
# Base injoignable et rien en cache : on laisse passer (le JWT reste signé et
# valide) plutôt que de couper toute l'application pendant une panne PostgreSQL.
_STATUS_FALLBACK = {"is_active": True, "email_verified": True, "role": "user"}


def invalidate_user_status(user_id: str) -> None:
    _status_cache.pop(user_id, None)


_session_cache: dict = {}


def _session_open(session_id: str) -> bool:
    """La session a-t-elle encore un refresh token valide ? (cache 60 s ;
    base injoignable : dernier état connu, sinon on laisse passer)."""
    now = time.monotonic()
    hit = _session_cache.get(session_id)
    if hit and now - hit[0] < _STATUS_TTL_S:
        return hit[1]
    try:
        with _get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM refresh_tokens WHERE family_id = %s "
                            "AND revoked = FALSE AND expires_at > NOW() LIMIT 1", (session_id,))
                open_ = cur.fetchone() is not None
    except Exception:
        logging.exception("Lecture de la session impossible")
        return hit[1] if hit else True
    _session_cache[session_id] = (now, open_)
    return open_


def _user_status(user_id: str) -> Optional[dict]:
    now = time.monotonic()
    hit = _status_cache.get(user_id)
    if hit and now - hit[0] < _STATUS_TTL_S:
        return hit[1]
    try:
        with _get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT is_active, email_verified, role FROM users WHERE id = %s",
                            (user_id,))
                row = cur.fetchone()
    except Exception:
        logging.exception("Lecture de l'état du compte impossible")
        return hit[1] if hit else _STATUS_FALLBACK
    status_ = dict(row) if row else None
    _status_cache[user_id] = (now, status_)
    return status_


def get_current_user(creds: Optional[HTTPAuthorizationCredentials] = Depends(bearer)) -> dict:
    if not creds:
        raise HTTPException(status_code=401, detail="Authentification requise.")
    payload = _verify_access_token(creds.credentials)
    st = _user_status(payload["sub"])
    if not st or not st.get("is_active"):
        raise HTTPException(status_code=401, detail="Compte désactivé ou supprimé.")
    sid = payload.get("sid")
    if sid and not _session_open(sid):
        raise HTTPException(status_code=401, detail="Session fermée — reconnectez-vous.")
    user = dict(payload)
    user["role"] = st.get("role") or "user"
    user["email_verified"] = _effective_verified(st)
    return user


def is_admin(user: dict) -> bool:
    return user.get("role") == "admin"


def get_verified_user(user: dict = Depends(get_current_user)) -> dict:
    """Pour les fonctions coûteuses (chat, voix) : adresse e-mail vérifiée exigée."""
    if not user.get("email_verified", True):
        raise HTTPException(
            status_code=403,
            detail="Adresse e-mail non vérifiée — saisissez le code reçu par e-mail.",
            headers={"X-Amiin-Error": "email_not_verified"},
        )
    return user


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/register", response_model=TokenResponse, status_code=201)
def register(body: RegisterRequest, request: Request, background: BackgroundTasks):
    _hit(f"register:{_client_ip(request)}", max_calls=20, window_s=3600)
    attest = integrity.check(request, "register", body.email,
                             is_admin_email=body.email in admin_emails())
    pw_hash = hash_password(body.password)
    display = body.display_name or body.email.split("@")[0]
    # Admin d'emblée seulement si aucune vérification n'est exigée ; sinon le
    # rôle est accordé à la saisie du code (verify_email).
    admin = body.email in admin_emails() and not email_verification_required()
    code = None
    try:
        with _get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """INSERT INTO users (email, password_hash, display_name, role, email_verified)
                       VALUES (%s, %s, %s, %s, %s) RETURNING id::text""",
                    (body.email, pw_hash, display, "admin" if admin else "user", admin),
                )
                row = cur.fetchone()
                if not admin and email_verification_required() and mail_configured():
                    code = _issue_verification_code(cur, row["id"])
                    _db_record(cur, f"verify_send_min:{row['id']}")
                    _db_record(cur, f"verify_send:{row['id']}")
            conn.commit()
    except psycopg2.errors.UniqueViolation:
        raise HTTPException(status_code=409, detail="Cet email est déjà utilisé.")

    uid = row["id"]
    if code:
        background.add_task(_send_verification_email, body.email, code)
    return _new_tokens(uid, body.email, request, integrity_status=attest)


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, request: Request):
    _hit(f"login:{_client_ip(request)}", max_calls=30, window_s=60)
    too_many = HTTPException(status_code=429, detail="Trop de tentatives — réessayez dans 15 minutes.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            if _login_failures_exceeded(cur, body.email):
                raise too_many
            cur.execute(
                "SELECT id::text, password_hash, is_active FROM users WHERE email = %s",
                (body.email,),
            )
            row = cur.fetchone()
            ok = bool(row) and verify_password(body.password, row["password_hash"])
            if not ok:
                _db_record(cur, f"login_fail:{body.email}")

    if not ok:
        raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect.")
    if not row["is_active"]:
        raise HTTPException(status_code=403, detail="Compte désactivé.")

    # Après le mot de passe : pas d'appel à Google pour une tentative ratée
    attest = integrity.check(request, "login", body.email,
                             is_admin_email=body.email in admin_emails())
    uid = row["id"]
    return _new_tokens(uid, body.email, request, integrity_status=attest)


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(body: RefreshRequest, request: Request):
    _hit(f"refresh:{_client_ip(request)}", max_calls=60, window_s=60)
    h = _hash_refresh(body.refresh_token)
    now = datetime.now(tz=timezone.utc)

    invalid = HTTPException(status_code=401, detail="Refresh token invalide ou expiré.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT rt.id::text, rt.user_id::text, u.email, rt.revoked, rt.revoked_at,
                          rt.revoked_reason, rt.family_id, rt.device_label,
                          rt.family_started_at, rt.integrity
                   FROM refresh_tokens rt
                   JOIN users u ON u.id = rt.user_id
                   WHERE rt.token_hash = %s
                     AND rt.expires_at > %s
                     AND u.is_active""",
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
                # Une session fermée volontairement (déconnexion, fermeture
                # depuis un autre appareil) n'a pas de délai de grâce.
                revoked_at = row["revoked_at"]
                if row["revoked_reason"] == "revoked":
                    raise invalid
                if revoked_at is None or now - revoked_at > REFRESH_REUSE_GRACE:
                    _revoke_all(cur, row["user_id"])
                    conn.commit()
                    raise invalid
            else:
                # Rotation : on révoque l'ancien et on en émet un nouveau
                cur.execute(
                    "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW(), "
                    "revoked_reason = 'rotated' WHERE id = %s",
                    (row["id"],),
                )
        conn.commit()

    # Même session ; l'app peut mettre à jour le nom de l'appareil.
    device = (_device_label(request) if request.headers.get("x-amiin-device")
              else row["device_label"])
    return _new_tokens(row["user_id"], row["email"], session_id=row["family_id"],
                       device=device, started_at=row["family_started_at"],
                       integrity_status=row["integrity"])


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest):
    """Révoque le refresh token fourni (le client doit aussi supprimer le JWT localement)."""
    h = _hash_refresh(body.refresh_token)
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW(), "
                "revoked_reason = 'revoked' WHERE token_hash = %s AND revoked = FALSE "
                "RETURNING family_id",
                (h,),
            )
            for r in cur.fetchall():
                _session_cache.pop(r["family_id"], None)
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
    # Limite PAR COMPTE (et non par IP : à Djibouti, beaucoup d'abonnés
    # mobiles partagent la même adresse IP).
    uid = current_user["sub"]
    _account_hit(f"delete:{uid}", max_calls=10, window_s=3600)
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
            for table in ("password_reset_codes", "email_verification_codes"):
                cur.execute("SELECT to_regclass(%s) IS NOT NULL AS ok", (table,))
                if cur.fetchone()["ok"]:
                    cur.execute(f"DELETE FROM {table} WHERE user_id = %s", (uid,))
            cur.execute("DELETE FROM refresh_tokens WHERE user_id = %s", (uid,))
            cur.execute("DELETE FROM users WHERE id = %s", (uid,))
    invalidate_user_status(uid)


@router.get("/me", response_model=UserResponse)
def me(current_user: dict = Depends(get_current_user)):
    uid = current_user["sub"]
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(f"SELECT {_USER_COLS} FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return _user_response(row)


_USER_COLS = "id::text, email, display_name, created_at, email_verified, role"


def _user_response(row: dict) -> UserResponse:
    return UserResponse(
        id=row["id"],
        email=row["email"],
        display_name=row["display_name"],
        created_at=row["created_at"].isoformat(),
        email_verified=_effective_verified(row),
        role=row.get("role") or "user",
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
                f"UPDATE users SET display_name = %s WHERE id = %s RETURNING {_USER_COLS}",
                (body.display_name, current_user["sub"]),
            )
            row = cur.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return _user_response(row)


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
    uid = current_user["sub"]
    _account_hit(f"chpw:{uid}", max_calls=10, window_s=3600)
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
    # Toutes les autres sessions sont fermées ; celle de cet appareil repart
    # sous un nouvel identifiant.
    return _new_tokens(uid, row["email"], request)


# ── Mot de passe oublié (code à 6 chiffres par e-mail) ─────────────────────────
# Un code plutôt qu'un lien : pas besoin de page web ni de deep link, l'app
# saisit le code directement. Variables d'environnement : SMTP_HOST,
# SMTP_PORT (587 STARTTLS, 465 SSL), SMTP_USER, SMTP_PASSWORD, SMTP_FROM.

RESET_CODE_TTL     = timedelta(minutes=30)
RESET_MAX_ATTEMPTS = 5


def _hash_code(purpose: str, user_id: str, code: str) -> str:
    # HMAC avec le secret serveur : un dump de la table ne permet pas de
    # retrouver les codes par force brute hors ligne (10^6 possibilités).
    # `purpose` empêche d'utiliser un code de vérification comme code de
    # réinitialisation (et inversement).
    msg = f"{user_id}:{code}" if purpose == "reset" else f"{purpose}:{user_id}:{code}"
    return hmac.new(JWT_SECRET.encode(), msg.encode(), hashlib.sha256).hexdigest()


def _hash_reset_code(user_id: str, code: str) -> str:
    return _hash_code("reset", user_id, code)


def _send_email(to: str, subject: str, body: str) -> None:
    """Envoi d'un e-mail texte : API HTTP Brevo si BREVO_API_KEY est définie
    (fonctionne même là où les ports SMTP sont bloqués), sinon SMTP.
    Appelé en tâche de fond : journalise les échecs sans lever."""
    sender = os.environ["SMTP_FROM"]
    try:
        api_key = os.environ.get("BREVO_API_KEY")
        if api_key:
            name, addr = parseaddr(sender)
            resp = requests.post(
                "https://api.brevo.com/v3/smtp/email",
                headers={"api-key": api_key, "accept": "application/json"},
                json={"sender": {"name": name or "Amiin", "email": addr},
                      "to": [{"email": to}], "subject": subject, "textContent": body},
                timeout=15,
            )
            resp.raise_for_status()
            return
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = sender
        msg["To"] = to
        msg.set_content(body)
        host = os.environ["SMTP_HOST"]
        port = int(os.environ.get("SMTP_PORT", "587"))
        user, password = os.environ.get("SMTP_USER"), os.environ.get("SMTP_PASSWORD")
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
        logging.exception("Envoi d'e-mail impossible (%s)", subject)


def _send_reset_email(to: str, code: str) -> None:
    _send_email(
        to, "Amiin — code de réinitialisation du mot de passe",
        f"Bonjour,\n\nVotre code de réinitialisation Amiin est : {code}\n\n"
        "Il est valable 30 minutes. Si vous n'êtes pas à l'origine de cette "
        "demande, ignorez ce message : votre mot de passe reste inchangé.\n\n— Amiin",
    )


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
    if not mail_configured():
        raise HTTPException(status_code=503,
                            detail="Réinitialisation indisponible pour le moment. Contactez le support.")
    _hit(f"forgot:{_client_ip(request)}", max_calls=10, window_s=3600)
    code = f"{secrets.randbelow(10**6):06d}"
    with _get_conn() as conn:
        with conn.cursor() as cur:
            _db_hit(cur, f"forgot_email:{body.email}", max_calls=3, window_s=3600)
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


# ── Vérification de l'adresse e-mail (code à 6 chiffres) ──────────────────────
# Même principe que la réinitialisation : un code saisi dans l'app, pas de lien.
# Le code part à l'inscription ; l'app peut en redemander un (1 par minute,
# 5 par heure). Tant que l'adresse n'est pas vérifiée, le chat et la voix
# répondent 403 (get_verified_user) ; le reste de l'app reste accessible.

VERIFY_CODE_TTL     = timedelta(minutes=30)
VERIFY_MAX_ATTEMPTS = 5


def _issue_verification_code(cur, user_id: str) -> str:
    code = f"{secrets.randbelow(10**6):06d}"
    cur.execute(
        """INSERT INTO email_verification_codes (user_id, code_hash, expires_at, attempts)
           VALUES (%s, %s, %s, 0)
           ON CONFLICT (user_id) DO UPDATE
           SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at, attempts = 0""",
        (user_id, _hash_code("verify", user_id, code),
         datetime.now(tz=timezone.utc) + VERIFY_CODE_TTL),
    )
    return code


def _send_verification_email(to: str, code: str) -> None:
    _send_email(
        to, f"Amiin — votre code de vérification : {code}",
        f"Bienvenue sur Amiin !\n\nVotre code de vérification est : {code}\n\n"
        "Saisissez-le dans l'application pour activer votre compte. Il est "
        "valable 30 minutes.\n\nSi vous n'avez pas créé de compte Amiin, "
        "ignorez ce message.\n\n— Amiin",
    )


class VerifyEmailRequest(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")


@router.post("/verify-email/send", status_code=202)
def send_verification_code(background: BackgroundTasks,
                           current_user: dict = Depends(get_current_user)):
    if current_user.get("email_verified"):
        return {"detail": "Adresse e-mail déjà vérifiée."}
    if not mail_configured():
        raise HTTPException(status_code=503,
                            detail="Envoi d'e-mails indisponible pour le moment. Contactez le support.")
    uid = current_user["sub"]
    with _get_conn() as conn:
        with conn.cursor() as cur:
            _db_hit(cur, f"verify_send_min:{uid}", max_calls=1, window_s=60,
                    detail="Patientez une minute avant de redemander un code.")
            _db_hit(cur, f"verify_send:{uid}", max_calls=5, window_s=3600,
                    detail="Trop de codes envoyés — réessayez dans une heure.")
            cur.execute("SELECT email FROM users WHERE id = %s", (uid,))
            row = cur.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
            code = _issue_verification_code(cur, uid)
    background.add_task(_send_verification_email, row["email"], code)
    return {"detail": "Un nouveau code vient d'être envoyé."}


@router.post("/verify-email", response_model=UserResponse)
def verify_email(body: VerifyEmailRequest, current_user: dict = Depends(get_current_user)):
    uid = current_user["sub"]
    invalid = HTTPException(status_code=400, detail="Code invalide ou expiré.")
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT code_hash, expires_at, attempts FROM email_verification_codes "
                "WHERE user_id = %s", (uid,))
            code_row = cur.fetchone()
            if (not code_row or code_row["attempts"] >= VERIFY_MAX_ATTEMPTS
                    or code_row["expires_at"] < datetime.now(tz=timezone.utc)):
                raise invalid
            if not hmac.compare_digest(code_row["code_hash"],
                                       _hash_code("verify", uid, body.code)):
                cur.execute("UPDATE email_verification_codes SET attempts = attempts + 1 "
                            "WHERE user_id = %s", (uid,))
                conn.commit()
                raise invalid
            cur.execute(
                f"UPDATE users SET email_verified = TRUE, "
                f"role = CASE WHEN email = ANY(%s::text[]) THEN 'admin' ELSE role END "
                f"WHERE id = %s RETURNING {_USER_COLS}", (admin_emails(), uid))
            row = cur.fetchone()
            cur.execute("DELETE FROM email_verification_codes WHERE user_id = %s", (uid,))
    invalidate_user_status(uid)
    if not row:
        raise HTTPException(status_code=404, detail="Utilisateur introuvable.")
    return _user_response(row)


# ── Appareils connectés ────────────────────────────────────────────────────────

class SessionInfo(BaseModel):
    id: str
    device: str
    started_at: str
    last_active_at: str
    current: bool
    verified: bool = False      # ouverte par l'app officielle (Play Integrity)


@router.get("/sessions", response_model=list)
def list_sessions(current_user: dict = Depends(get_current_user)):
    """Sessions ouvertes du compte (une par appareil), la plus récente d'abord."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT family_id, MAX(device_label) FILTER (WHERE rn = 1) AS device,
                          BOOL_OR(integrity = 'ok') AS verified,
                          MIN(COALESCE(family_started_at, created_at)) AS started_at,
                          MAX(created_at) AS last_active_at
                   FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY family_id
                                                      ORDER BY created_at DESC) AS rn
                         FROM refresh_tokens
                         WHERE user_id = %s AND revoked = FALSE AND expires_at > NOW()) t
                   GROUP BY family_id
                   ORDER BY MAX(created_at) DESC""",
                (current_user["sub"],),
            )
            rows = cur.fetchall()
    sid = current_user.get("sid")
    return [
        SessionInfo(id=r["family_id"], device=r["device"] or "Appareil inconnu",
                    started_at=r["started_at"].isoformat(),
                    last_active_at=r["last_active_at"].isoformat(),
                    current=r["family_id"] == sid,
                    verified=bool(r["verified"])).model_dump()
        for r in rows
    ]


@router.delete("/sessions/{session_id}", status_code=204)
def revoke_session(session_id: str, current_user: dict = Depends(get_current_user)):
    """Ferme la session d'un appareil : il est déconnecté au plus tard en 1 min."""
    with _get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE refresh_tokens SET revoked = TRUE, revoked_at = NOW(), "
                "revoked_reason = 'revoked' "
                "WHERE user_id = %s AND family_id = %s AND revoked = FALSE",
                (current_user["sub"], session_id),
            )
            if cur.rowcount == 0:
                raise HTTPException(status_code=404, detail="Session introuvable.")
    _session_cache.pop(session_id, None)
