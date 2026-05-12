"""Tests pour SourceSuggester — liste unique rankée + ingestion à la volée.

Mocke `RSSParser.detect` (pas d'appel HTTP réel) + `EditorialLLMClient.chat_json`.
Couvre :
- Followed source : retournée dans la liste avec `is_already_followed=True`.
- Ingestion : nouvelle source si feed_url absent du catalogue.
- Réutilisation : row existante si feed_url déjà connu.
- Theme guard : INSERT skipped si theme_id hors contrainte SQL.
- Injection purpose + editorial_brief dans le user_message LLM.
- Fallback déterministe sans `MISTRAL_API_KEY`.
"""

import asyncio
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest_asyncio
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.services.veille.source_suggester import SourceSuggester


@pytest_asyncio.fixture
async def test_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Veille User",
        onboarding_completed=True,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


@pytest_asyncio.fixture
async def followed_source(db_session, test_user):
    src = Source(
        id=uuid4(),
        name="Le café pédago",
        url="https://cafepedago.example.com",
        feed_url=f"https://cafepedago.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="science",
        is_active=True,
        is_curated=True,
    )
    db_session.add(src)
    db_session.add(
        UserSource(
            id=uuid4(),
            user_id=test_user.user_id,
            source_id=src.id,
        )
    )
    await db_session.commit()
    return src


def _detect_response(name: str, feed_url: str, feed_type: str = "rss"):
    """Simule un DetectedFeed minimal (retour de `RSSParser.detect`)."""
    from app.services.rss_parser import DetectedFeed

    return DetectedFeed(
        feed_url=feed_url,
        title=name,
        description=f"{name} — média indé",
        feed_type=feed_type,
        logo_url=None,
        entries=[],
    )


def _candidate(name: str, url: str, score: float = 0.7, why: str | None = None) -> dict:
    return {
        "name": name,
        "url": url,
        "why": why or f"{name} — média pertinent",
        "relevance_score": score,
    }


class TestAlreadyFollowedFlag:
    async def test_returns_followed_with_flag(
        self, db_session, test_user, followed_source
    ):
        """Une source déjà rattachée via UserSource ressort avec
        `is_already_followed=True` dans la liste flat."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [_candidate(followed_source.name, followed_source.url, 0.9)]
            }
        )
        suggester = SourceSuggester(llm=llm)

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(
                return_value=_detect_response(
                    followed_source.name, followed_source.feed_url
                )
            ),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        assert len(result.sources) == 1
        item = result.sources[0]
        assert item.source_id == followed_source.id
        assert item.is_already_followed is True

    async def test_excludes_specified(self, db_session, test_user, followed_source):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [_candidate(followed_source.name, followed_source.url, 0.9)]
            }
        )
        suggester = SourceSuggester(llm=llm)

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(
                return_value=_detect_response(
                    followed_source.name, followed_source.feed_url
                )
            ),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
                excluded_source_ids=[followed_source.id],
            )

        assert result.sources == []


class TestIngestion:
    async def test_ingest_new_source(self, db_session, test_user):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate(
                        "Mediapart Education",
                        "https://mediapart-edu.example.com",
                        0.85,
                    )
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        new_feed = "https://mediapart-edu.example.com/feed.xml"

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(
                return_value=_detect_response("Mediapart Education", new_feed)
            ),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=["politiques"],
            )

        assert len(result.sources) == 1
        assert result.sources[0].feed_url == new_feed
        assert result.sources[0].is_already_followed is False
        assert result.sources[0].relevance_score == 0.85

        ingested = (
            (
                await db_session.execute(
                    select(Source).where(Source.feed_url == new_feed)
                )
            )
            .scalars()
            .first()
        )
        assert ingested is not None
        assert ingested.is_curated is False
        assert ingested.is_active is True
        assert ingested.theme == "science"

        # Pas de UserSource créée (le LLM ne crée pas de follow).
        link = (
            (
                await db_session.execute(
                    select(UserSource).where(
                        UserSource.user_id == test_user.user_id,
                        UserSource.source_id == ingested.id,
                    )
                )
            )
            .scalars()
            .first()
        )
        assert link is None

    async def test_reuse_existing_source(self, db_session, test_user, followed_source):
        """Si feed_url existe déjà → on renvoie la row existante (pas de doublon)."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [_candidate(followed_source.name, followed_source.url, 0.8)]
            }
        )
        suggester = SourceSuggester(llm=llm)

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(
                return_value=_detect_response(
                    followed_source.name, followed_source.feed_url
                )
            ),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        all_with_feed = (
            (
                await db_session.execute(
                    select(Source).where(Source.feed_url == followed_source.feed_url)
                )
            )
            .scalars()
            .all()
        )
        assert len(list(all_with_feed)) == 1
        assert result.sources[0].source_id == followed_source.id


class TestDedupByDomain:
    async def test_dedup_keeps_highest_score(self, db_session, test_user):
        """Deux candidats sur le même domaine racine → on garde le meilleur score."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("Foo", "https://foo.example.com", 0.4),
                    _candidate("Foo Plus", "https://www.foo.example.com/plus", 0.9),
                    _candidate("Bar", "https://bar.example.com", 0.6),
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        # detect_source retourne un feed_url DIFFÉRENT par URL appelée
        async def _detect(url):
            return _detect_response(url, f"{url}/feed.xml")

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(side_effect=_detect),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        # 2 domaines distincts → 2 résultats. Foo gagne avec score 0.9.
        domains = {s.url for s in result.sources}
        assert len(result.sources) == 2
        # Tri par score desc
        scores = [s.relevance_score for s in result.sources]
        assert scores == sorted(scores, reverse=True)
        assert any("foo.example.com" in d for d in domains)

    async def test_sort_by_relevance_desc(self, db_session, test_user):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("A", "https://a.example.com", 0.5),
                    _candidate("B", "https://b.example.com", 0.95),
                    _candidate("C", "https://c.example.com", 0.7),
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        async def _detect(url):
            return _detect_response(url, f"{url}/feed.xml")

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(side_effect=_detect),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        names = [s.name for s in result.sources]
        assert names == ["B", "C", "A"]


class TestThemeGuard:
    async def test_invalid_theme_skips_ingest(self, db_session, test_user):
        """`_persist_detected` doit lever ValueError avant l'INSERT si le
        theme_id viole `ck_source_theme_valid`. Sans ce garde-fou, l'INSERT
        empoisonne la session (PendingRollbackError sur tout commit suivant).
        """
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("Climat Info", "https://climat.example.com", 0.7)
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        new_feed = "https://climat.example.com/feed.xml"
        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(return_value=_detect_response("Climat Info", new_feed)),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="climat",  # legacy slug, hors contrainte
                topic_labels=[],
            )

        assert result.sources == []
        leftover = (
            (
                await db_session.execute(
                    select(Source).where(Source.feed_url == new_feed)
                )
            )
            .scalars()
            .first()
        )
        assert leftover is None


class TestPurposeAndBriefInjection:
    async def test_purpose_and_brief_in_user_message(self, db_session, test_user):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={"sources": []})
        suggester = SourceSuggester(llm=llm)

        await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=["climat"],
            purpose="preparer_projet",
            editorial_brief="Plutôt analyses long format",
        )

        assert llm.chat_json.await_count == 1
        user_msg = llm.chat_json.call_args.kwargs["user_message"]
        assert "Préparer un projet / une décision" in user_msg
        assert "Brief éditorial : Plutôt analyses long format" in user_msg

    async def test_purpose_other_in_user_message(self, db_session, test_user):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(return_value={"sources": []})
        suggester = SourceSuggester(llm=llm)

        await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=[],
            purpose="autre",
            purpose_other="préparer un livre",
        )

        user_msg = llm.chat_json.call_args.kwargs["user_message"]
        assert "Autre (préparer un livre)" in user_msg


class TestFallback:
    async def test_no_llm_returns_curated_same_theme(self, db_session, test_user):
        # Crée 10 sources curées thème science ; le fallback en renvoie max 8.
        for i in range(10):
            db_session.add(
                Source(
                    id=uuid4(),
                    name=f"Sci Source {i}",
                    url=f"https://sci{i}.example.com",
                    feed_url=f"https://sci{i}.example.com/feed-{uuid4()}.xml",
                    type=SourceType.ARTICLE,
                    theme="science",
                    is_active=True,
                    is_curated=True,
                )
            )
        await db_session.commit()

        llm = AsyncMock()
        llm.is_ready = False
        suggester = SourceSuggester(llm=llm)

        result = await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=[],
        )

        assert len(result.sources) == 8
        assert all(s.relevance_score is None for s in result.sources)
        assert all(s.is_already_followed is False for s in result.sources)


class TestSavepointIsolation:
    """Sans savepoint, une `IntegrityError` au `flush()` empoisonne la session ;
    tous les candidats suivants lèvent `PendingRollbackError` → 503 + 0 source
    ingérée. Avec savepoint, seul le candidat fautif est rollback."""

    async def test_session_recovers_from_integrity_error(self, db_session, test_user):
        """Force une `IntegrityError` directe au flush() du candidat #2 et
        vérifie que le candidat #3 réussit + que la session reste utilisable."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("First", "https://first.example.com", 0.9),
                    _candidate("Boom", "https://boom.example.com", 0.5),
                    _candidate("Third", "https://third.example.com", 0.7),
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        async def _detect(url):
            return _detect_response(url, f"{url}/feed.xml")

        original_flush = db_session.flush
        flush_calls = {"count": 0}

        async def _flush_failing_on_second(*args, **kwargs):
            flush_calls["count"] += 1
            if flush_calls["count"] == 2:
                raise IntegrityError("simulated", {}, Exception("constraint X"))
            return await original_flush(*args, **kwargs)

        with (
            patch(
                "app.services.veille.source_suggester.RSSParser.detect",
                new=AsyncMock(side_effect=_detect),
            ),
            patch.object(db_session, "flush", new=_flush_failing_on_second),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        names = {s.name for s in result.sources}
        assert "Boom" not in names
        assert len(result.sources) == 2

        # La session doit être saine : un commit final ne lève pas.
        await db_session.commit()


class TestCandidateTimeout:
    """Cap par candidat à 8 s : un URL qui hang dans RSSParser ne doit pas
    geler le pipeline pour les autres candidats."""

    async def test_slow_candidate_is_skipped(self, db_session, test_user, monkeypatch):
        # On baisse le timeout à 0.1 s pour ne pas allonger la suite de tests.
        monkeypatch.setattr(
            "app.services.veille.source_suggester._HYDRATE_TIMEOUT_S", 0.1
        )

        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("Fast", "https://fast.example.com", 0.9),
                    _candidate("Slow", "https://slow.example.com", 0.8),
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        async def _detect(url: str):
            if "slow" in url:
                await asyncio.sleep(2.0)  # bien au-dessus du timeout patché
            return _detect_response(url, f"{url}/feed.xml")

        with patch(
            "app.services.veille.source_suggester.RSSParser.detect",
            new=AsyncMock(side_effect=_detect),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        names = {s.name for s in result.sources}
        assert "Slow" not in names
        assert len(result.sources) == 1
        assert result.sources[0].name == "Fast"


class TestLLMTimeout:
    """Cap global LLM à 20 s : sur timeout → fallback curé."""

    async def test_llm_timeout_falls_back_to_curated(
        self, db_session, test_user, monkeypatch
    ):
        monkeypatch.setattr("app.services.veille.source_suggester._LLM_TIMEOUT_S", 0.1)

        # Crée 3 sources curées du thème pour vérifier le fallback.
        for i in range(3):
            db_session.add(
                Source(
                    id=uuid4(),
                    name=f"Curated {i}",
                    url=f"https://curated{i}.example.com",
                    feed_url=f"https://curated{i}.example.com/feed-{uuid4()}.xml",
                    type=SourceType.ARTICLE,
                    theme="science",
                    is_active=True,
                    is_curated=True,
                )
            )
        await db_session.commit()

        llm = AsyncMock()
        llm.is_ready = True

        async def _slow_chat(*args, **kwargs):
            await asyncio.sleep(2.0)
            return {"sources": []}

        llm.chat_json = _slow_chat
        suggester = SourceSuggester(llm=llm)

        result = await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=[],
        )

        # Bascule sur le fallback curé.
        assert len(result.sources) == 3
        assert all(s.relevance_score is None for s in result.sources)


class TestNoTxDuringLLM:
    """Anti-régression : aucune requête DB ne doit ouvrir une transaction
    AVANT l'appel LLM. Sinon la tx reste idle pendant l'appel réseau et
    `idle_in_transaction_session_timeout` (10 s, cf. database.py:166) tue
    la connexion → PendingRollbackError au commit final (PYTHON-3P)."""

    async def test_followed_ids_query_runs_after_llm(self, db_session, test_user):
        order: list[str] = []

        llm = AsyncMock()
        llm.is_ready = True

        async def _record_chat(*args, **kwargs):
            order.append("llm")
            return {"sources": []}

        llm.chat_json = _record_chat
        suggester = SourceSuggester(llm=llm)

        original_followed = suggester._followed_source_ids

        async def _record_followed(session, user_id):
            order.append("followed_ids")
            return await original_followed(session, user_id)

        suggester._followed_source_ids = _record_followed

        await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=[],
        )

        assert order == ["llm", "followed_ids"], (
            "LLM doit être appelé AVANT la SELECT user_sources, sinon la tx "
            "reste idle pendant l'appel Mistral et PG tue la connexion."
        )

    async def test_rollback_before_llm_then_timeouts_reapplied(self):
        """Anti-régression PYTHON-3Z (post-#568) : `safe_async_session`
        émet 2× SET LOCAL au début de la session → tx implicite ouverte.
        Sans rollback explicite avant l'appel LLM, l'await Mistral
        (~13 s observés) dépasse `idle_in_transaction_session_timeout=10s`
        → PG tue la connexion → IdleInTransactionSessionTimeout sur la
        SELECT suivante (event Sentry c5c381eb…). Verrouille l'ordre :
            session.rollback() → llm → apply_session_timeouts → followed_ids

        Pure mock (pas de db_session) : on teste l'ordre des appels, pas
        l'exécution SQL réelle.
        """
        from sqlalchemy.ext.asyncio import AsyncSession

        order: list[str] = []

        session = AsyncMock(spec=AsyncSession)

        async def _record_rollback():
            order.append("rollback")

        session.rollback = _record_rollback

        llm = AsyncMock()
        llm.is_ready = True

        async def _record_chat(*args, **kwargs):
            order.append("llm")
            return {"sources": []}

        llm.chat_json = _record_chat
        suggester = SourceSuggester(llm=llm)

        async def _record_followed(s, user_id):
            order.append("followed_ids")
            return set()

        suggester._followed_source_ids = _record_followed

        async def _record_fallback(s, theme_id, excluded, followed_ids):
            order.append("fallback")
            return []

        suggester._fallback = _record_fallback

        async def _record_apply_timeouts(s, *args, **kwargs):
            order.append("apply_timeouts")

        with patch(
            "app.services.veille.source_suggester.apply_session_timeouts",
            new=_record_apply_timeouts,
        ):
            await suggester.suggest_sources(
                session=session,
                user_id=uuid4(),
                theme_id="science",
                topic_labels=[],
            )

        # Le suggester va aussi appeler _fallback (candidates vide), peu
        # importe ici — on verrouille le PRÉFIXE d'ordre.
        assert order[:4] == [
            "rollback",
            "llm",
            "apply_timeouts",
            "followed_ids",
        ], order


class TestParallelDetect:
    """Anti-régression Iter 4 : la phase HTTP detect doit s'exécuter en
    parallèle (`_DETECT_CONCURRENCY=4`) pour que 12 candidats lents
    finissent en ⌈12/4⌉ × delay et non 12 × delay. Sans la
    parallélisation, le wall-clock dépassait le timeout Dio mobile (30 s)
    et l'utilisateur tombait sur le fallback mock alors que les sources
    finissaient par être ingérées en DB côté serveur."""

    async def test_detect_runs_concurrently_within_semaphore(self):
        from app.models.source import Source as SourceModel
        from app.services.rss_parser import DetectedFeed
        from app.services.veille.source_suggester import _DETECT_CONCURRENCY

        in_flight = {"current": 0, "max_observed": 0}

        async def _slow_detect(url: str) -> DetectedFeed:
            in_flight["current"] += 1
            in_flight["max_observed"] = max(
                in_flight["max_observed"], in_flight["current"]
            )
            try:
                await asyncio.sleep(0.5)
            finally:
                in_flight["current"] -= 1
            return DetectedFeed(
                feed_url=f"{url}/feed.xml",
                title=url,
                description="t",
                feed_type="rss",
                logo_url=None,
                entries=[],
            )

        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate(f"S{i}", f"https://s{i}.example.com", 0.5 + i * 0.01)
                    for i in range(12)
                ]
            }
        )

        suggester = SourceSuggester(llm=llm)

        # Bypass DB : pas de followed, persist stub renvoie un Source en
        # mémoire. Évite la dépendance Postgres pour ce test perf.
        async def _no_followed(s, user_id):
            return set()

        suggester._followed_source_ids = _no_followed

        async def _stub_persist(s, cand, detected, theme_id):
            return SourceModel(
                id=uuid4(),
                name=cand.name,
                url=cand.url,
                feed_url=detected.feed_url,
                type=SourceType.ARTICLE,
                theme=theme_id,
                description=None,
                logo_url=None,
                is_curated=False,
                is_active=True,
            )

        suggester._persist_detected = _stub_persist

        # AsyncSession factice : seules `rollback` + `begin_nested` (async
        # context manager) sont effectivement awaited par suggest_sources.
        class _FakeNested:
            async def __aenter__(self):
                return self

            async def __aexit__(self, exc_type, exc, tb):
                return None

        class _FakeSession:
            async def rollback(self):
                return None

            def begin_nested(self):
                return _FakeNested()

        session = _FakeSession()

        with (
            patch(
                "app.services.veille.source_suggester.RSSParser.detect",
                new=AsyncMock(side_effect=_slow_detect),
            ),
            patch(
                "app.services.veille.source_suggester.apply_session_timeouts",
                new=AsyncMock(),
            ),
        ):
            loop = asyncio.get_event_loop()
            t0 = loop.time()
            result = await suggester.suggest_sources(
                session=session,
                user_id=uuid4(),
                theme_id="science",
                topic_labels=[],
            )
            elapsed = loop.time() - t0

        assert len(result.sources) == 12
        # Sémaphore 4 ⇒ ⌈12/4⌉ × 0.5 = 1.5 s wall-clock idéal.
        # En séquentiel : 12 × 0.5 = 6 s. Marge × 2 pour CI : assert <3 s.
        assert elapsed < 3.0, (
            f"detect loop took {elapsed:.2f}s, expected ~1.5s parallel "
            f"(régression de la parallélisation Iter 4 ?)"
        )
        # La concurrence atteinte doit être exactement le sémaphore.
        assert in_flight["max_observed"] == _DETECT_CONCURRENCY, (
            f"max in-flight = {in_flight['max_observed']}, "
            f"expected {_DETECT_CONCURRENCY}"
        )
