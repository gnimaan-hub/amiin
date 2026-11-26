# -*- coding: utf-8 -*-
"""
Serveur SMTP local qui reçoit les e-mails d'Amiin (codes de vérification,
mot de passe oublié) et les écrit dans une boîte JSONL. STARTTLS activé avec un
certificat auto-signé : c'est le chemin exact du code d'envoi d'auth.py.
Lancement : python smtp_sink.py --port 2525 --mailbox mailbox.jsonl --cert c.pem --key k.pem
"""
import argparse
import json
import ssl
import time
from email import message_from_bytes, policy

from aiosmtpd.controller import Controller


class Sink:
    def __init__(self, path):
        self.path = path

    async def handle_DATA(self, server, session, envelope):
        msg = message_from_bytes(envelope.content, policy=policy.default)
        body = msg.get_body(preferencelist=("plain",))
        entry = {"ts": time.time(), "from": envelope.mail_from, "to": envelope.rcpt_tos,
                 "subject": str(msg["subject"]), "body": body.get_content() if body else "",
                 "tls": bool(session.ssl)}
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        return "250 OK"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=2525)
    ap.add_argument("--mailbox", default="mailbox.jsonl")
    ap.add_argument("--cert", required=True)
    ap.add_argument("--key", required=True)
    a = ap.parse_args()
    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ctx.load_cert_chain(a.cert, a.key)
    c = Controller(Sink(a.mailbox), hostname="127.0.0.1", port=a.port,
                   tls_context=ctx, require_starttls=True)
    c.start()
    print(f"SMTP local sur 127.0.0.1:{a.port}", flush=True)
    try:
        while True:
            time.sleep(3600)
    finally:
        c.stop()
