# Simulation de campagne (comptes de test)

Fait tourner le **vrai serveur Amiin** (`amiin_api.app`) avec une base PostgreSQL
locale neuve, un serveur SMTP local (les codes de vérification sont réellement
envoyés, en STARTTLS) et un **faux Claude** (`fake_anthropic.py`) qui répond au
format exact de l'API et compte les tokens d'après la taille réelle des
requêtes d'Amiin. Aucune clé, aucun coût. Qdrant et Jina, non joignables, sont
remplacés par une recherche vide (`run_server.py`).

```bash
# Prérequis : PostgreSQL local (rôle amiin/amiin superutilisateur),
#   pip install -r requirements.txt -r requirements-dev.txt aiosmtpd
PY=python3 tests/simulation/simulate.sh 20 0.02     # 20 comptes, quota 0,02 $/jour
```

Chaque compte : inscription → chat refusé avant vérification → code lu dans la
boîte locale → vérification → conversation en français (questions, notes,
démarches, tâches en plusieurs passes) jusqu'au blocage par le quota →
contrôles (jauge, 402, sessions) → suppression du compte. Résultats détaillés
dans `results.json` (dossier `$WORK`, temporaire par défaut).

Fichiers : `fake_anthropic.py`, `smtp_sink.py`, `run_server.py`,
`run_campaign.py`, `simulate.sh`. Les noms ne commencent pas par `test_` :
pytest ne les collecte pas.
