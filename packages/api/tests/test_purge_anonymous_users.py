"""Purge des sessions anonymes abandonnées (story 31.1).

La sélection tape `auth.users`, absent du schéma de test (créé par `create_all`
sur les modèles applicatifs) : on teste donc l'orchestration du job avec une
session et une Admin API simulées, pas le SQL lui-même.
"""

from contextlib import asynccontextmanager
from types import SimpleNamespace

import pytest

from app.jobs import purge_anonymous_users as job_module

# Les ids repartent en `UUID(...)` pour le DELETE des profils : pas de slug.
_ANON_IDS = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222",
]


class _FakeResult:
    def __init__(self, rows):
        self._rows = rows

    def fetchall(self):
        return self._rows


@pytest.fixture
def patch_session(monkeypatch):
    """Fait remonter `candidates` à la requête de sélection du job."""

    def _install(candidates: list[str]):
        executed = {"statements": [], "params": None, "commits": 0}

        class _FakeSession:
            async def execute(self, statement, params=None):
                executed["statements"].append(statement)
                if params is not None:
                    executed["params"] = params
                return _FakeResult([(uid,) for uid in candidates])

            async def commit(self):
                executed["commits"] += 1

        @asynccontextmanager
        async def _maker():
            yield _FakeSession()

        monkeypatch.setattr(job_module, "safe_async_session", _maker)
        return executed

    return _install


@pytest.fixture
def patch_settings(monkeypatch):
    def _install(url: str = "https://project.supabase.co", key: str = "service-key"):
        monkeypatch.setattr(
            job_module,
            "get_settings",
            lambda: SimpleNamespace(supabase_url=url, supabase_service_role_key=key),
        )

    return _install


@pytest.fixture
def patch_admin_api(monkeypatch):
    """Remplace l'appel Admin API ; renvoie la liste des ids supprimés."""

    def _install(status_by_user: dict[str, int] | None = None):
        deleted: list[str] = []

        class _FakeClient:
            async def __aenter__(self):
                return self

            async def __aexit__(self, *args):
                return False

            async def delete(self, url, headers=None):
                user_id = url.rsplit("/", 1)[-1]
                code = (status_by_user or {}).get(user_id, 204)
                if code in (200, 204, 404):
                    deleted.append(user_id)
                return SimpleNamespace(status_code=code)

        monkeypatch.setattr(job_module.httpx, "AsyncClient", lambda **_: _FakeClient())
        return deleted

    return _install


@pytest.mark.asyncio
async def test_purge_deletes_each_candidate_and_its_profile(
    patch_session, patch_settings, patch_admin_api
):
    patch_settings()
    executed = patch_session(_ANON_IDS)
    deleted = patch_admin_api()

    stats = await job_module.purge_anonymous_users()

    assert deleted == _ANON_IDS
    assert stats == {"candidates": 2, "deleted_count": 2, "skipped_reason": None}
    assert executed["params"]["days"] == job_module.PURGE_AFTER_DAYS
    assert executed["params"]["limit"] == job_module.MAX_DELETIONS_PER_RUN
    # Sélection + DELETE des profils applicatifs (CASCADE fait le reste).
    assert len(executed["statements"]) == 2
    assert executed["commits"] == 1


@pytest.mark.asyncio
async def test_purge_counts_only_successful_deletions(
    patch_session, patch_settings, patch_admin_api
):
    """Un échec Admin API ne doit pas être compté comme une suppression."""
    patch_settings()
    patch_session(_ANON_IDS)
    patch_admin_api({_ANON_IDS[1]: 500})

    stats = await job_module.purge_anonymous_users()

    assert stats["candidates"] == 2
    assert stats["deleted_count"] == 1


@pytest.mark.asyncio
async def test_purge_leaves_profiles_alone_when_nothing_was_deleted(
    patch_session, patch_settings, patch_admin_api
):
    """Auth non supprimé ⇒ profil conservé, jamais orphelin."""
    patch_settings()
    executed = patch_session(_ANON_IDS)
    patch_admin_api(dict.fromkeys(_ANON_IDS, 500))

    stats = await job_module.purge_anonymous_users()

    assert stats["deleted_count"] == 0
    assert len(executed["statements"]) == 1
    assert executed["commits"] == 0


@pytest.mark.asyncio
async def test_purge_is_a_noop_without_admin_credentials(patch_settings):
    patch_settings(key="")

    stats = await job_module.purge_anonymous_users()

    assert stats["deleted_count"] == 0
    assert stats["skipped_reason"] == "missing_admin_credentials"
