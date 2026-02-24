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
        extra="ignore",  # Ignore extra env vars like TRANSFORMERS_CACHE
    )

    # Application
    app_name: str = "Facteur API"
    app_version: str = "1.0.0"
    environment: Literal["development", "staging", "production"] = "development"
    debug: bool = False

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

    # RSS Retention
    rss_retention_days: int = 20

    @field_validator("rss_retention_days")
    @classmethod
    def validate_rss_retention_days(cls, v: int) -> int:
        """Empêche des valeurs négatives qui causeraient une suppression totale."""
        if v < 0:
            raise ValueError(
                "rss_retention_days must be a non-negative integer (got {v}). "
                "Negative values would delete ALL data instead of old data."
            )
        return v

    # CORS
    cors_origins: list[str] = ["*"]

    # Sentry
    sentry_dsn: str = ""

    # ML Classification (Story 4.1d)
    ml_enabled: bool = False  # Set to True to load CamemBERT model

    # Startup Checks
    skip_startup_checks: bool = False  # Set to True to skip migration checks (CI/Tests)

    # App Update (GitHub Releases)
    github_token: str = ""  # Personal access token with repo read scope
    github_repo: str = "boujonlaurin-dotcom/facteur"  # owner/repo

    @model_validator(mode="after")
    def auto_detect_railway_environment(self) -> "Settings":
        """Auto-detect Railway environment from RAILWAY_ENVIRONMENT_NAME."""
        railway_env = os.environ.get("RAILWAY_ENVIRONMENT_NAME", "")
        if railway_env:
            if railway_env.lower() == "staging":
                object.__setattr__(self, 'environment', 'staging')
            elif self.environment == "development":
                object.__setattr__(self, 'environment', 'production')
        return self

    @model_validator(mode="after")
    def validate_deployed_db(self) -> "Settings":
        """Empêche l'utilisation de localhost en production/staging."""
        if self.environment in ("production", "staging") and not os.environ.get("DATABASE_URL"):
            raise ValueError(
                f"DATABASE_URL is missing in {self.environment}. "
                "Set DATABASE_URL in Railway."
            )
        if self.environment in ("production", "staging") and "localhost" in self.database_url:
            raise ValueError(
                f"DATABASE_URL points to localhost in {self.environment}. "
                "Check your environment variables on Railway."
            )
        return self

    @property
    def is_production(self) -> bool:
        """Vérifie si on est en production."""
        return self.environment == "production"

    @property
    def is_staging(self) -> bool:
        """Vérifie si on est en staging."""
        return self.environment == "staging"


@lru_cache
def get_settings() -> Settings:
    """Retourne les settings (cached)."""
    return Settings()

