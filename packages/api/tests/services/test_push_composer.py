import json
from datetime import UTC, date, datetime
from types import SimpleNamespace
from uuid import UUID

from app.services.push_composer import (
    DAILY_DIGEST_INTRO,
    ComposedPush,
    _truncate_fact,
    article_route,
    compose_daily_digest,
    compose_source_alert,
    compose_topic_alert,
)
from app.services.source_alert_producer import SourceAlertCandidate
from app.services.topic_alert_producer import TopicAlertCandidate

TARGET = date(2026, 7, 18)
CONTENT_ID = UUID("00000000-0000-4000-8000-0000000000a1")
SOURCE_ID = UUID("00000000-0000-4000-8000-0000000000b2")
TOPIC_ID = UUID("00000000-0000-4000-8000-0000000000b3")

# Miroir du test mobile `push_route_resolution_test.dart` : toute route ajoutée
# ici doit être ajoutée là-bas, où elle est résolue contre le vrai GoRouter.
# C'est ce couple de tests qui empêche de réémettre une route morte.
EMITTED_ROUTE_SHAPES = {"/digest", "/flux-continu/content/<id>"}


def _essentiel(titles: list[str]):
    return SimpleNamespace(articles=[SimpleNamespace(title=t) for t in titles])


def _source_candidate(title: str = "Un titre") -> SourceAlertCandidate:
    return SourceAlertCandidate(
        source_id=SOURCE_ID,
        source_name="Le Canard Enchaîné",
        content_id=CONTENT_ID,
        content_title=title,
        published_at=datetime(2026, 7, 18, 8, 0, tzinfo=UTC),
        articles_30d=1,
        oldest_content_at=None,
    )


def _topic_candidate(title: str = "Un titre") -> TopicAlertCandidate:
    return TopicAlertCandidate(
        topic_id=TOPIC_ID,
        topic_name="Ligue 1",
        content_id=CONTENT_ID,
        content_title=title,
        published_at=datetime(2026, 7, 18, 8, 0, tzinfo=UTC),
        articles_30d=8,
        oldest_content_at=None,
    )


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


# --- Deep link des alertes (bug-alerte-push-lien-introuvable) ---------------


def test_article_route_targets_a_route_registered_client_side():
    """`/article/<id>` n'existe pas dans le GoRouter : ne jamais y revenir.

    C'est l'unique cause du « lien introuvable » au tap d'une alerte. La cible
    doit rester `/flux-continu/content/<id>`, enregistrée aussi bien sur `main`
    que sur les binaires `production` en circulation.
    """
    route = article_route(CONTENT_ID)
    assert route == f"/flux-continu/content/{CONTENT_ID}"
    assert not route.startswith("/article/")


def test_source_alert_route_opens_the_article():
    composed = compose_source_alert(
        _source_candidate(), "Publie environ une fois par mois"
    )
    assert composed.data["route"] == f"/flux-continu/content/{CONTENT_ID}"
    assert composed.data["kind"] == "source_alert"
    assert composed.data["content_id"] == str(CONTENT_ID)


def test_topic_alert_route_opens_the_article():
    composed = compose_topic_alert(
        _topic_candidate(), "Publie environ 2 fois par semaine"
    )
    assert composed.data["route"] == f"/flux-continu/content/{CONTENT_ID}"
    assert composed.data["kind"] == "topic_alert"
    assert composed.data["content_id"] == str(CONTENT_ID)


def test_every_composed_route_is_a_known_shape():
    """Verrou de contrat : aucune route push hors de l'ensemble connu.

    Ajouter une route ici oblige à l'ajouter dans le test mobile jumeau, seul
    endroit où elle est confrontée au vrai GoRouter.
    """

    def _shape(route: str) -> str:
        return route.replace(str(CONTENT_ID), "<id>")

    routes = {
        compose_daily_digest(_essentiel(["Un"]), TARGET).data["route"],
        compose_source_alert(_source_candidate(), "cadence").data["route"],
        compose_topic_alert(_topic_candidate(), "cadence").data["route"],
    }
    assert {_shape(r) for r in routes} == EMITTED_ROUTE_SHAPES
