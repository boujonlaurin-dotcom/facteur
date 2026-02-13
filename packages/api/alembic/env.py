import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy import text
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config, create_async_engine

from alembic import context

# Load environment variables from .env
import os
from urllib.parse import urlparse
from dotenv import load_dotenv
load_dotenv()

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Get DATABASE_URL from .env and convert for async psycopg
database_url = os.getenv("DATABASE_URL")

# For migrations, use MIGRATION_DATABASE_URL if explicitly set.
# Otherwise, auto-switch Supabase pooler from transaction mode (port 6543)
# to session mode (port 5432). Transaction-mode pooling breaks DDL because
# the pooler can reassign server connections between statements, preventing
# ALTER TABLE from acquiring ACCESS EXCLUSIVE locks. Session mode dedicates
# a server connection for the entire session, allowing DDL to work correctly.
_migration_override = os.getenv("MIGRATION_DATABASE_URL")
if _migration_override:
    database_url = _migration_override
    print(f"[alembic] Using MIGRATION_DATABASE_URL for migrations")
elif database_url and ":6543" in database_url:
    database_url = database_url.replace(":6543", ":5432")
    print(f"[alembic] Switched Supabase pooler from transaction mode (:6543) to session mode (:5432)")

# Convert postgresql:// or postgres:// to postgresql+psycopg:// for async engine
if database_url:
    if "+asyncpg" in database_url:
        database_url = database_url.replace("+asyncpg", "+psycopg")
    elif database_url.startswith("postgres://"):
        database_url = database_url.replace("postgres://", "postgresql+psycopg://", 1)
    elif database_url.startswith("postgresql://") and "+psycopg" not in database_url:
        database_url = database_url.replace("postgresql://", "postgresql+psycopg://", 1)

# Connection args for migrations - critical for Supabase PgBouncer compatibility
# These options are passed to PostgreSQL at connection time, bypassing PgBouncer's
# session-level timeout limitations
MIGRATION_CONNECT_ARGS = {
    "prepare_threshold": None,  # Disable prepared statements (required for PgBouncer transaction mode)
    # Pass timeout options directly to PostgreSQL server via connection options
    # 10 min statement timeout, 2 min lock timeout
    "options": "-c statement_timeout=600000 -c lock_timeout=120000",
}

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# add your model's MetaData object here
# for 'autogenerate' support
from app.database import Base
# Import all models to register them with Base.metadata
from app.models import *  # noqa

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = database_url or config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        # SET LOCAL within the transaction — guaranteed to work with PgBouncer/Supavisor
        # because the same backend connection is used for the entire transaction.
        # The connection-level "options" parameter may be ignored by Supavisor.
        connection.execute(text("SET LOCAL statement_timeout = '0'"))
        connection.execute(text("SET LOCAL lock_timeout = '120s'"))
        context.run_migrations()


async def run_async_migrations() -> None:
    """In this scenario we need to create an Engine
    and associate a connection with the context.
    
    Uses MIGRATION_CONNECT_ARGS to ensure proper timeout settings
    that work with Supabase PgBouncer transaction pooling.
    """
    if database_url:
        connectable = create_async_engine(
            database_url,
            poolclass=pool.NullPool,
            connect_args=MIGRATION_CONNECT_ARGS,
        )
    else:
        connectable = async_engine_from_config(
            config.get_section(config.config_ini_section, {}),
            prefix="sqlalchemy.",
            poolclass=pool.NullPool,
        )

    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)

    await connectable.dispose()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
