# -*- coding: utf-8 -*-
"""Fixtures communes : importe l'API sans démarrer le lifespan (pas d'appel à
Qdrant, Jina, Anthropic ni PostgreSQL)."""

import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-pour-pytest-uniquement-32o")


@pytest.fixture(scope="session")
def api():
    import amiin_api
    return amiin_api


@pytest.fixture
def client(api):
    """TestClient authentifié en tant que l'utilisateur « u1 »."""
    from fastapi.testclient import TestClient
    api.app.dependency_overrides[api.get_current_user] = lambda: {"sub": "u1"}
    yield TestClient(api.app)
    api.app.dependency_overrides.clear()
