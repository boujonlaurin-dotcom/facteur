"""Configuration de l'application via variables d'environnement."""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


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

    @property
    def is_production(self) -> bool:
        """Vérifie si on est en production."""
        return self.environment == "production"


@lru_cache
def get_settings() -> Settings:
    """Retourne les settings (cached)."""
    return Settings()

