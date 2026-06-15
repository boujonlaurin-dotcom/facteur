"""Tests du budget mensuel persistant (gouvernance coût scaling, PR-S3)."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.observability import cost_budget


@pytest.fixture(autouse=True)
def _clear_cache():
    cost_budget.invalidate_cache()
    yield
    cost_budget.invalidate_cache()


def _session_returning(scalar_value):
    session = MagicMock()
    result = MagicMock()
    result.scalar_one.return_value = scalar_value
    session.execute = AsyncMock(return_value=result)
    maker = MagicMock()
    maker.return_value.__aenter__ = AsyncMock(return_value=session)
    maker.return_value.__aexit__ = AsyncMock(return_value=False)
    return maker, session


@pytest.mark.asyncio
async def test_monthly_call_count_queries_and_caches():
    maker, session = _session_returning(42)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        first = await cost_budget.monthly_call_count("brave")
        second = await cost_budget.monthly_call_count("brave")
    assert first == 42
    assert second == 42  # 2e appel servi par le cache
    session.execute.assert_awaited_once()  # une seule requête DB


@pytest.mark.asyncio
async def test_call_site_scoped_count_is_cached_separately():
    """Le cap recherche doit compter SON call site, pas tout le provider :
    `mistral` couvre aussi classif/éditorial. Compteurs en cache distincts."""
    maker, session = _session_returning(7)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        provider_wide = await cost_budget.monthly_call_count("mistral")
        scoped = await cost_budget.monthly_call_count(
            "mistral", call_site="smart_search_mistral"
        )
    assert provider_wide == 7
    assert scoped == 7
    # 2 requêtes DB distinctes (clés de cache différentes), pas un seul hit
    assert session.execute.await_count == 2
    assert "mistral" in cost_budget._cache
    assert "mistral:smart_search_mistral" in cost_budget._cache


@pytest.mark.asyncio
async def test_is_over_cap_accepts_call_site():
    maker, _ = _session_returning(2000)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        assert (
            await cost_budget.is_over_cap(
                "mistral", 2000, call_site="smart_search_mistral"
            )
            is True
        )


@pytest.mark.asyncio
async def test_monthly_call_count_force_refresh_bypasses_cache():
    maker, session = _session_returning(10)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        await cost_budget.monthly_call_count("brave")
        await cost_budget.monthly_call_count("brave", force_refresh=True)
    assert session.execute.await_count == 2


@pytest.mark.asyncio
async def test_monthly_call_count_never_raises_returns_last_known():
    maker, _ = _session_returning(5)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        await cost_budget.monthly_call_count("mistral")  # peuple le cache à 5
    # DB tombe : la valeur connue est renvoyée plutôt que de lever
    cost_budget._cache["mistral"] = (5, 0.0)  # force l'expiration du TTL
    broken = MagicMock(side_effect=RuntimeError("db down"))
    with patch("app.services.observability.cost_budget.safe_async_session", broken):
        value = await cost_budget.monthly_call_count("mistral")
    assert value == 5


@pytest.mark.asyncio
async def test_is_over_cap():
    maker, _ = _session_returning(1800)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        assert await cost_budget.is_over_cap("brave", 1800) is True
        cost_budget.invalidate_cache()
    maker2, _ = _session_returning(1799)
    with patch("app.services.observability.cost_budget.safe_async_session", maker2):
        assert await cost_budget.is_over_cap("brave", 1800) is False


@pytest.mark.asyncio
async def test_is_over_cap_disabled_when_cap_non_positive():
    # cap <= 0 → jamais de blocage, et aucune requête DB
    maker, session = _session_returning(99999)
    with patch("app.services.observability.cost_budget.safe_async_session", maker):
        assert await cost_budget.is_over_cap("brave", 0) is False
    session.execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_log_budget_projection_returns_snapshot():
    snapshot = {"mistral": {"classification_pass1": 100}, "brave": {"smart_search_brave": 20}}
    with patch(
        "app.services.observability.cost_budget.monthly_usage_by_call_site",
        new=AsyncMock(return_value=snapshot),
    ):
        result = await cost_budget.log_budget_projection(projection_factor=2.0)
    assert result == snapshot
