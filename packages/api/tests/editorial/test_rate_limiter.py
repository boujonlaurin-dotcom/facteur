"""Tests du `_MistralRateLimiter` (LR-1 PR 1).

Le pacing token-bucket est piloté par une **horloge factice** (aucun sleep
réel) : on vérifie que le bucket démarre plein, draine sans attente, puis
cadence à `rpm` une fois vide, et qu'il se recharge avec le temps. La
concurrence est vérifiée avec de vraies primitives asyncio.
"""

from __future__ import annotations

import asyncio

import pytest

from app.services.editorial.rate_limiter import _MistralRateLimiter


class FakeClock:
    """Horloge monotone factice : `sleep` avance le temps sans attente réelle."""

    def __init__(self) -> None:
        self.now = 0.0
        self.sleeps: list[float] = []

    def time(self) -> float:
        return self.now

    async def sleep(self, delay: float) -> None:
        self.sleeps.append(delay)
        self.now += delay


def _limiter(clock: FakeClock, *, rpm: int, concurrency: int) -> _MistralRateLimiter:
    return _MistralRateLimiter(
        rpm=rpm,
        concurrency=concurrency,
        time_func=clock.time,
        sleep_func=clock.sleep,
    )


@pytest.mark.asyncio
async def test_first_call_never_waits():
    """Bucket plein au démarrage ⇒ le premier appel ne paie aucune attente."""
    clock = FakeClock()
    limiter = _limiter(clock, rpm=1, concurrency=1)
    async with limiter.slot():
        pass
    assert clock.sleeps == []


@pytest.mark.asyncio
async def test_full_bucket_drains_without_waiting():
    """Drainer exactement `rpm` jetons à t=0 ne déclenche aucun sleep."""
    clock = FakeClock()
    limiter = _limiter(clock, rpm=60, concurrency=10)
    for _ in range(60):
        async with limiter.slot():
            pass
    assert clock.sleeps == []
    assert clock.now == 0.0


@pytest.mark.asyncio
async def test_paces_at_rpm_once_bucket_empty():
    """Une fois le bucket vide, chaque appel attend un intervalle de recharge."""
    clock = FakeClock()
    limiter = _limiter(clock, rpm=60, concurrency=10)  # 60 rpm -> 1 jeton/s
    for _ in range(60):
        async with limiter.slot():
            pass
    for _ in range(3):
        async with limiter.slot():
            pass
    assert clock.sleeps == [1.0, 1.0, 1.0]
    assert clock.now == 3.0


@pytest.mark.asyncio
async def test_tokens_refill_over_time():
    """Le temps écoulé recharge le bucket (jusqu'au plafond `rpm`)."""
    clock = FakeClock()
    limiter = _limiter(clock, rpm=60, concurrency=10)
    for _ in range(60):
        async with limiter.slot():
            pass
    # 10 s s'écoulent -> 10 jetons rechargés -> 10 appels sans attente.
    clock.now += 10.0
    for _ in range(10):
        async with limiter.slot():
            pass
    assert clock.sleeps == []
    # Le 11e appel retrouve un bucket vide et doit attendre.
    async with limiter.slot():
        pass
    assert clock.sleeps == [1.0]


@pytest.mark.asyncio
async def test_concurrency_cap_limits_in_flight():
    """La semaphore borne le nombre d'appels simultanés à `concurrency`."""
    clock = FakeClock()
    limiter = _limiter(clock, rpm=100000, concurrency=2)  # rpm hors-jeu ici
    in_flight = 0
    peak = 0
    gate = asyncio.Event()

    async def worker() -> None:
        nonlocal in_flight, peak
        async with limiter.slot():
            in_flight += 1
            peak = max(peak, in_flight)
            await gate.wait()
            in_flight -= 1

    tasks = [asyncio.create_task(worker()) for _ in range(5)]
    # Laisse l'ordonnanceur tourner : seuls `concurrency` workers franchissent
    # la semaphore, les autres restent bloqués sur l'acquire.
    for _ in range(20):
        await asyncio.sleep(0)
    assert in_flight == 2
    assert peak == 2
    gate.set()
    await asyncio.gather(*tasks)
    assert peak == 2
