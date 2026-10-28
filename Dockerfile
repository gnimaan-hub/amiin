FROM python:3.12-slim

WORKDIR /app

# Copier et installer les dépendances en premier (cache Docker)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier le code source
COPY amiin_api.py auth.py ./
# Catalogue des démarches : même fichier que l'app, injecté dans le prompt système
COPY amiin_app_flutter/assets/data/demarches_catalog.json ./amiin_app_flutter/assets/data/

# Utilisateur non privilégié (l'app écrit seulement amiin_requests.log dans /app)
RUN useradd --create-home --uid 10001 amiin && chown -R amiin /app
USER amiin

# Render injecte $PORT — uvicorn le lit via la variable d'environnement
CMD ["sh", "-c", "uvicorn amiin_api:app --host 0.0.0.0 --port ${PORT:-8000}"]
