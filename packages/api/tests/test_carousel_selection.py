"""Tests de la sélection partagée des carrousels (Story 32.1).

Deux volets :
- `pick_essentiel_type` : fonction pure de rotation date-seedée (déterminisme,
  premier-disponible dans l'ordre fixe, variation jour à jour).
- Complémentarité côté Flâner : `_build_carousels` retire bien le type réservé à
  l'Essentiel et sert les autres (câblage `pick_essentiel_type` dans le service).
"""

import datetime
from unittest.mock import patch
from uuid import uuid4

import pytest

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, SourceType
from app.models.source import Source
from app.services.recommendation.carousel_catalog import (
    PHASE_B_ORDER,
    CarouselBuildContext,
)
from app.services.recommendation.carousel_selection_service import (
    build_phase_b,
    pick_essentiel_type,
    select_essentiel_carousel,
)
from app.services.recommendation_service import RecommendationService

_DATE = datetime.date(2026, 7, 30)


# ==========================================================================
# pick_essentiel_type — fonction pure
# ==========================================================================


def test_pick_empty_eligible_returns_none():
    assert pick_essentiel_type(uuid4(), _DATE, set()) is None


def test_pick_single_type_returns_it():
    assert pick_essentiel_type(uuid4(), _DATE, {"community"}) == "community"


def test_pick_is_deterministic_for_same_user_and_date():
    user = uuid4()
    full = set(PHASE_B_ORDER)
    first = pick_essentiel_type(user, _DATE, full)
    for _ in range(5):
        assert pick_essentiel_type(user, _DATE, full) == first


def test_pick_returns_a_valid_eligible_type():
    user = uuid4()
    full = set(PHASE_B_ORDER)
    pick = pick_essentiel_type(user, _DATE, full)
    assert pick in full


def test_pick_first_available_in_rotation():
    """Retirer le type choisi fait tomber sur le suivant disponible dans la
    rotation (jamais None tant qu'il reste des éligibles)."""
    user = uuid4()
    remaining = set(PHASE_B_ORDER)
    seen = []
    while remaining:
        pick = pick_essentiel_type(user, _DATE, remaining)
        assert pick is not None
        assert pick in remaining
        seen.append(pick)
        remaining = remaining - {pick}
    # On a bien épuisé les 4 types, sans doublon.
    assert sorted(seen) == sorted(PHASE_B_ORDER)


def test_pick_varies_across_days():
    """La rotation date-seedée ne reste pas collée sur un seul type au fil du
    mois (offset = md5(user|date) % 4)."""
    user = uuid4()
    full = set(PHASE_B_ORDER)
    picks = {
        pick_essentiel_type(user, datetime.date(2026, 7, day), full)
        for day in range(1, 29)
    }
    assert len(picks) >= 2


def test_pick_same_eligible_same_pick_regardless_of_container_type():
    user = uuid4()
    as_set = pick_essentiel_type(user, _DATE, {"saved", "community"})
    as_list = pick_essentiel_type(user, _DATE, ["saved", "community"])
    as_dict = pick_essentiel_type(user, _DATE, {"saved": 1, "community": 2})
    assert as_set == as_list == as_dict


# ==========================================================================
# Complémentarité Flâner (DB) — le type réservé est retiré du feed
# ==========================================================================


def _now():
    return datetime.datetime.now(datetime.UTC)


def _make_source(name: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url="https://example.com",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )


def _make_content(source: Source, days_ago: float, title: str = "Article") -> Content:
    return Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=_now() - datetime.timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
    )


async def _seed_saved_and_community(db_session, user_id):
    """Rend `saved` ET `community` éligibles (≥ 3 items chacun).

    4 articles communautaires (et non 3) : le test de parité en trie un via
    `triaged_ids` et `community` doit rester éligible des deux côtés.
    """
    source = _make_source("Flaner")
    db_session.add(source)
    saved_arts = [_make_content(source, days_ago=1 + i) for i in range(3)]
    comm_arts = [
        _make_content(source, days_ago=1 + i, title=f"cm{i}") for i in range(4)
    ]
    for a in saved_arts + comm_arts:
        db_session.add(a)
    await db_session.flush()
    for i, a in enumerate(saved_arts):
        db_session.add(
            UserContentStatus(
                user_id=user_id,
                content_id=a.id,
                status=ContentStatus.UNSEEN,
                is_saved=True,
                saved_at=_now() - datetime.timedelta(minutes=i),
            )
        )
    for a in comm_arts:
        for _ in range(2):  # 2 tournesols communautaires
            db_session.add(
                UserContentStatus(
                    user_id=uuid4(),
                    content_id=a.id,
                    status=ContentStatus.UNSEEN,
                    is_liked=True,
                    liked_at=_now() - datetime.timedelta(hours=1),
                )
            )
    await db_session.commit()
    return comm_arts


async def _flaner_types(db_session, session_maker, user_id):
    service = RecommendationService(db_session, session_maker=session_maker)
    service.entity_overflow = []
    service.keyword_overflow = []
    _, carousels = await service._build_carousels([], {}, user_id=user_id)
    return {c["carousel_type"] for c in carousels}


@pytest.mark.asyncio
async def test_flaner_excludes_reserved_saved(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_saved_and_community(db_session, user_id)
    with patch(
        "app.services.recommendation_service.pick_essentiel_type",
        return_value="saved",
    ):
        types = await _flaner_types(db_session, fake_session_maker, user_id)
    assert "saved" not in types  # réservé à l'Essentiel
    assert "community" in types  # les autres restent servis


@pytest.mark.asyncio
async def test_flaner_excludes_reserved_community(db_session, fake_session_maker):
    user_id = uuid4()
    await _seed_saved_and_community(db_session, user_id)
    with patch(
        "app.services.recommendation_service.pick_essentiel_type",
        return_value="community",
    ):
        types = await _flaner_types(db_session, fake_session_maker, user_id)
    assert "community" not in types
    assert "saved" in types


@pytest.mark.asyncio
async def test_flaner_no_reservation_serves_both(db_session, fake_session_maker):
    """Sans réservation (aucun type retenu), Flâner sert les deux types."""
    user_id = uuid4()
    await _seed_saved_and_community(db_session, user_id)
    with patch(
        "app.services.recommendation_service.pick_essentiel_type",
        return_value=None,
    ):
        types = await _flaner_types(db_session, fake_session_maker, user_id)
    assert {"saved", "community"} <= types


@pytest.mark.asyncio
async def test_select_essentiel_carousel_matches_pick(db_session, fake_session_maker):
    """La construction paresseuse de l'Essentiel (`select_essentiel_carousel`)
    choisit le MÊME type que le couple Flâner `build_phase_b` + `pick_essentiel_type`
    — parité qui garantit la complémentarité cross-surface, y compris avec une
    mémoire de triage peuplée (Volet B : `triaged_ids` doit être appliqué
    symétriquement des deux côtés)."""
    user_id = uuid4()
    comm_arts = await _seed_saved_and_community(db_session, user_id)
    ctx = CarouselBuildContext(
        session=db_session,
        session_maker=fake_session_maker,
        user_id=user_id,
        consumed_ids=set(),
        triaged_ids={comm_arts[0].id},
    )
    full = await build_phase_b(ctx)
    expected = pick_essentiel_type(user_id, _DATE, full)
    lazy = await select_essentiel_carousel(ctx, _DATE)
    assert lazy is not None
    assert lazy.carousel_type == expected
    # L'article trié n'est servi par aucun des deux chemins.
    assert comm_arts[0].id not in {i.id for i in lazy.items}
