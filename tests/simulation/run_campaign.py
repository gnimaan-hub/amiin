# -*- coding: utf-8 -*-
"""
Campagne de test « 20 comptes » contre le serveur Amiin lancé par run_server.py.
Chaque compte suit le parcours de l'app, en français, sans voix :
  inscription → chat refusé avant vérification → code reçu par e-mail (SMTP
  local) → vérification → conversation (questions, notes, démarches, tâches
  en plusieurs passes) jusqu'au blocage par le quota → contrôles → suppression.
Les comptes sont joués l'un après l'autre (« en chaîne »).

Résultats : results.json (détail) — le rapport est rédigé à partir de ce fichier.
Usage : python run_campaign.py --api http://127.0.0.1:8000/v1 --mailbox mailbox.jsonl \
          --db postgresql://... --fake-log calls.jsonl --accounts 20
"""
import argparse
import json
import re
import time
import uuid
from datetime import datetime

import psycopg2
import requests
from psycopg2.extras import RealDictCursor

PASSWORD = "Simulation-2026!"
DEVICE = {"X-Amiin-Device": "Simulation"}

# Messages joués en boucle (décalés selon le compte pour varier les parcours)
SCRIPT = [
    ("salutation", "Bonjour Amiin"),
    ("question", "Comment obtenir un certificat de résidence à Djibouti ?"),
    ("note", "Crée une note : déposer le dossier de certificat de résidence lundi à la mairie"),
    ("question", "Quelle est la durée légale du travail à Djibouti et comment sont payées les heures supplémentaires ?"),
    ("démarche", "Je veux suivre la démarche egouv_103 pour mon passeport, ajoute-la"),
    ("lecture", "Quelles sont mes notes ?"),
    ("détail", "Quels documents faut-il pour le passeport ? Donne-moi le détail"),
    ("question", "Comment créer une SARL à Djibouti, quelles sont les étapes et les coûts ?"),
    ("note", "Note que je dois renouveler ma carte d'identité avant la fin de l'année"),
    ("lecture", "Rappelle-moi mes notes"),
]
READ_TOOLS = {"get_events", "get_notes", "get_demarche_detail"}


class AppUser:
    """État local de l'app pour un compte (notes, démarches, historique, mémoire)."""

    def __init__(self, api, idx, run_id):
        self.api = api
        self.idx = idx
        self.email = f"sim{idx:02d}.{run_id}@amiin-test.dj"
        self.name = f"Testeur {idx:02d}"
        self.headers = dict(DEVICE)
        self.notes, self.demarches, self.history, self.actions = [], [], [], []
        self.log = []

    # ── HTTP ────────────────────────────────────────────────────────────────
    def post(self, path, **kw):
        return requests.post(self.api + path, headers={**self.headers, **kw.pop("headers", {})},
                             timeout=60, **kw)

    def get(self, path):
        return requests.get(self.api + path, headers=self.headers, timeout=30)

    def auth(self, token):
        self.headers["Authorization"] = f"Bearer {token}"

    # ── Chat, comme chat_controller.dart ────────────────────────────────────
    def _context(self):
        return {"now": datetime.now().isoformat(),
                "profile": {"display_name": self.name, "employment": "employee",
                            "favorite_topics": ["démarches", "droit du travail"]},
                "recent_actions": [{"date": a[0], "summary": a[1]} for a in self.actions[-8:]]}

    def _stream(self, body):
        r = self.post("/chat/stream", json=body, stream=True)
        if r.status_code != 200:
            return r.status_code, "", None
        text, done = [], None
        for line in r.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data: "):
                continue
            ev = json.loads(line[6:])
            if ev["type"] == "token":
                text.append(ev["text"])
            elif ev["type"] == "done":
                done = ev
            elif ev["type"] == "error":
                return 500, "".join(text), None
        return 200, "".join(text), done

    def _run_read_tool(self, tc):
        name, inp = tc["name"], tc.get("input") or {}
        if name == "get_notes":
            content = json.dumps([{"id": n["id"], "title": n["title"], "content": n["content"]}
                                  for n in self.notes], ensure_ascii=False)
        elif name == "get_demarche_detail":
            content = json.dumps({"id": inp.get("demarche_id"), "titre": "Passeport",
                                  "pieces": ["Acte de naissance", "Carte d'identité", "2 photos"],
                                  "etapes": ["Dépôt du dossier", "Paiement", "Retrait"]},
                                 ensure_ascii=False)
        else:
            content = "[]"
        return {"tool_use_id": tc["id"], "content": content}

    def send(self, kind, message):
        """Un message utilisateur, avec jusqu'à 3 passes d'outils. Retourne un résumé."""
        history = [{"role": h[0], "content": h[1][:12000]} for h in self.history[-10:]]
        body = {"message": message, "history": history, "client_context": self._context(),
                "expand": True,
                "user_preferences": {"tone": "neutral", "response_length": "balanced",
                                     "expertise_level": "standard", "ai_language": "fr",
                                     "show_sources": False, "currency": "DJF"}}
        reply, passes, tools_used = "", 0, []
        for _ in range(3):
            status, text, done = self._stream(body)
            if status != 200:
                return {"kind": kind, "status": status, "passes": passes, "tools": tools_used}
            passes += 1
            reply += text
            calls = (done or {}).get("tool_calls") or []
            tools_used += [c["name"] for c in calls]
            for c in calls:                        # actions exécutées par l'app
                if c["name"] == "create_note":
                    self.notes.append({"id": str(uuid.uuid4()), **c["input"]})
                    self.actions.append((datetime.now().isoformat(), "Note : " + c["input"]["title"]))
                elif c["name"] == "start_demarche":
                    self.demarches.append(c["input"]["demarche_id"])
                    self.actions.append((datetime.now().isoformat(),
                                         "Démarche suivie : " + c["input"]["demarche_id"]))
            reads = [c for c in calls if c["name"] in READ_TOOLS]
            if not reads:
                break
            body = {**body, "pending_tool_uses": reads,
                    "tool_results": [self._run_read_tool(c) for c in reads]}
        self.history += [("user", message), ("assistant", reply)]
        return {"kind": kind, "status": 200, "passes": passes, "tools": tools_used,
                "reply_chars": len(reply)}


def wait_mail(path, email, after_ts, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        try:
            with open(path, encoding="utf-8") as f:
                for line in f:
                    m = json.loads(line)
                    if email in m["to"] and m["ts"] >= after_ts:
                        return m
        except FileNotFoundError:
            pass
        time.sleep(0.2)
    return None


def db_query(db, sql, args=()):
    with psycopg2.connect(db, cursor_factory=RealDictCursor) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return cur.fetchall() if cur.description else None


def used_usd(db, uid):
    rows = db_query(db, "SELECT COALESCE(SUM(cost_micro_usd),0) AS s, COUNT(*) AS n "
                        "FROM usage_events WHERE user_id = %s", (uid,))
    return float(rows[0]["s"]) / 1e6, rows[0]["n"]


def wait_events(db, uid, n_expected, timeout=5):
    """L'usage est écrit juste après chaque requête (hors boucle) : on attend
    une ligne par passe (une tâche en 2 passes = 2 requêtes = 2 lignes)."""
    end = time.time() + timeout
    while time.time() < end:
        cost, n = used_usd(db, uid)
        if n >= n_expected:
            return cost, n
        time.sleep(0.05)
    return used_usd(db, uid)


def run_account(args, idx, run_id):
    u = AppUser(args.api, idx, run_id)
    res = {"idx": idx, "email": u.email, "checks": {}, "messages": []}
    chk = res["checks"]

    t0 = time.time()
    r = u.post("/auth/register", json={"email": u.email, "password": PASSWORD,
                                       "display_name": u.name})
    chk["inscription_201"] = r.status_code == 201
    u.auth(r.json()["access_token"])
    me = u.get("/auth/me").json()
    res["user_id"] = uid = me["id"]
    chk["non_verifie_apres_inscription"] = me["email_verified"] is False

    # Chat refusé tant que l'adresse n'est pas vérifiée
    chk["chat_refuse_403_avant_verif"] = u.post("/chat/stream", json={"message": "Bonjour"}).status_code == 403

    mail = wait_mail(args.mailbox, u.email, t0 - 1)
    chk["email_code_recu"] = mail is not None
    res["email_delai_s"] = round(mail["ts"] - t0, 2) if mail else None
    chk["email_par_starttls"] = bool(mail and mail["tls"])
    code = re.search(r"\b(\d{6})\b", mail["body"]).group(1) if mail else "000000"
    chk["code_dans_objet"] = bool(mail and code in mail["subject"])

    if idx % 5 == 0:                              # un compte sur 5 se trompe d'abord
        wrong = "111111" if code != "111111" else "222222"
        chk["mauvais_code_refuse_400"] = u.post("/auth/verify-email", json={"code": wrong}).status_code == 400
    r = u.post("/auth/verify-email", json={"code": code})
    chk["verification_ok"] = r.status_code == 200 and r.json()["email_verified"] is True

    usage0 = u.get("/me/usage").json()
    chk["jauge_initiale_0"] = usage0["percent"] == 0 and not usage0["exhausted"]

    # Conversation jusqu'au blocage
    n_events, last_cost, blocked = 0, 0.0, False
    for k in range(args.max_messages):
        kind, text = SCRIPT[(k + idx) % len(SCRIPT)]
        out = u.send(kind, text)
        if out["status"] == 402:
            blocked = True
            out["cout_usd"] = 0
            res["messages"].append(out)
            break
        cost, n_events = wait_events(args.db, uid, n_events + out["passes"])
        out["cout_usd"] = round(cost - last_cost, 6)
        out["cumul_usd"] = round(cost, 6)
        last_cost = cost
        res["messages"].append(out)
        if out["status"] != 200:
            break

    total, n = used_usd(args.db, uid)
    usage = u.get("/me/usage").json()
    res.update(total_usd=round(total, 6), evenements=n, notes=len(u.notes),
               demarches=len(u.demarches), jauge=usage)
    ok_msgs = [m for m in res["messages"] if m["status"] == 200]
    chk["bloque_par_quota_402"] = blocked
    chk["quota_atteint_avant_blocage"] = total >= args.quota
    chk["depassement_max_1_message"] = (total - args.quota) <= max(
        [m["cout_usd"] for m in ok_msgs] or [0]) + 1e-9
    chk["jauge_coherente_100"] = usage["exhausted"] and usage["percent"] == 100
    chk["chat_non_stream_aussi_402"] = u.post("/chat", json={"message": "Encore une question"}).status_code == 402
    chk["dictee_402"] = u.post("/stt").status_code == 402
    chk["notes_creees"] = len(u.notes) > 0 or not any(m["kind"] == "note" for m in ok_msgs)
    # Tâche en plusieurs passes interrompue par le quota (1re passe faite, suite refusée)
    chk["aucune_tache_coupee_en_cours"] = not any(
        m["status"] == 402 and m["passes"] > 0 for m in res["messages"])
    chk["demarche_suivie"] = len(u.demarches) > 0 or not any(m["kind"] == "démarche" for m in ok_msgs)
    sessions = u.get("/auth/sessions").json()
    chk["session_appareil_listee"] = (len(sessions) == 1 and sessions[0]["current"]
                                      and sessions[0]["device"] == "Simulation")
    return u, res


def cleanup(args):
    """Supprime (connexion + « Supprimer le compte ») les comptes de la
    campagne encore présents en base, puis vérifie qu'il ne reste rien."""
    data = json.load(open(args.out, encoding="utf-8"))
    emails = [r["email"] for r in data["comptes"]]
    present = {r["email"] for r in db_query(args.db, "SELECT email FROM users WHERE email = ANY(%s)", (emails,))}
    codes = []
    for email in sorted(present):
        r = requests.post(args.api + "/auth/login", json={"email": email, "password": PASSWORD},
                          headers=DEVICE, timeout=30)
        h = {"Authorization": f"Bearer {r.json()['access_token']}"}
        codes.append(requests.delete(args.api + "/auth/me", json={"password": PASSWORD},
                                     headers=h, timeout=30).status_code)
    uids = [r["user_id"] for r in data["comptes"]]
    left = {t: db_query(args.db, f"SELECT COUNT(*) AS n FROM {t} WHERE user_id::text = ANY(%s)",
                        (uids,))[0]["n"]
            for t in ("refresh_tokens", "email_verification_codes", "usage_events")}
    left["users"] = db_query(args.db, "SELECT COUNT(*) AS n FROM users WHERE email = ANY(%s)",
                             (emails,))[0]["n"]
    data["resume"]["nettoyage"] = {"restants_avant": len(present),
                                   "suppressions": {str(c): codes.count(c) for c in set(codes)},
                                   "lignes_restantes_apres": left}
    json.dump(data, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps(data["resume"]["nettoyage"], ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", default="http://127.0.0.1:8000/v1")
    ap.add_argument("--mailbox", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--fake-log", required=True)
    ap.add_argument("--accounts", type=int, default=20)
    ap.add_argument("--quota", type=float, default=0.02)
    ap.add_argument("--max-messages", type=int, default=60)
    ap.add_argument("--out", default="results.json")
    ap.add_argument("--cleanup", action="store_true",
                    help="supprimer les comptes restants d'une campagne (lit --out)")
    args = ap.parse_args()
    if args.cleanup:
        return cleanup(args)

    run_id = uuid.uuid4().hex[:6]
    started = time.time()
    users, results = [], []
    for i in range(1, args.accounts + 1):
        u, res = run_account(args, i, run_id)
        users.append(u)
        results.append(res)
        bad = [k for k, v in res["checks"].items() if not v]
        print(f"compte {i:02d} : {len(res['messages'])} messages, {res['total_usd']:.4f} $"
              f" — {'OK' if not bad else 'ÉCHECS : ' + ', '.join(bad)}", flush=True)

    # Rapprochement : coût enregistré par Amiin vs consommation vue par le faux Claude
    uids = [r["user_id"] for r in results]
    db_total = sum(r["total_usd"] for r in results)
    calls = [json.loads(l) for l in open(args.fake_log, encoding="utf-8")]

    # Suppression des comptes par l'API (parcours « Supprimer le compte »)
    deletions = []
    for u in users:
        r = requests.delete(args.api + "/auth/me", json={"password": PASSWORD},
                            headers=u.headers, timeout=30)
        deletions.append(r.status_code)
    left = {t: db_query(args.db, f"SELECT COUNT(*) AS n FROM {t} WHERE user_id::text = ANY(%s)",
                        (uids,))[0]["n"]
            for t in ("refresh_tokens", "email_verification_codes", "usage_events")}
    left["users"] = db_query(args.db, "SELECT COUNT(*) AS n FROM users WHERE id::text = ANY(%s)",
                             (uids,))[0]["n"]
    after = [requests.get(args.api + "/auth/me", headers=u.headers, timeout=30).status_code
             for u in users]

    summary = {"run_id": run_id, "duree_s": round(time.time() - started, 1),
               "comptes": len(results), "quota_usd": args.quota,
               "total_usd_enregistre": round(db_total, 6),
               "appels_claude": len(calls),
               "suppressions": {str(c): deletions.count(c) for c in set(deletions)},
               "apres_suppression_me": after, "lignes_restantes": left}
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"resume": summary, "comptes": results, "appels_claude": calls}, f,
                  ensure_ascii=False, indent=1)
    print(json.dumps(summary, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
