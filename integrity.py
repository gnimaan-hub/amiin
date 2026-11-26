# -*- coding: utf-8 -*-
"""
integrity.py — Vérification Google Play Integrity (API « Standard »).

But : s'assurer qu'une inscription ou une connexion vient de la VRAIE app
Amiin, installée depuis le Play Store, sur un appareil Android intègre — et
non d'un script ou d'une app modifiée qui créerait des comptes en masse pour
consommer le quota gratuit.

Déroulé :
  1. L'app demande un jeton à Google Play, lié à une empreinte de la requête
     (« register:adresse » ou « login:adresse », hachée en SHA-256).
  2. Elle l'envoie dans l'en-tête X-Amiin-Integrity.
  3. Le serveur fait déchiffrer le jeton par l'API Google (compte de service)
     et vérifie : bon paquet, empreinte identique, jeton récent (< 5 min),
     app reconnue par Play, appareil intègre.

On ne vérifie qu'à l'inscription et à la connexion (pas à chaque message) :
la session ouverte reste ensuite valable. Le quota gratuit Google
(~10 000 vérifications/jour) suffit donc largement.

Variables d'environnement :
  INTEGRITY_MODE           off (défaut) | report (vérifie et journalise, ne bloque
                           pas) | enforce (refuse inscription/connexion sans
                           attestation valide). Commencer par report.
  PLAY_INTEGRITY_SA_JSON   contenu JSON de la clé du compte de service Google
                           Cloud ayant le rôle d'accès à Play Integrity (secret).
  PLAY_INTEGRITY_PACKAGE   nom du paquet (défaut dj.amiin.app).
Les adresses de ADMIN_EMAILS ne sont jamais bloquées (accès depuis le web ou
un émulateur pour l'administration).
"""

import hashlib
import json
import logging
import os
import threading
import time
from typing import Optional

import requests
from fastapi import HTTPException, Request

MAX_AGE_S = 300
_SCOPE = "https://www.googleapis.com/auth/playintegrity"
_creds = None
_creds_lock = threading.Lock()


def mode() -> str:
    m = os.environ.get("INTEGRITY_MODE", "off").strip().lower()
    return m if m in ("off", "report", "enforce") else "off"


def package_name() -> str:
    return os.environ.get("PLAY_INTEGRITY_PACKAGE", "dj.amiin.app")


def request_hash(action: str, email: str) -> str:
    """Empreinte calculée à l'identique par l'app (MainActivity.kt)."""
    return hashlib.sha256(f"{action}:{email.strip().lower()}".encode()).hexdigest()


def evaluate(payload: dict, action: str, email: str, now_ms: Optional[int] = None) -> list:
    """Problèmes relevés dans un verdict déchiffré ; liste vide = attestation valide."""
    problems = []
    now_ms = now_ms if now_ms is not None else int(time.time() * 1000)
    req = payload.get("requestDetails") or {}
    if req.get("requestPackageName") != package_name():
        problems.append("paquet")
    if req.get("requestHash") != request_hash(action, email):
        problems.append("empreinte")
    try:
        age_ms = now_ms - int(req.get("timestampMillis", 0))
    except (TypeError, ValueError):
        age_ms = MAX_AGE_S * 1000 + 1
    if not 0 <= age_ms <= MAX_AGE_S * 1000:
        problems.append("jeton_perime")
    app = payload.get("appIntegrity") or {}
    if app.get("appRecognitionVerdict") != "PLAY_RECOGNIZED":
        problems.append("app_non_reconnue")
    device = (payload.get("deviceIntegrity") or {}).get("deviceRecognitionVerdict") or []
    if "MEETS_DEVICE_INTEGRITY" not in device:
        problems.append("appareil_non_integre")
    return problems


def _access_token() -> str:
    """Jeton OAuth du compte de service (mis en cache, renouvelé au besoin)."""
    global _creds
    from google.auth.transport.requests import Request as GoogleRequest
    from google.oauth2 import service_account
    with _creds_lock:
        if _creds is None:
            info = json.loads(os.environ["PLAY_INTEGRITY_SA_JSON"])
            _creds = service_account.Credentials.from_service_account_info(info, scopes=[_SCOPE])
        if not _creds.valid:
            _creds.refresh(GoogleRequest())
        return _creds.token


def decode(token: str) -> dict:
    """Fait déchiffrer le jeton par Google ; retourne le verdict (tokenPayloadExternal)."""
    resp = requests.post(
        f"https://playintegrity.googleapis.com/v1/{package_name()}:decodeIntegrityToken",
        headers={"Authorization": f"Bearer {_access_token()}"},
        json={"integrity_token": token},
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json().get("tokenPayloadExternal") or {}


INTEGRITY_REQUIRED_DETAIL = ("Pour votre sécurité, Amiin doit être installée depuis le Google Play "
                             "Store sur un appareil non modifié. Mettez l'application à jour puis "
                             "réessayez.")


def check(request: Request, action: str, email: str, is_admin_email: bool = False) -> str:
    """Contrôle d'une inscription ou d'une connexion. Retourne un statut court
    ('ok', 'absent', 'refuse:<raisons>', 'erreur', 'off'), journalisé et
    rattaché à la session. En mode enforce, lève 403 si l'attestation manque
    ou échoue (sauf adresse admin)."""
    m = mode()
    if m == "off":
        return "off"
    token = request.headers.get("x-amiin-integrity", "").strip()
    if not token:
        status = "absent"
    else:
        try:
            problems = evaluate(decode(token), action, email)
            status = "ok" if not problems else "refuse:" + ",".join(problems)
        except Exception:
            # Google injoignable ou clé mal configurée : on ne bloque pas les
            # utilisateurs pour une panne de notre côté.
            logging.exception("Play Integrity : vérification impossible")
            return "erreur"
    logging.info("Play Integrity [%s] %s : %s", m, action, status)
    if m == "enforce" and status != "ok" and not is_admin_email:
        raise HTTPException(status_code=403, detail=INTEGRITY_REQUIRED_DETAIL,
                            headers={"X-Amiin-Error": "integrity_required"})
    return status
