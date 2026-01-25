import structlog
import os
from alembic.config import Config
from alembic import script
from alembic.runtime import migration
from sqlalchemy.ext.asyncio import AsyncConnection
from app.database import engine

logger = structlog.get_logger()

# Compute absolute path to alembic.ini relative to this file's location
# checks.py is in packages/api/app/, alembic.ini is in packages/api/
_ALEMBIC_INI_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "alembic.ini")

# Environment variable to bypass migration check during migration rollout
# Set FACTEUR_MIGRATION_IN_PROGRESS=1 to allow app to start while migrations are being applied
# WARNING: Only use this temporarily during migration deployments
MIGRATION_BYPASS_ENV = "FACTEUR_MIGRATION_IN_PROGRESS"

def _get_current_revision_sync(connection: AsyncConnection):
    """Sync function to get current revision from DB context."""
    context = migration.MigrationContext.configure(connection)
    return context.get_current_revision()

async def check_migrations_up_to_date():
    """
    Checks if the database is up-to-date with Alembic migrations.
    
    Behavior:
    - Config errors (alembic.ini not found): WARNING, continue startup
    - DB connection errors: WARNING, continue startup
    - Migration mismatch (pending migrations): CRITICAL, crash (data integrity risk)
    - FACTEUR_MIGRATION_IN_PROGRESS=1: WARNING, continue (for migration rollout)
    """
    logger.info("startup_check_migrations_start")
    
    # Check for bypass flag (used during migration rollout)
    if os.getenv(MIGRATION_BYPASS_ENV) == "1":
        logger.warning(
            "startup_migration_check_bypassed",
            reason=f"{MIGRATION_BYPASS_ENV}=1",
            action="App will start without migration validation. Remove flag after migrations complete."
        )
        return  # Continue boot without migration check
    
    # 1. Get HEAD revision from code (alembic.ini)
    try:
        alembic_cfg = Config(_ALEMBIC_INI_PATH)
        script_directory = script.ScriptDirectory.from_config(alembic_cfg)
        heads = script_directory.get_heads()
        head_rev = heads[0] if heads else None
    except Exception as e:
        # G2: Non-essential config errors should warn, not crash
        logger.warning("startup_check_migrations_skipped_config", error=str(e))
        return  # Continue boot without migration check

    # 2. Get CURRENT revision from Database
    try:
        async with engine.connect() as conn:
            current_rev = await conn.run_sync(_get_current_revision_sync)
    except Exception as e:
        # G2: DB transient errors should warn, not crash (DB might just be slow)
        logger.warning("startup_check_migrations_skipped_db", error=str(e))
        return  # Continue boot without migration check

    logger.info("startup_check_migrations_result", head=head_rev, current=current_rev)

    # 3. Compare - THIS is fatal because running with wrong schema is dangerous
    if head_rev != current_rev:
        error_msg = f"Pending migrations detected! Code head: {head_rev}, DB current: {current_rev}. Run 'alembic upgrade head'."
        logger.critical("startup_check_migrations_mismatch", error=error_msg)
        raise RuntimeError(error_msg)
    
    logger.info("startup_check_migrations_ok")
