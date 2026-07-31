"""Epic 30 « La lecture aboutie » — garde-fous des compteurs de complétion.

Trois zones qui n'avaient aucun test alors qu'elles pilotent la calibration de
`DAILY_COMPLETION_GOAL` :

1. `_update_closure_streak` — était systématiquement mocké dans les 3 fichiers
   qui l'approchent, ce qui a laissé passer un décalage de frontière (édition
   estampillée `editorial_day()` / digest cherché en `today_paris()`).
2. `count_completed_today` — le compteur exposé à l'UI.
3. `StreakResponse.daily_goal` — dupliqué en dur, donc libre de diverger.
"""

from datetime import UTC, date, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content, ContentType, UserContentStatus
from app.models.user import UserProfile, UserStreak
from app.schemas.content import SourceMini
from app.schemas.digest import DigestTopic, DigestTopicArticle
from app.schemas.essentiel import EssentielArticle
from app.schemas.streak import DAILY_COMPLETION_GOAL
from app.services.digest_service import DigestService
from app.services.essentiel_service import EssentielUserContext, _to_essentiel_article
from app.services.streak_service import StreakService
from app.utils.time import PARIS_TZ

# --------------------------------------------------------------------------
# 1. closure streak — démocké
# --------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_closure_streak_counts_consecutive_editions(db_session):
    """Clore l'édition D puis l'édition D+1 donne une série de 2.

    Test de non-régression du bug : la méthode estampillait une notion de
    « aujourd'hui » (frontière 07h30) alors que ses appelants trouvent le
    digest via `today_paris()` (minuit). Entre 00h et 07h30 Paris, clore
    l'édition D estampillait D-1, puis clore D+1 le lendemain soir voyait
    `days_since == 2` → série remise à 1.
    """
    user_id = uuid4()
    service = DigestService(db_session)

    first = await service._update_closure_streak(user_id, date(2026, 4, 24))
    second = await service._update_closure_streak(user_id, date(2026, 4, 25))

    assert first["current"] == 1
    assert second["current"] == 2

    streak = await db_session.scalar(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    assert streak.last_closure_date == date(2026, 4, 25)
    assert streak.longest_closure_streak == 2


@pytest.mark.asyncio
async def test_closure_streak_is_idempotent_per_edition(db_session):
    """Re-clore la même édition (chemin explicite après le chemin implicite)
    ne double pas la série."""
    user_id = uuid4()
    service = DigestService(db_session)

    await service._update_closure_streak(user_id, date(2026, 4, 24))
    again = await service._update_closure_streak(user_id, date(2026, 4, 24))

    assert again["current"] == 1


@pytest.mark.asyncio
async def test_closure_streak_resets_after_a_skipped_edition(db_session):
    """Une édition sautée casse bien la série — la correction ne rend pas la
    méthode permissive, elle la rend seulement indépendante de l'heure."""
    user_id = uuid4()
    service = DigestService(db_session)

    await service._update_closure_streak(user_id, date(2026, 4, 24))
    resumed = await service._update_closure_streak(user_id, date(2026, 4, 26))

    assert resumed["current"] == 1


@pytest.mark.asyncio
async def test_closure_streak_ignores_a_past_edition(db_session):
    """Refermer une édition passée ne touche pas la série en cours.

    Le sélecteur de date sert les éditions J-7 et `complete_digest` accepte
    n'importe quel `digest_id` : depuis l'estampillage sur l'édition, un
    `days_since` négatif tombait dans la branche « série cassée » (reset à 1)
    et ramenait `last_closure_date` en arrière — donc cassait aussi la clôture
    du lendemain.
    """
    user_id = uuid4()
    service = DigestService(db_session)

    await service._update_closure_streak(user_id, date(2026, 4, 24))
    await service._update_closure_streak(user_id, date(2026, 4, 25))

    backfill = await service._update_closure_streak(user_id, date(2026, 4, 20))

    assert backfill["current"] == 2

    streak = await db_session.scalar(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    assert streak.last_closure_date == date(2026, 4, 25)

    # Et la clôture du lendemain prolonge toujours la série.
    tomorrow = await service._update_closure_streak(user_id, date(2026, 4, 26))
    assert tomorrow["current"] == 3


# --------------------------------------------------------------------------
# 2. count_completed_today — frontière 07h30 Paris
# --------------------------------------------------------------------------


async def _content(db_session, test_source) -> Content:
    content = Content(
        id=uuid4(),
        source_id=test_source.id,
        title="Un article",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
    )
    db_session.add(content)
    await db_session.flush()
    return content


async def _complete(db_session, test_source, user_id, completed_at: datetime | None):
    content = await _content(db_session, test_source)
    db_session.add(
        UserContentStatus(
            user_id=user_id,
            content_id=content.id,
            completed_at=completed_at,
        )
    )
    await db_session.flush()


@pytest.mark.asyncio
async def test_count_completed_today_ignores_older_days(
    db_session, test_source, monkeypatch
):
    """Une complétion de J-3 ne compte pas dans la journée éditoriale en cours."""
    user_id = uuid4()
    now = datetime(2026, 4, 24, 12, 0, tzinfo=PARIS_TZ)
    monkeypatch.setattr(
        "app.services.streak_service.editorial_day_bounds",
        lambda: (
            datetime(2026, 4, 24, 7, 30, tzinfo=PARIS_TZ),
            datetime(2026, 4, 25, 7, 30, tzinfo=PARIS_TZ),
        ),
    )

    await _complete(db_session, test_source, user_id, now)
    await _complete(db_session, test_source, user_id, now - timedelta(days=3))
    # Article ouvert mais jamais abouti — ne doit jamais compter.
    await _complete(db_session, test_source, user_id, None)

    assert await StreakService(db_session).count_completed_today(str(user_id)) == 1


@pytest.mark.asyncio
async def test_count_completed_today_exercises_the_0730_boundary(
    db_session, test_source, monkeypatch
):
    """La fenêtre suit 07h30 Paris des deux côtés : 07h29 appartient encore à
    l'édition de la veille, 07h31 à celle du jour."""
    user_id = uuid4()
    monkeypatch.setattr(
        "app.services.streak_service.editorial_day_bounds",
        lambda: (
            datetime(2026, 4, 24, 7, 30, tzinfo=PARIS_TZ),
            datetime(2026, 4, 25, 7, 30, tzinfo=PARIS_TZ),
        ),
    )

    # Hors fenêtre : juste avant l'ouverture, et juste après la fermeture.
    await _complete(
        db_session, test_source, user_id, datetime(2026, 4, 24, 7, 29, tzinfo=PARIS_TZ)
    )
    await _complete(
        db_session, test_source, user_id, datetime(2026, 4, 25, 7, 30, tzinfo=PARIS_TZ)
    )
    # Dans la fenêtre : à l'ouverture pile, et juste avant la fermeture.
    await _complete(
        db_session, test_source, user_id, datetime(2026, 4, 24, 7, 30, tzinfo=PARIS_TZ)
    )
    await _complete(
        db_session, test_source, user_id, datetime(2026, 4, 25, 7, 29, tzinfo=PARIS_TZ)
    )

    assert await StreakService(db_session).count_completed_today(str(user_id)) == 2


@pytest.mark.asyncio
async def test_count_completed_today_is_scoped_to_the_user(
    db_session, test_source, monkeypatch
):
    user_id = uuid4()
    monkeypatch.setattr(
        "app.services.streak_service.editorial_day_bounds",
        lambda: (
            datetime(2026, 4, 24, 7, 30, tzinfo=PARIS_TZ),
            datetime(2026, 4, 25, 7, 30, tzinfo=PARIS_TZ),
        ),
    )
    inside = datetime(2026, 4, 24, 12, 0, tzinfo=PARIS_TZ)

    await _complete(db_session, test_source, user_id, inside)
    await _complete(db_session, test_source, uuid4(), inside)

    assert await StreakService(db_session).count_completed_today(str(user_id)) == 1


# --------------------------------------------------------------------------
# 3. contrats — objectif journalier et complétion servie par /api/essentiel
# --------------------------------------------------------------------------


def test_daily_goal_default_tracks_the_constant():
    """Garde anti-re-duplication : le défaut du schéma ne doit plus être un
    littéral libre de diverger de la valeur servie par le service."""
    from app.schemas.streak import StreakResponse

    response = StreakResponse(
        current_streak=0,
        longest_streak=0,
        last_activity_date=None,
        weekly_count=0,
        weekly_goal=10,
        weekly_progress=0.0,
    )
    assert response.daily_goal == DAILY_COMPLETION_GOAL


@pytest.mark.asyncio
async def test_get_streak_reflects_profile_daily_goal(db_session):
    """L'objectif quotidien réglable (colonne profil `daily_goal`) doit être
    servi par `get_streak`, et non plus la constante en dur (story 30.2)."""
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            gamification_enabled=True,
            weekly_goal=10,
            daily_goal=5,
        )
    )
    await db_session.flush()

    streak = await StreakService(db_session).get_streak(str(user_id))

    assert streak.daily_goal == 5


@pytest.mark.asyncio
async def test_get_streak_falls_back_to_constant_without_profile(db_session):
    """Sans profil (ex. utilisateur legacy), l'objectif retombe sur la constante
    serveur plutôt que de planter."""
    user_id = uuid4()

    streak = await StreakService(db_session).get_streak(str(user_id))

    assert streak.daily_goal == DAILY_COMPLETION_GOAL


def test_essentiel_article_carries_completed_at():
    """`/api/essentiel` doit servir `completed_at` : sans lui la carte héros de
    la Tournée ne peut pas connaître la complétion."""
    completed_at = datetime(2026, 4, 24, 9, 0, tzinfo=UTC)
    article = DigestTopicArticle(
        content_id=uuid4(),
        title="Un article",
        url="https://example.com/a",
        published_at=datetime.now(UTC),
        source=SourceMini(
            id=uuid4(),
            name="Le Monde",
            logo_url=None,
            type="article",
            theme="society",
        ),
        rank=1,
        reason="test",
        completed_at=completed_at,
    )
    topic = DigestTopic(
        topic_id="t1",
        label="Société",
        rank=1,
        reason="test",
        theme="society",
        articles=[article],
    )

    projected = _to_essentiel_article(topic, article, 1, EssentielUserContext())

    assert isinstance(projected, EssentielArticle)
    assert projected.completed_at == completed_at
