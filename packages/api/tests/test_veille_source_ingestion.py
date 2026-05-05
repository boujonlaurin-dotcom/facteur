"""Tests pour SourceSuggester — liste unique rankée + ingestion à la volée.

Mocke `SourceService.detect_source` (pas d'appel HTTP réel) + `EditorialLLMClient.chat_json`.
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


def _detect_response(name: str, feed_url: str, source_type: str = "article"):
    """Simule un SourceDetectResponse minimal."""
    from app.schemas.source import SourceDetectResponse

    return SourceDetectResponse(
        source_id=None,
        detected_type=source_type,
        feed_url=feed_url,
        name=name,
        description=f"{name} — média indé",
        logo_url=None,
        theme="science",
        preview={"item_count": 0, "latest_titles": []},
        bias_stance="unknown",
        reliability_score="unknown",
        bias_origin="unknown",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
        """`_hydrate_or_ingest` doit lever ValueError avant l'INSERT si le
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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
    """Bug `bug-veille-suggestions-sources-pending-rollback` : sans savepoint,
    une `IntegrityError` sur un `flush()` empoisonnait toute la session ; tous
    les candidats suivants levaient `PendingRollbackError` → 503 et 0 source
    ingérée. Avec savepoint, seul le candidat fautif est rollback."""

    async def test_failing_candidate_does_not_poison_others(
        self, db_session, test_user
    ):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    _candidate("Good 1", "https://good1.example.com", 0.8),
                    _candidate("Bad", "https://bad.example.com", 0.7),
                    _candidate("Good 2", "https://good2.example.com", 0.6),
                ]
            }
        )
        suggester = SourceSuggester(llm=llm)

        async def _detect(url: str):
            # Le candidat "bad" résout vers un feed_url volontairement
            # invalide qui dépasse la limite text/varchar théorique du
            # nom de Source (>200 chars) côté ingest. detect_source ne
            # lève pas, c'est `flush()` qui doit échouer.
            if "bad" in url:
                return _detect_response("X" * 250, f"{url}/feed.xml")
            return _detect_response(url, f"{url}/feed.xml")

        with patch(
            "app.services.veille.source_suggester.SourceService.detect_source",
            new=AsyncMock(side_effect=_detect),
        ):
            result = await suggester.suggest_sources(
                session=db_session,
                user_id=test_user.user_id,
                theme_id="science",
                topic_labels=[],
            )

        # Le candidat fautif est skippé via savepoint rollback ; les 2 bons
        # candidats sont ingérés.
        names = sorted(s.name for s in result.sources)
        assert "Bad" not in names
        assert "https://good1.example.com" in {s.name for s in result.sources}
        assert "https://good2.example.com" in {s.name for s in result.sources}

        # La session est toujours utilisable après l'incident — un commit
        # final ne lève pas PendingRollbackError.
        await db_session.commit()

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
                "app.services.veille.source_suggester.SourceService.detect_source",
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
    """Cap par candidat à 8 s : un mauvais URL qui hang ne doit pas geler
    le pipeline (cf. bug binge.audio/feed/ retry 22× = 3 min wall)."""

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
            "app.services.veille.source_suggester.SourceService.detect_source",
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
        assert result.sources[0].name == "https://fast.example.com"


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
