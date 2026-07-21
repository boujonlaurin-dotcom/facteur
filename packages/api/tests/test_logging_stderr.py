"""Garde-fou : structlog écrit sur stderr, pas stdout.

Incident worker 2026-06-30 : ~3 semaines de silence côté Railway. Cause du
trou d'observabilité : structlog écrivait sur le stdout par défaut, block-buffered
en conteneur, tandis que Railway ne remonte de façon fiable que stderr
(uvicorn/alembic). Ce test verrouille le routage stderr (couplé à
`PYTHONUNBUFFERED=1` dans le Dockerfile) pour éviter une régression silencieuse.
"""

import sys

import structlog

import app.main  # noqa: F401  — applique structlog.configure() au import


def test_structlog_logger_factory_targets_stderr():
    factory = structlog.get_config()["logger_factory"]
    assert isinstance(factory, structlog.PrintLoggerFactory)
    # Le fix concret : cible stderr (et surtout PAS le stdout par défaut).
    assert factory._file is not sys.stdout
    assert factory._file is sys.stderr
