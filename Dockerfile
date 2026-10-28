FROM python:3.10-slim

WORKDIR /app

# Copier et installer les dépendances en premier (cache Docker)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier le code source
COPY amiin_api.py auth.py ./
# Catalogue des démarches : même fichier que l'app, injecté dans le prompt système
COPY amiin_app_flutter/assets/data/demarches_catalog.json ./amiin_app_flutter/assets/data/

# Render injecte $PORT — uvicorn le lit via la variable d'environnement
CMD ["sh", "-c", "uvicorn amiin_api:app --host 0.0.0.0 --port ${PORT:-8000}"]
