"""Story 12.8 — Tests ordre métier + jitter déterministe des carrousels.

Vérifie :
- Les positions de base suivent le nouvel ordre métier (favorite > new_source > community > saved > hot > deep).
- `_jitter_carousel_position()` est stable pour un couple (user_id, date, type) donné.
- Le jitter varie entre utilisateurs différents sur la même date.
- Le jitter varie entre dates différentes pour le même utilisateur.
- Le jitter reste dans la fenêtre ±2 autour de la base.
- Les positions finales sont toujours ≥ 1.
"""

from __future__ import annotations

import datetime
from uuid import uuid4

from app.services.recommendation_service import RecommendationService


class TestCarouselBaseOrder:
    def test_business_order_is_favorite_first_deep_last(self):
        """Ordre métier validé avec l'utilisateur :
        favorite > new_source > community > saved > hot > deep."""
        bp = RecommendationService._CAROUSEL_BASE_POSITIONS
        assert bp["favorite"] < bp["new_source"]
        assert bp["new_source"] < bp["community"]
        assert bp["community"] < bp["saved"]
        assert bp["saved"] < bp["hot"]
        assert bp["hot"] < bp["deep"]

    def test_decale_shares_community_slot_since_mutually_exclusive(self):
        """`decale` n'apparaît qu'en mode serein (qui exclut `community` et `hot`),
        donc il peut partager le slot de `community` sans collision réelle."""
        bp = RecommendationService._CAROUSEL_BASE_POSITIONS
        assert bp["decale"] == bp["community"]


class TestJitterDeterminism:
    def test_jitter_stable_for_same_user_same_day(self):
        user_id = uuid4()
        today = datetime.date(2026, 4, 19)
        pos_a = RecommendationService._jitter_carousel_position("hot", user_id, today)
        pos_b = RecommendationService._jitter_carousel_position("hot", user_id, today)
        assert pos_a == pos_b

    def test_jitter_varies_across_users_same_day(self):
        today = datetime.date(2026, 4, 19)
        positions = {
            RecommendationService._jitter_carousel_position("hot", uuid4(), today)
            for _ in range(30)
        }
        assert len(positions) > 1, "Jitter should vary across users"

    def test_jitter_varies_across_dates_same_user(self):
        user_id = uuid4()
        positions = {
            RecommendationService._jitter_carousel_position(
                "hot",
                user_id,
                datetime.date(2026, 4, 1) + datetime.timedelta(days=d),
            )
            for d in range(30)
        }
        assert len(positions) > 1, "Jitter should vary across dates"

    def test_jitter_varies_across_carousel_types(self):
        """Même user + date, différents types → différents jitters."""
        user_id = uuid4()
        today = datetime.date(2026, 4, 19)
        jitters = {
            RecommendationService._jitter_carousel_position(t, user_id, today)
            - RecommendationService._CAROUSEL_BASE_POSITIONS[t]
            for t in ("favorite", "new_source", "community", "saved", "hot", "deep")
        }
        # Not all 6 will be distinct, but at least 2 different jitter values expected
        assert len(jitters) >= 2


class TestJitterBounds:
    def test_jitter_stays_within_plus_minus_2_of_base(self):
        """Sur 200 tirages, tout écart au base doit être dans {-2, -1, 0, 1, 2}."""
        today = datetime.date(2026, 4, 19)
        base = RecommendationService._CAROUSEL_BASE_POSITIONS["favorite"]
        for _ in range(200):
            pos = RecommendationService._jitter_carousel_position(
                "favorite", uuid4(), today
            )
            delta = pos - base
            assert -2 <= delta <= 2, f"Jitter delta {delta} out of bounds"

    def test_position_never_below_one(self):
        """Même si base=3 et jitter=-2, la position finale ≥ 1 (et non 0/-1)."""
        today = datetime.date(2026, 4, 19)
        for _ in range(200):
            pos = RecommendationService._jitter_carousel_position(
                "favorite", uuid4(), today
            )
            assert pos >= 1

    def test_no_user_id_returns_raw_base(self):
        """Sans user_id, pas de seed → on renvoie la base brute."""
        today = datetime.date(2026, 4, 19)
        for carousel_type, base in (
            RecommendationService._CAROUSEL_BASE_POSITIONS.items()
        ):
            pos = RecommendationService._jitter_carousel_position(
                carousel_type, None, today
            )
            assert pos == base

    def test_unknown_carousel_type_falls_back_to_default(self):
        """Type inconnu → base par défaut (15) ± jitter, toujours ≥ 1."""
        today = datetime.date(2026, 4, 19)
        pos = RecommendationService._jitter_carousel_position(
            "mystery_carousel_type", uuid4(), today
        )
        assert 13 <= pos <= 17


class TestJitterDistribution:
    def test_jitter_uses_full_range(self):
        """Sur beaucoup de users, tous les jitters {-2..+2} doivent apparaître."""
        today = datetime.date(2026, 4, 19)
        base = RecommendationService._CAROUSEL_BASE_POSITIONS["hot"]
        observed = set()
        for _ in range(500):
            pos = RecommendationService._jitter_carousel_position(
                "hot", uuid4(), today
            )
            observed.add(pos - base)
        assert observed == {-2, -1, 0, 1, 2}, (
            f"Expected full jitter range, got {observed}"
        )
