"""Tests pour scripts/retag_and_promote_sources.py.

Couvre la logique pure (sans DB) : dérivation `granular_topics` (seuils, ordre
par share, top-K, vocab 51-slugs), résolution conservatrice (purge ancien vocab
sans wiper un vrai spécialiste), promotion catalogue, audit de couverture, et
régénération CSV (update colonnes + append promues + préservation commentaires).
"""

from __future__ import annotations

from scripts.retag_and_promote_sources import (
    Promotion,
    SourceMeta,
    compute_plan,
    derive_granular_topics,
    is_promotable,
    regenerate_csv_rows,
    resolve_new_topics,
)


def _meta(sid: str, **kw) -> SourceMeta:
    base = {
        "source_id": sid,
        "name": f"Source {sid}",
        "url": f"https://{sid}.test/",
        "theme": "society",
        "type": "article",
        "is_curated": False,
        "bias_stance": "center",
        "reliability_score": "high",
        "description": "Desc.",
        "score_independence": 0.7,
        "score_rigor": 0.7,
        "score_ux": 0.7,
        "source_tier": "mainstream",
        "granular_topics": None,
        "articles_30d": 50,
    }
    base.update(kw)
    return SourceMeta(**base)


# --------------------------------------------------------------------------- #
# derive_granular_topics
# --------------------------------------------------------------------------- #
def test_derive_keeps_only_significant_specialties_ordered_by_share():
    # total=100 : politics 40% (dominant), economy 12%, sport 5% (sous min_share),
    # foo invalide ignoré.
    counts = {"politics": 40, "economy": 12, "sport": 5, "foo-old": 30}
    out = derive_granular_topics(counts, total=100)
    assert out == ["politics", "economy"]  # sport < 0.10, foo-old hors taxonomie


def test_derive_respects_min_count_even_with_high_share():
    # share haut mais volume < MIN_COUNT (4) -> écarté.
    counts = {"factcheck": 3}
    assert derive_granular_topics(counts, total=5) == []


def test_derive_caps_at_top_k():
    counts = {
        s: 100 - i
        for i, s in enumerate(
            [
                "politics",
                "economy",
                "work",
                "justice",
                "health",
                "science",
                "tech",
                "energy",
            ]
        )
    }
    out = derive_granular_topics(counts, total=1000, min_share=0.0)
    assert len(out) == 6
    assert out[0] == "politics"  # le plus gros share en tête


def test_derive_zero_total_is_empty():
    assert derive_granular_topics({"politics": 10}, total=0) == []


# --------------------------------------------------------------------------- #
# resolve_new_topics (conservateur)
# --------------------------------------------------------------------------- #
def test_resolve_derived_wins():
    assert resolve_new_topics(["politics"], ["social-justice"]) == ["politics"]


def test_resolve_empty_derived_purges_old_vocab_keeps_valid():
    # "social-justice" (ancien vocab) purgé, "health" (valide) conservé.
    assert resolve_new_topics([], ["social-justice", "health"]) == ["health"]


def test_resolve_empty_derived_all_old_vocab_becomes_none():
    assert resolve_new_topics([], ["social-justice", "energy-transition"]) is None


def test_resolve_empty_derived_preserves_thin_valid_specialist():
    # Spécialiste mince déjà en 51-slugs : on ne wipe pas faute d'articles.
    assert resolve_new_topics([], ["factcheck"]) == ["factcheck"]


# --------------------------------------------------------------------------- #
# is_promotable
# --------------------------------------------------------------------------- #
def test_promotable_happy_path():
    assert is_promotable(_meta("a")) is True


def test_not_promotable_already_curated():
    assert is_promotable(_meta("a", is_curated=True)) is False


def test_not_promotable_unknown_bias():
    assert is_promotable(_meta("a", bias_stance="unknown")) is False


def test_not_promotable_low_reliability():
    assert is_promotable(_meta("a", reliability_score="low")) is False


def test_not_promotable_low_volume():
    assert is_promotable(_meta("a", articles_30d=5)) is False


# --------------------------------------------------------------------------- #
# compute_plan (orchestration pure)
# --------------------------------------------------------------------------- #
def test_compute_plan_retags_and_promotes_and_audits():
    metas = [
        # Spécialiste politics, non curée, productive -> re-tag + promotion.
        _meta("s1", granular_topics=["democracy"]),
        # Déjà curée, généraliste sans concentration -> purge ancien vocab.
        _meta("s2", is_curated=True, granular_topics=["macro", "labor-market"]),
    ]
    topic_stats = {
        # economy 8% < MIN_SHARE -> écarté ; sport 12% gardé après politics.
        "s1": {"politics": 50, "sport": 12, "economy": 8},
        "s2": {"politics": 10, "economy": 10, "work": 10, "health": 10},  # éparpillé
    }
    totals = {"s1": 100, "s2": 100}

    plan = compute_plan(metas, topic_stats, totals)

    # s1 re-taggé politics(dominant)+sport, economy écarté (<10%), et promu.
    assert plan.granular_after["s1"] == ["politics", "sport"]
    assert any(p.source_id == "s1" for p in plan.promotions)
    assert plan.curated_after["s1"] is True

    # s2 : chaque topic = 10% pile -> retenus (share >= 0.10), ordre alpha-stable
    # par compte égal. Pas promu (déjà curé).
    assert set(plan.granular_after["s2"]) == {"economy", "health", "politics", "work"}
    assert not any(p.source_id == "s2" for p in plan.promotions)

    # Audit : politics couvert (s1 dominant + s2), economy couvert.
    assert plan.coverage_contains["politics"] >= 1
    assert plan.coverage_dominant["politics"] == 1  # s1 dominant
    # Un slug sans aucune source curée tombe dans les trous.
    assert "gaming" in plan.coverage_gaps


def test_compute_plan_no_articles_keeps_valid_topics_no_change():
    metas = [_meta("s1", is_curated=True, granular_topics=["factcheck"])]
    plan = compute_plan(metas, {}, {})
    assert plan.granular_after["s1"] == ["factcheck"]
    assert plan.topic_changes == []  # inchangé -> pas de write
    assert plan.coverage_contains["factcheck"] == 1


# --------------------------------------------------------------------------- #
# regenerate_csv_rows
# --------------------------------------------------------------------------- #
_FIELDS = ["Name", "URL", "Status", "granular_topics", "source_tier"]


def test_csv_updates_existing_row_and_promotes_status():
    rows = [
        {
            "Name": "# --- section ---",
            "URL": "",
            "Status": "",
            "granular_topics": "",
            "source_tier": "",
        },
        {
            "Name": "S1",
            "URL": "https://s1.test/",
            "Status": "INDEXED",
            "granular_topics": '["old"]',
            "source_tier": "mainstream",
        },
    ]
    out = regenerate_csv_rows(
        rows,
        _FIELDS,
        granular_by_url={"https://s1.test": ["politics", "economy"]},
        curated_by_url={"https://s1.test": True},
        promotions=[],
    )
    # Ligne commentaire préservée.
    assert out[0]["Name"] == "# --- section ---"
    # Colonnes mises à jour, INDEXED -> CURATED.
    assert out[1]["granular_topics"] == '["politics", "economy"]'
    assert out[1]["Status"] == "CURATED"


def test_csv_never_downgrades_curated_or_touches_archived():
    rows = [
        {
            "Name": "C",
            "URL": "https://c.test/",
            "Status": "CURATED",
            "granular_topics": "",
            "source_tier": "",
        },
        {
            "Name": "A",
            "URL": "https://a.test/",
            "Status": "ARCHIVED",
            "granular_topics": "",
            "source_tier": "",
        },
    ]
    out = regenerate_csv_rows(
        rows,
        _FIELDS,
        granular_by_url={"https://c.test": ["politics"], "https://a.test": ["sport"]},
        curated_by_url={"https://c.test": True, "https://a.test": False},
        promotions=[],
    )
    assert out[0]["Status"] == "CURATED"
    assert out[1]["Status"] == "ARCHIVED"  # jamais re-touché
    # granular_topics quand même rafraîchi pour la ligne curée.
    assert out[0]["granular_topics"] == '["politics"]'


def test_csv_appends_promotions_absent_from_csv():
    rows = [
        {
            "Name": "S1",
            "URL": "https://s1.test/",
            "Status": "CURATED",
            "granular_topics": "",
            "source_tier": "",
        },
    ]
    promo = Promotion(
        source_id="new",
        name="New Source",
        url="https://new.test/",
        theme="tech",
        type="youtube",
        bias_stance="center",
        reliability_score="high",
        description="Desc new",
        score_independence=0.8,
        score_rigor=0.7,
        score_ux=0.6,
        source_tier="deep",
        granular_topics=["ai", "tech"],
        articles_30d=40,
    )
    out = regenerate_csv_rows(
        rows,
        _FIELDS,
        granular_by_url={"https://s1.test": ["politics"]},
        curated_by_url={"https://s1.test": True},
        promotions=[promo],
    )
    assert len(out) == 2
    assert out[1]["Name"] == "New Source"
    assert out[1]["Status"] == "CURATED"
    assert out[1]["granular_topics"] == '["ai", "tech"]'


def test_csv_skips_promotion_already_present_by_url():
    rows = [
        {
            "Name": "S1",
            "URL": "https://s1.test/",
            "Status": "INDEXED",
            "granular_topics": "",
            "source_tier": "",
        },
    ]
    promo = Promotion(
        source_id="s1",
        name="S1",
        url="https://s1.test",
        theme="tech",
        type="article",
        bias_stance="center",
        reliability_score="high",
        description=None,
        score_independence=None,
        score_rigor=None,
        score_ux=None,
        source_tier="mainstream",
        granular_topics=["ai"],
        articles_30d=40,
    )
    out = regenerate_csv_rows(
        rows,
        _FIELDS,
        granular_by_url={"https://s1.test": ["ai"]},
        curated_by_url={"https://s1.test": True},
        promotions=[promo],
    )
    assert len(out) == 1  # pas de doublon (match URL, trailing slash ignoré)
