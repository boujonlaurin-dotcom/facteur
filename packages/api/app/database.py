"""Configuration de la base de données avec SQLAlchemy async."""

import time

from sqlalchemy import event, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import AsyncAdaptedQueuePool, NullPool

from app.config import get_settings
from app.middleware.request_context import (
    current_request_method,
    current_request_path,
)

settings = get_settings()

# Engine async
# Diagnostic: Print engine target with port info for troubleshooting
from urllib.parse import urlparse

import structlog

logger = structlog.get_logger()
_db_parsed = urlparse(settings.database_url) if settings.database_url else None
logger.info(
    "engine_initializing",
    host=_db_parsed.hostname if _db_parsed else "NONE",
    port=_db_parsed.port if _db_parsed else "NONE",
    database=_db_parsed.path.lstrip("/") if _db_parsed else "NONE",
    driver=settings.database_url.split("://")[0] if settings.database_url else "NONE",
)

# Determine pool configuration based on environment
# Railway/Supabase: Use QueuePool with pre_ping for connection resilience
# Local dev: Can use NullPool for simplicity
_is_railway = "railway" in (settings.database_url or "").lower()
_is_supabase = "supabase" in (settings.database_url or "").lower()
_use_queue_pool = _is_railway or _is_supabase

# Exposé pour les tests : capacité prod et fail-fast timeout. Toute modif ici
# impacte la pression sur le Supabase Pooler (60 conn partagées).
PROD_POOL_KWARGS = {
    "pool_size": 25,
    "max_overflow": 25,
    "pool_timeout": 10,
    "pool_recycle": 180,
}

if _use_queue_pool:
    # Railway/Supabase: Use AsyncAdaptedQueuePool for proper connection pooling
    # This handles connection drops better than NullPool
    logger.info("db_pool_config", pool_type="AsyncAdaptedQueuePool", pre_ping=True)
    engine = create_async_engine(
        settings.database_url,
        echo=settings.debug,
        # Enable pool_pre_ping to verify connections before use
        # This prevents "SSL connection has been closed unexpectedly" errors
        pool_pre_ping=True,
        # Use AsyncAdaptedQueuePool for proper connection management
        poolclass=AsyncAdaptedQueuePool,
        # Supabase Pooler 60 connection limit shared. App: 25+25=50 max →
        # ~16 concurrent feed requests (~3 conns/req). Margin 10 left for the
        # in-process scheduler. pool_timeout=10s : fail fast for visibility
        # instead of 30s silent stalls. pool_recycle=180s : Supabase PgBouncer
        # idle timeout is ~5 min, recycle before that.
        **PROD_POOL_KWARGS,
        # Connect args for PgBouncer compatibility
        connect_args={
            "prepare_threshold": None,  # Disable prepared statements for PgBouncer transaction mode
            "connect_timeout": 10,  # Fail fast if DB host/port unreachable (prevents indefinite hang)
            # Round 2 fix (docs/bugs/bug-infinite-load-requests.md item 6) :
            # statement_timeout côté Postgres — si une requête tourne plus de
            # 30 s, Postgres la tue et renvoie une erreur au client. C'est
            # notre dernier rempart quand (a) un driver async coincé,
            # (b) un `await` qui ne revient pas, ou (c) un scénario
            # rare où le middleware request-budget ne peut pas annuler
            # la task parce qu'elle est bloquée sur un I/O bas niveau.
            # Note libpq syntax : "-c statement_timeout=30000" (millisecondes).
            "options": "-c statement_timeout=30000",
        },
    )
else:
    # Local development: Use NullPool for simplicity
    logger.info("db_pool_config", pool_type="NullPool", pre_ping=False)
    engine = create_async_engine(
        settings.database_url,
        echo=settings.debug,
        pool_pre_ping=False,
        poolclass=NullPool,
        connect_args={
            "prepare_threshold": None,
        },
    )


# Pool observability: log connections held longer than 10 seconds.
# Helps detect session leaks that cause pool exhaustion.
_LONG_CHECKOUT_THRESHOLD_S = 10.0


def _maybe_log_long_checkout(connection_record) -> None:
    checkout_time = getattr(connection_record, "_checkout_time", None)
    if checkout_time is None:
        return
    duration = time.monotonic() - checkout_time
    if duration > _LONG_CHECKOUT_THRESHOLD_S:
        logger.warning(
            "long_session_checkout",
            duration_s=round(duration, 1),
            endpoint=current_request_path.get("unknown"),
            method=current_request_method.get("unknown"),
        )
    connection_record._checkout_time = None


if _use_queue_pool:

    @event.listens_for(engine.sync_engine, "checkout")
    def _on_checkout(dbapi_conn, connection_record, connection_proxy):
        connection_record._checkout_time = time.monotonic()

    @event.listens_for(engine.sync_engine, "checkin")
    def _on_checkin(dbapi_conn, connection_record):
        _maybe_log_long_checkout(connection_record)


# Session factory
async_session_maker = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


# Round 3 fix (docs/bugs/bug-infinite-load-requests.md — Sentry PYTHON-4/5/6) :
# Supabase/PgBouncer tue parfois des connexions de façon asynchrone et renvoie
# des erreurs qui ne sont PAS automatiquement classées comme "disconnect" par
# SQLAlchemy. Résultat : le slot reste dans le pool en état invalid, toutes
# les requêtes suivantes lèvent PendingRollbackError, le pool se remplit de
# zombies, QueuePool limit reached → "infinite loading".
#
# Ce listener force `is_disconnect=True` sur les signatures Supabase-spécifiques
# pour que SQLAlchemy évacue le slot et en crée un neuf à la prochaine demande.
_DISCONNECT_SIGNATURES = (
    "server closed the connection",
    "dbhandler exited",
    "consuming input failed",
    "connection reset by peer",
    "connection is closed",
    "ssl connection has been closed",
    "terminating connection",
)


if _use_queue_pool:

    @event.listens_for(engine.sync_engine, "handle_error")
    def _invalidate_on_supabase_kill(exception_context):
        exc = exception_context.original_exception
        if exc is None:
            return
        msg = str(exc).lower()
        matched = next((s for s in _DISCONNECT_SIGNATURES if s in msg), None)
        if matched is None:
            return
        # Force SQLAlchemy à marquer la connexion morte → évacuée du pool.
        exception_context.is_disconnect = True
        logger.warning(
            "db_connection_invalidated_by_signature",
            signature=matched,
            exc_type=type(exc).__name__,
        )


class Base(DeclarativeBase):
    """Base class pour les modèles SQLAlchemy."""

    pass


async def init_db() -> None:
    """Initialise la connexion à la base de données."""
    # Log connection target (safely) with port info
    target_url = engine.url.render_as_string(hide_password=True)
    db_host = engine.url.host
    db_port = engine.url.port
    logger.info("db_connection_check", target=target_url, host=db_host, port=db_port)

    # En production, les tables sont gérées via Supabase
    # Cette fonction vérifie juste que la connexion fonctionne
    try:
        import asyncio
        import socket

        # Diagnostic DNS préventif — exécuté dans un thread pour ne pas
        # bloquer l'event loop. socket.gethostbyname() est synchrone et
        # peut prendre 5-30s sur Railway ; si on l'appelle directement dans
        # une coroutine, uvicorn ne peut plus servir /api/health → healthcheck
        # timeout. Cf. docs/bugs/bug-infinite-load-requests.md.
        loop = asyncio.get_event_loop()
        try:
            if db_host:
                resolved_ip = await asyncio.wait_for(
                    loop.run_in_executor(None, socket.gethostbyname, db_host),
                    timeout=5.0,
                )
                logger.info("db_dns_resolved", host=db_host, ip=resolved_ip)
        except (TimeoutError, socket.gaierror) as dns_err:
            logger.error(
                "db_dns_error",
                host=db_host,
                port=db_port,
                error=str(dns_err),
                hint="Check your DATABASE_URL on Railway.",
            )

        # Diagnostic TCP préventif — même raison : exécuté dans un thread.
        def _tcp_check() -> None:
            sock = socket.create_connection((db_host, db_port), timeout=5)
            sock.close()

        try:
            if db_host and db_port:
                await asyncio.wait_for(
                    loop.run_in_executor(None, _tcp_check),
                    timeout=6.0,
                )
                logger.info("db_tcp_reachable", host=db_host, port=db_port)
        except (TimeoutError, ConnectionRefusedError, OSError) as tcp_err:
            logger.error(
                "db_tcp_unreachable",
                host=db_host,
                port=db_port,
                error=str(tcp_err),
                hint="Port might be wrong. Supabase uses 6543 (transaction) or 5432 (session).",
            )

        async with engine.begin() as conn:
            # Test connection
            await conn.execute(text("SELECT 1"))
        logger.info("db_connection_successful", host=db_host, port=db_port)
    except Exception as e:
        logger.error(
            "db_connection_failed",
            error=str(e),
            host=db_host,
            port=db_port,
            target=target_url,
        )
        raise


async def close_db() -> None:
    """Ferme la connexion à la base de données."""
    await engine.dispose()


async def get_db() -> AsyncSession:
    """Dependency pour obtenir une session de base de données.

    Uses ``except BaseException`` (not ``Exception``) so that
    ``asyncio.CancelledError`` — a ``BaseException`` since Python 3.9 —
    also triggers a rollback.  Without this, a cancelled handler skips
    the rollback branch and relies solely on ``finally`` to close the
    session.  If ``close()`` itself is interrupted the connection leaks
    into an "idle in transaction" state, gradually filling the pool.

    Round 3 hardening : rollback et close sont wrappés en try/except pour que
    l'échec d'un cleanup (sur connexion déjà morte) ne masque pas l'exception
    originale du handler. Sinon Starlette/Sentry capturent une cascade confuse
    de PendingRollbackError au lieu de la vraie cause.
    """
    async with async_session_maker() as session:
        try:
            yield session
            await session.commit()
        except BaseException:
            try:
                await session.rollback()
            except Exception as rollback_exc:
                logger.debug(
                    "get_db_rollback_failed",
                    error=str(rollback_exc),
                    exc_type=type(rollback_exc).__name__,
                )
            raise
        finally:
            try:
                await session.close()
            except Exception as close_exc:
                logger.debug(
                    "get_db_close_failed",
                    error=str(close_exc),
                    exc_type=type(close_exc).__name__,
                )
