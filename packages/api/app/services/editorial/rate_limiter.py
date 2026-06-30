"""Limiteur de débit partagé pour les appels Mistral `large` (LR-1 PR 1).

Le pipeline éditorial éclate des `asyncio.gather` non bornés (curation +
deep_matcher + perspective) sur le modèle `mistral-large-latest` via un
`EditorialLLMClient` à usage unique. Ce burst quotidien provoquait ~28 % de
429 (201 appels rate-limited / 14 j, spécifiques à l'éditorial).

`_MistralRateLimiter` borne ce burst sur **deux axes** :
- **token-bucket /minute** (`rpm`) : lisse le débit de départ des requêtes ;
- **semaphore** (`concurrency`) : borne le nombre d'appels HTTP simultanés.

Conçu comme **singleton module** (cf. `llm_client._get_large_limiter`) parce
que `EditorialLLMClient` est instancié par appelant : un limiteur par instance
ne bornerait pas l'agrégat. Comme l'objet vit au niveau module, il survit aux
changements de boucle d'événements (tests pytest-asyncio function-scoped) : la
`Semaphore` et le `Lock` sont (re)créés à la volée quand la boucle courante
change (`_ensure_loop_state`). L'horloge est injectable pour tester le pacing
avec une horloge factice sans `sleep` réel.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager


class _MistralRateLimiter:
    """Token-bucket /minute + cap de concurrence, loop-safe.

    `time_func` / `sleep_func` sont injectables (défaut `time.monotonic` /
    `asyncio.sleep`) pour piloter le pacing avec une horloge factice en test.
    """

    def __init__(
        self,
        *,
        rpm: int,
        concurrency: int,
        time_func: Callable[[], float] = time.monotonic,
        sleep_func: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._rpm = max(1, rpm)
        self._concurrency = max(1, concurrency)
        self._time = time_func
        self._sleep = sleep_func
        # Bucket démarre plein : le premier appel ne paie aucune attente.
        self._tokens = float(self._rpm)
        self._last_refill = self._time()
        # (Re)créés par boucle d'événements (cf. _ensure_loop_state).
        self._loop: asyncio.AbstractEventLoop | None = None
        self._sem: asyncio.Semaphore | None = None
        self._lock: asyncio.Lock | None = None

    @property
    def _refill_per_sec(self) -> float:
        return self._rpm / 60.0

    def _ensure_loop_state(self) -> None:
        """Recrée semaphore/lock si la boucle courante a changé.

        `asyncio.Semaphore`/`Lock` se lient à la boucle où ils sont utilisés
        en premier et lèvent s'ils sont réutilisés depuis une autre boucle.
        En prod la boucle est unique (aucun coût) ; en test chaque cas a sa
        propre boucle, d'où la recréation paresseuse. Le bucket (compteurs
        temporels) est, lui, agnostique à la boucle et conservé tel quel.
        """
        loop = asyncio.get_running_loop()
        if self._loop is not loop or self._sem is None or self._lock is None:
            self._loop = loop
            self._sem = asyncio.Semaphore(self._concurrency)
            self._lock = asyncio.Lock()

    async def _consume_token(self) -> None:
        """Attend qu'un jeton soit disponible puis le consomme.

        Sérialisé par `self._lock` : la section critique contient un `await`
        (sleep), donc sans verrou des coroutines concurrentes corrompraient le
        compteur. Verrou tenu pendant le sleep ⇒ octroi strictement cadencé
        (pacing FIFO), ce qui est précisément le throttle voulu.
        """
        assert self._lock is not None  # posé par _ensure_loop_state
        async with self._lock:
            while True:
                now = self._time()
                elapsed = now - self._last_refill
                if elapsed > 0:
                    self._tokens = min(
                        float(self._rpm),
                        self._tokens + elapsed * self._refill_per_sec,
                    )
                    self._last_refill = now
                if self._tokens >= 1.0:
                    self._tokens -= 1.0
                    return
                deficit = 1.0 - self._tokens
                await self._sleep(deficit / self._refill_per_sec)

    @asynccontextmanager
    async def slot(self) -> AsyncIterator[None]:
        """Acquiert un jeton (rpm) puis un slot de concurrence le temps du POST."""
        self._ensure_loop_state()
        await self._consume_token()
        assert self._sem is not None  # posé par _ensure_loop_state
        async with self._sem:
            yield
