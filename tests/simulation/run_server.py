# -*- coding: utf-8 -*-
"""
Lance le VRAI serveur Amiin (amiin_api.app) pour la simulation :
  - base PostgreSQL locale, envoi d'e-mails par SMTP local, quotas actifs ;
  - le SDK Anthropic parle au faux serveur (ANTHROPIC_BASE_URL) ;
  - seules la recherche vectorielle (Qdrant) et les embeddings (Jina), non
    joignables ici, sont remplacés : aucun document trouvé, et des tokens
    Jina comptés d'après la longueur du texte (pour la mesure du coût).
Variables attendues : DATABASE_URL, ANTHROPIC_BASE_URL, SMTP_*, QUOTA_DAILY_USD…
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
os.chdir(ROOT)

import uvicorn                     # noqa: E402
import amiin_api                   # noqa: E402
from anthropic import Anthropic, AsyncAnthropic   # noqa: E402


def _fake_load_components():
    key = os.environ["ANTHROPIC_API_KEY"]
    amiin_api.claude_client = Anthropic(api_key=key)
    amiin_api.async_claude = AsyncAnthropic(api_key=key)


amiin_api.load_components = _fake_load_components
amiin_api._jina_embed_batch = lambda texts, task="retrieval.query": (
    [[0.0] * amiin_api.JINA_EMBED_DIM for _ in texts], sum(max(1, len(t) // 4) for t in texts))
amiin_api._search_with_embedding = lambda *a, **k: []

if __name__ == "__main__":
    uvicorn.run(amiin_api.app, host="127.0.0.1", port=int(os.environ.get("PORT", "8000")),
                log_level="warning")
