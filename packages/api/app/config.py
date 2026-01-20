"""Configuration de l'application via variables d'environnement."""

from functools import lru_cache
from typing import Literal, Any
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import os
from dotenv import load_dotenv
from pathlib import Path


# Force load .env from the package directory to avoid shadowing by external env vars
load_dotenv(Path(__file__).parent.parent / ".env", override=True)


class Settings(BaseSettings):
    """Configuration de l'application."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Application
    app_name: str = "Facteur API"
    app_version: str = "1.0.0"
    environment: Literal["development", "staging", "production"] = "development"
    debug: bool = True

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Database (Supabase PostgreSQL)
    database_url: str = "postgresql+psycopg://postgres:postgres@localhost:54322/postgres"

    @field_validator("database_url", mode="before")
    @classmethod
    def fix_database_url(cls, v: Any) -> Any:
        """Transforme postgres:// ou postgresql:// en postgresql+psycopg://"""
        if isinstance(v, str):
            # Remove any existing driver suffix first
            if "+asyncpg" in v:
                v = v.replace("+asyncpg", "+psycopg")
            elif v.startswith("postgres://"):
                v = v.replace("postgres://", "postgresql+psycopg://", 1)
            elif v.startswith("postgresql://") and "+psycopg" not in v:
                v = v.replace("postgresql://", "postgresql+psycopg://", 1)
            
            # Ensure sslmode=require is present if not already (important for Railway/Supabase pooling)
            # But only append if query params don't already exist or if sslmode is missing
            if "?" not in v:
                v += "?sslmode=require"
            elif "sslmode=" not in v:
                v += "&sslmode=require"
                
        return v


    # Supabase
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str = ""
    supabase_jwt_secret: str = ""

    # RevenueCat
    revenuecat_api_key: str = ""
    revenuecat_webhook_secret: str = ""

    # RSS Sync
    rss_sync_interval_minutes: int = 30
    rss_sync_enabled: bool = True

    # CORS
    cors_origins: list[str] = ["*"]

    # Sentry
    sentry_dsn: str = ""

    # ML Classification (Story 4.1d)
    ml_enabled: bool = False  # Set to True to load CamemBERT model

    @model_validator(mode="after")
    def validate_production_db(self) -> "Settings":
        """Empêche l'utilisation de localhost en production."""
        if self.is_production and "localhost" in self.database_url:
            raise ValueError(
                f"❌ CRITICAL ERROR: DATABASE_URL points to localhost in production ({self.database_url}). "
                "Check your environment variables on Railway."
            )
        return self

    @property
    def is_production(self) -> bool:
        """Vérifie si on est en production."""
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    """Retourne les settings (cached)."""
    # Diagnostic: Log all environment variable keys (NOT values)
    print(f"🛠️ Diagnostic: Available environment variables: {sorted(list(os.environ.keys()))}", flush=True)
    return Settings()

