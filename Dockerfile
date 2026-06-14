FROM python:3.10-slim

WORKDIR /app

# Copier et installer les dépendances en premier (cache Docker)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copier le code source
COPY amiin_api.py .

# Render injecte $PORT — uvicorn le lit via la variable d'environnement
CMD ["sh", "-c", "uvicorn amiin_api:app --host 0.0.0.0 --port ${PORT:-8000}"]
