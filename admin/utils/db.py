"""Connexion synchrone à la BDD pour le dashboard Streamlit."""

import os
from functools import lru_cache

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

load_dotenv()


@lru_cache(maxsize=1)
def get_engine():
    """Crée un engine sync SQLAlchemy depuis DATABASE_URL.

    Convertit le driver async psycopg vers psycopg2 (sync).
    Compatible PgBouncer (prepare_threshold=None).
    """
    url = os.environ.get("DATABASE_URL", "")
    if not url:
        raise RuntimeError("DATABASE_URL manquant. Définir dans .env ou en variable d'environnement.")

    # Adapter le driver async → sync
    if "+psycopg://" in url:
        url = url.replace("+psycopg://", "+psycopg2://")
    elif "+asyncpg://" in url:
        url = url.replace("+asyncpg://", "+psycopg2://")
    elif url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+psycopg2://", 1)
    elif url.startswith("postgresql://") and "+psycopg2" not in url:
        url = url.replace("postgresql://", "postgresql+psycopg2://", 1)

    # Assurer sslmode=require
    if "?" not in url:
        url += "?sslmode=require"
    elif "sslmode=" not in url:
        url += "&sslmode=require"

    return create_engine(
        url,
        pool_pre_ping=True,
        pool_size=3,
        max_overflow=2,
        pool_recycle=180,
        connect_args={
            "prepare_threshold": None,  # PgBouncer transaction mode
        },
    )


def get_connection():
    """Retourne une connexion sync pour exécuter du SQL brut."""
    return get_engine().connect()


def run_query(sql: str, params: dict | None = None) -> list[dict]:
    """Exécute une requête SQL et retourne les résultats en list[dict]."""
    with get_connection() as conn:
        result = conn.execute(text(sql), params or {})
        columns = list(result.keys())
        return [dict(zip(columns, row)) for row in result.fetchall()]
