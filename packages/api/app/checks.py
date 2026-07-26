import os
from functools import lru_cache

import structlog
from alembic.config import Config
from alembic.runtime import migration
from sqlalchemy.ext.asyncio import AsyncConnection

from alembic import script
from app.database import engine

logger = structlog.get_logger()

# Compute absolute path to alembic.ini relative to this file's location
# checks.py is in packages/api/app/, alembic.ini is in packages/api/
_ALEMBIC_INI_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "alembic.ini"
)

# Environment variable to bypass migration check during migration rollout
# Set FACTEUR_MIGRATION_IN_PROGRESS=1 to allow app to start while migrations are being applied
# WARNING: Only use this temporarily during migration deployments
MIGRATION_BYPASS_ENV = "FACTEUR_MIGRATION_IN_PROGRESS"


class MultipleAlembicHeadsError(RuntimeError):
    """Le code embarque plusieurs heads Alembic — l'image est cassée.

    Deux PRs mergées le même jour depuis la même base sans révision de merge
    suffisent (incident du 25/07/2026). ``alembic upgrade head`` n'a alors plus
    de cible : le boot Railway démarre l'app quand même et l'ORM mappe des
    colonnes jamais créées → 500 sur tout le trafic authentifié. Prendre
    ``heads[0]`` masquait la panne : selon l'ordre retourné, le contrôle de
    démarrage et la sonde readiness pouvaient passer au vert.
    """


def _single_head(script_directory: "script.ScriptDirectory") -> str | None:
    """Head unique du code, ou ``MultipleAlembicHeadsError`` s'il y en a plusieurs."""
    heads = script_directory.get_heads()
    if len(heads) > 1:
        raise MultipleAlembicHeadsError(f"Multiple Alembic heads: {heads}")
    return heads[0] if heads else None


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

    # Check for bypass flag (used during migration rollout or CI)
    if (
        os.getenv(MIGRATION_BYPASS_ENV) == "1"
        or os.getenv("SKIP_STARTUP_CHECKS") == "True"
    ):
        logger.warning(
            "startup_migration_check_bypassed",
            reason="Bypass flag detected",
            action="App will start without migration validation.",
        )
        return  # Continue boot without migration check

    # Auto-skip if no DATABASE_URL is set (avoids crash during basic Docker boot tests)
    from app.config import get_settings

    settings = get_settings()
    if not os.environ.get("DATABASE_URL") and not settings.is_production:
        logger.warning(
            "startup_migration_check_skipped_no_db",
            reason="DATABASE_URL not set in non-production",
        )
        return

    # 1. Get HEAD revision from code (alembic.ini)
    try:
        alembic_cfg = Config(_ALEMBIC_INI_PATH)
        script_directory = script.ScriptDirectory.from_config(alembic_cfg)
        head_rev = _single_head(script_directory)
    except MultipleAlembicHeadsError as e:
        # Fatal, comme un schéma en retard : l'image ne peut pas migrer.
        logger.critical("startup_check_migrations_multiple_heads", error=str(e))
        raise
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


@lru_cache(maxsize=1)
def _code_head_and_ancestors() -> tuple[str | None, frozenset[str]]:
    """Code-side head revision + the full set of its ancestors (incl. head).

    Derived only from the Alembic script files bundled in this image, so it is
    static per process — memoised. Raises on config error, ou
    ``MultipleAlembicHeadsError`` si l'image embarque un fork (caller catches).
    """
    alembic_cfg = Config(_ALEMBIC_INI_PATH)
    script_directory = script.ScriptDirectory.from_config(alembic_cfg)
    head_rev = _single_head(script_directory)
    if head_rev is None:
        return None, frozenset()
    ancestors = frozenset(
        rev.revision for rev in script_directory.iterate_revisions(head_rev, "base")
    )
    return head_rev, ancestors


async def get_migration_readiness() -> dict[str, str | bool | None]:
    """Direction-aware migration drift status for the readiness probe.

    Returns ``{"behind": bool, "head": str|None, "current": str|None}``.

    ``behind=True`` **only** when the DB current revision is a *strict ancestor*
    of the code head — i.e. migrations this deployed image expects have not been
    applied yet (the "pending migrations" failure mode that makes every query on
    the new schema 500). A drifted container should then be pulled out of the
    load balancer.

    ``behind=False`` when ``current == head`` (fine) **or** when ``current`` is
    *ahead of* / unrelated to the code head. The latter is the normal
    expand-contract window: the prod backend runs last week's code (old head) on
    a shared DB whose ``current`` has already been advanced by staging — 503-ing
    prod then would cause an outage, so we must stay ready. Any config/DB error
    also returns ``behind=False`` (fail-open — never take traffic down because
    this check itself hiccuped).
    """
    try:
        head_rev, ancestors = _code_head_and_ancestors()
    except MultipleAlembicHeadsError as e:
        # Pas un hoquet : l'image ne peut pas migrer, son schéma attendu est
        # indéterminé. Le fail-open ne s'applique pas — on sort du LB.
        logger.critical("readiness_migration_multiple_heads", error=str(e))
        return {"behind": True, "head": None, "current": None}
    except Exception as e:
        logger.warning("readiness_migration_check_config_error", error=str(e))
        return {"behind": False, "head": None, "current": None}

    try:
        async with engine.connect() as conn:
            current_rev = await conn.run_sync(_get_current_revision_sync)
    except Exception as e:
        logger.warning("readiness_migration_check_db_error", error=str(e))
        return {"behind": False, "head": head_rev, "current": None}

    if head_rev is None or current_rev == head_rev:
        return {"behind": False, "head": head_rev, "current": current_rev}

    # DB is behind code iff its current revision is a *strict* ancestor of head.
    # (current ahead of / unrelated to head → not in `ancestors` → stays ready.)
    behind = current_rev in ancestors and current_rev != head_rev
    return {"behind": behind, "head": head_rev, "current": current_rev}
