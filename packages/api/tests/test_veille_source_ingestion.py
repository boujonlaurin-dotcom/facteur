"""Tests pour SourceSuggester (Story 18.1) — ingestion à la volée des niches.

Mocke `SourceService.detect_source` (pas d'appel HTTP réel) + `EditorialLLMClient.chat_json`.
Couvre :
- Followed : SELECT user_sources filtré par thème.
- Niche : ingestion d'une nouvelle source si feed_url absent du catalogue.
- Niche : réutilisation de la row existante si feed_url déjà connu.
- Fallback déterministe sans `MISTRAL_API_KEY`.
"""

from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest_asyncio
from sqlalchemy import select

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


@pytest_asyncio.fixture
async def offtheme_followed_source(db_session, test_user):
    """Source suivie mais sur un autre thème — ne doit PAS apparaître."""
    src = Source(
        id=uuid4(),
        name="Tech Daily",
        url="https://techdaily.example.com",
        feed_url=f"https://techdaily.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
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


class TestFollowed:
    async def test_returns_only_theme_matching(
        self,
        db_session,
        test_user,
        followed_source,
        offtheme_followed_source,
    ):
        llm = AsyncMock()
        llm.is_ready = False  # niche → fallback (vide ici car pas de curated)
        suggester = SourceSuggester(llm=llm)

        result = await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=["evaluations"],
        )

        followed_ids = [s.source_id for s in result.followed]
        assert followed_source.id in followed_ids
        assert offtheme_followed_source.id not in followed_ids

    async def test_excludes_specified(self, db_session, test_user, followed_source):
        llm = AsyncMock()
        llm.is_ready = False
        suggester = SourceSuggester(llm=llm)

        result = await suggester.suggest_sources(
            session=db_session,
            user_id=test_user.user_id,
            theme_id="science",
            topic_labels=[],
            excluded_source_ids=[followed_source.id],
        )

        assert result.followed == []


class TestNicheIngestion:
    async def test_ingest_new_source(self, db_session, test_user):
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    {
                        "name": "Mediapart Education",
                        "url": "https://mediapart-edu.example.com",
                        "why": "Investigation sur les politiques éducatives",
                    }
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

        assert len(result.niche) == 1
        assert result.niche[0].feed_url == new_feed

        # Source row créée avec is_curated=False.
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

        # Pas de UserSource créée (c'est une niche, pas un follow).
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
        """Si le feed_url existe déjà → on renvoie la row existante (pas de doublon)."""
        llm = AsyncMock()
        llm.is_ready = True
        llm.chat_json = AsyncMock(
            return_value={
                "sources": [
                    {
                        "name": followed_source.name,
                        "url": followed_source.url,
                        "why": "Spécialisé éducation",
                    }
                ]
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

        # La niche ne doit PAS dupliquer la source.
        # Note : la source existante est aussi `followed` ici → dans la vraie
        # vie le caller passe `excluded_source_ids` avec les followed pour
        # éviter le doublon ; le service fait confiance à cette liste.
        # On vérifie ici qu'AUCUNE nouvelle row Source n'a été créée.
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
        # Et que la niche pointe sur la row existante.
        assert result.niche[0].source_id == followed_source.id


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
                    {
                        "name": "Climat Info",
                        "url": "https://climat.example.com",
                        "why": "Spécialisé climat",
                    }
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

        # Le candidat doit être skippé (try/except dans _niche), pas crasher
        # toute la requête. La niche reste vide et aucune row Source n'est
        # créée avec theme='climat'.
        assert result.niche == []
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
        # On ne se soucie pas de la réponse — on capture juste l'appel.
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
        # Crée 6 sources curées thème education ; le fallback en renvoie 5 max.
        for i in range(6):
            db_session.add(
                Source(
                    id=uuid4(),
                    name=f"Edu Source {i}",
                    url=f"https://edu{i}.example.com",
                    feed_url=f"https://edu{i}.example.com/feed-{uuid4()}.xml",
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

        assert len(result.niche) == 5
