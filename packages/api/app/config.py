"""Configuration de l'application via variables d'environnement."""

from functools import lru_cache
from typing import Literal, Any
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import os


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
    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:54322/postgres"

    @field_validator("database_url", mode="before")
    @classmethod
    def fix_database_url(cls, v: Any) -> Any:
        """Transforme postgres:// ou postgresql:// en postgresql+asyncpg://"""
        if isinstance(v, str):
            if v.startswith("postgres://"):
                return v.replace("postgres://", "postgresql+asyncpg://", 1)
            elif v.startswith("postgresql://") and "+asyncpg" not in v:
                return v.replace("postgresql://", "postgresql+asyncpg://", 1)
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

