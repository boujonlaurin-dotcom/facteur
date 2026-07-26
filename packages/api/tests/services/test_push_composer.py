import json
from datetime import date
from types import SimpleNamespace

from app.services.push_composer import (
    DAILY_DIGEST_INTRO,
    ComposedPush,
    _truncate_fact,
    compose_daily_digest,
)

TARGET = date(2026, 7, 18)


def _essentiel(titles: list[str]):
    return SimpleNamespace(articles=[SimpleNamespace(title=t) for t in titles])


def test_compose_caps_teasers_at_three_and_keeps_order():
    composed = compose_daily_digest(
        _essentiel(["Un", "Deux", "Trois", "Quatre"]), TARGET
    )
    assert json.loads(composed.data["teasers"]) == ["Un", "Deux", "Trois"]


def test_compose_body_is_intro_plus_first_title_for_ios_alert():
    composed = compose_daily_digest(_essentiel(["Titre phare", "Deux"]), TARGET)
    assert composed.body == "À retenir aujourd'hui : Titre phare"
    assert composed.title == "Facteur"


def test_compose_data_payload_contract():
    composed = compose_daily_digest(_essentiel(["Un"]), TARGET)
    assert isinstance(composed, ComposedPush)
    assert composed.data["route"] == "/digest"
    assert composed.data["kind"] == "daily_digest"
    assert composed.data["target_date"] == "2026-07-18"
    assert composed.data["intro"] == DAILY_DIGEST_INTRO


def test_compose_with_fewer_than_three_articles():
    composed = compose_daily_digest(_essentiel(["Seul"]), TARGET)
    assert json.loads(composed.data["teasers"]) == ["Seul"]
    assert composed.body == "À retenir aujourd'hui : Seul"


def test_truncate_fact_keeps_short_title_intact():
    assert _truncate_fact("Titre court") == "Titre court"


def test_truncate_fact_cuts_at_word_boundary_with_ellipsis():
    long_title = "mot " * 40  # 160 chars
    truncated = _truncate_fact(long_title)
    assert truncated.endswith("...")
    assert len(truncated) <= 90
    # Coupe au mot : pas de mot tronqué au milieu.
    assert truncated.removesuffix("...").split(" ")[-1] == "mot"


def test_truncate_fact_collapses_whitespace():
    assert _truncate_fact("Un   titre\n aéré") == "Un titre aéré"


def test_compose_truncates_long_teasers():
    long_title = "A" * 200
    composed = compose_daily_digest(_essentiel([long_title]), TARGET)
    teaser = json.loads(composed.data["teasers"])[0]
    assert teaser.endswith("...")
    assert len(teaser) <= 90
