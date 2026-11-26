#!/usr/bin/env bash
# Campagne de simulation Amiin : vrai serveur + PostgreSQL local + SMTP local
# + faux Claude. Usage : tests/simulation/simulate.sh [nb_comptes] [quota_usd]
# Prérequis : PostgreSQL local, python avec requirements(-dev) + aiosmtpd.
# Variables : PY (interpréteur), PGADMIN (commande psql superutilisateur).
set -euo pipefail
cd "$(dirname "$0")"
ACCOUNTS="${1:-20}"; QUOTA="${2:-0.02}"
PY="${PY:-python3}"
WORK="${WORK:-$(mktemp -d)}"; mkdir -p "$WORK"
DB="postgresql://amiin:amiin@127.0.0.1/amiin_sim"
export NO_PROXY="127.0.0.1,localhost" no_proxy="127.0.0.1,localhost"

# Base neuve (schéma de départ des tables créées à la main en production)
${PGADMIN:-psql postgresql://amiin:amiin@127.0.0.1/postgres} -q -c "DROP DATABASE IF EXISTS amiin_sim" -c "CREATE DATABASE amiin_sim OWNER amiin"
"$PY" - "$DB" <<'PYEOF'
import sys, psycopg2
sys.path.insert(0, "..")
from test_auth_db import _BASE_SCHEMA
with psycopg2.connect(sys.argv[1]) as c, c.cursor() as cur:
    cur.execute(_BASE_SCHEMA)
PYEOF

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=127.0.0.1" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
rm -f "$WORK"/mailbox.jsonl "$WORK"/calls.jsonl

"$PY" fake_anthropic.py --port 8765 --log "$WORK/calls.jsonl" > "$WORK/fake.log" 2>&1 &
P1=$!
"$PY" smtp_sink.py --port 2525 --mailbox "$WORK/mailbox.jsonl" --cert "$WORK/cert.pem" --key "$WORK/key.pem" > "$WORK/smtp.log" 2>&1 &
P2=$!
DATABASE_URL="$DB" JWT_SECRET_KEY="simulation-$(openssl rand -hex 16)" \
ANTHROPIC_API_KEY="sk-ant-simulation" ANTHROPIC_BASE_URL="http://127.0.0.1:8765" \
SMTP_HOST=127.0.0.1 SMTP_PORT=2525 SMTP_FROM="Amiin <no-reply@amiin-test.dj>" \
QUOTA_DAILY_USD="$QUOTA" ADMIN_EMAILS="" PORT=8000 \
"$PY" run_server.py > "$WORK/server.log" 2>&1 &
P3=$!
trap 'kill $P1 $P2 $P3 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  curl -s -o /dev/null http://127.0.0.1:8000/v1/chat/health && break; sleep 0.5
done

"$PY" run_campaign.py --api http://127.0.0.1:8000/v1 --mailbox "$WORK/mailbox.jsonl" \
  --db "$DB" --fake-log "$WORK/calls.jsonl" --accounts "$ACCOUNTS" --quota "$QUOTA" \
  --out "$WORK/results.json"
# La suppression de compte est limitée à 10 par heure et par IP (en mémoire) :
# toute la campagne venant de 127.0.0.1, on redémarre le serveur pour finir.
kill $P3; wait $P3 2>/dev/null || true
DATABASE_URL="$DB" JWT_SECRET_KEY="simulation-$(openssl rand -hex 16)" \
ANTHROPIC_API_KEY="sk-ant-simulation" ANTHROPIC_BASE_URL="http://127.0.0.1:8765" \
SMTP_HOST=127.0.0.1 SMTP_PORT=2525 SMTP_FROM="Amiin <no-reply@amiin-test.dj>" \
QUOTA_DAILY_USD="$QUOTA" ADMIN_EMAILS="" PORT=8000 \
"$PY" run_server.py >> "$WORK/server.log" 2>&1 &
P3=$!
for i in $(seq 1 60); do
  curl -s -o /dev/null http://127.0.0.1:8000/v1/chat/health && break; sleep 0.5
done
"$PY" run_campaign.py --api http://127.0.0.1:8000/v1 --mailbox "$WORK/mailbox.jsonl" \
  --db "$DB" --fake-log "$WORK/calls.jsonl" --out "$WORK/results.json" --cleanup
echo "Résultats : $WORK/results.json — journaux : $WORK/*.log"
