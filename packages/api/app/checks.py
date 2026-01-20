import structlog
from alembic.config import Config
from alembic import script
from alembic.runtime import migration
from sqlalchemy.ext.asyncio import AsyncConnection
from app.database import engine

logger = structlog.get_logger()

def _get_current_revision_sync(connection: AsyncConnection):
    """Sync function to get current revision from DB context."""
    context = migration.MigrationContext.configure(connection)
    return context.get_current_revision()

async def check_migrations_up_to_date():
    """
    Checks if the database is up-to-date with Alembic migrations.
    Raises RuntimeError if there are pending migrations.
    """
    logger.info("startup_check_migrations_start")
    
    # 1. Get HEAD revision from code (alembic.ini)
    try:
        # Assuming alembic.ini is in the current working directory (packages/api)
        alembic_cfg = Config("alembic.ini")
        script_directory = script.ScriptDirectory.from_config(alembic_cfg)
        heads = script_directory.get_heads()
        head_rev = heads[0] if heads else None
    except Exception as e:
        logger.error("startup_check_migrations_failed_config", error=str(e))
        # If we can't read config, we probably shouldn't start either, but strictly
        # speaking this check failed.
        raise RuntimeError(f"Could not load Alembic configuration: {e}")

    # 2. Get CURRENT revision from Database
    try:
        async with engine.connect() as conn:
            current_rev = await conn.run_sync(_get_current_revision_sync)
    except Exception as e:
        logger.error("startup_check_migrations_failed_db", error=str(e))
        # DB might be down, let init_db handle that or raise here
        raise RuntimeError(f"Could not fetch database revision: {e}")

    logger.info("startup_check_migrations_result", head=head_rev, current=current_rev)

    # 3. Compare
    if head_rev != current_rev:
        error_msg = f"Pending migrations detected! Code head: {head_rev}, DB current: {current_rev}. Run 'alembic upgrade head'."
        logger.critical("startup_check_migrations_mismatch", error=error_msg)
        raise RuntimeError(error_msg)
    
    logger.info("startup_check_migrations_ok")
