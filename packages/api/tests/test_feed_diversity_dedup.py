"""Diversité source + dédup cluster du scroll « Flâner » (GET /api/feed/).

Deux garde-fous runtime, additifs et sans schéma DB :
- `_apply_source_interleaving` : jamais 2 articles de la même source collés
  (réordonne, ne retire rien ; best-effort si la fin est mono-source).
- `_apply_cluster_dedup` : un même sujet (cluster de titres, Jaccard 0.4)
  n'apparaît qu'une fois dans le flux, en gardant le 1er (plus récent). La
  liste d'entrée n'est PAS mutée → le snapshot `pre_regroup_map` conserve la
  couverture complète pour le carrousel « Actu chaude ».
"""

from uuid import uuid4

from app.models.content import Content
from app.services.recommendation_service import RecommendationService


def _content(source_id, title: str, *, theme: str | None = None) -> Content:
    """Content transient (sans session) : suffisant pour les fonctions pures."""
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        theme=theme,
    )


# ─── _apply_source_interleaving ──────────────────────────────────────────────


def test_interleaving_breaks_adjacent_same_source():
    """3×A + 2×B → réordonné en A B A B A, zéro paire adjacente."""
    a, b = uuid4(), uuid4()
    items = [
        _content(a, "A1"),
        _content(a, "A2"),
        _content(a, "A3"),
        _content(b, "B1"),
        _content(b, "B2"),
    ]

    out = RecommendationService._apply_source_interleaving(items)

    # Aucune source identique en position adjacente (arrangement possible ici).
    assert all(
        out[i].source_id != out[i - 1].source_id for i in range(1, len(out))
    ), "aucune paire de sources adjacentes ne doit subsister"
    # On ne retire aucun article : même multiset d'ids.
    assert {c.id for c in out} == {c.id for c in items}


def test_interleaving_is_best_effort_on_mono_source_tail():
    """Fin mono-source impossible à casser → on laisse tel quel, sans crash."""
    a, b = uuid4(), uuid4()
    items = [_content(a, "A1"), _content(b, "B1"), _content(a, "A2"), _content(a, "A3")]

    out = RecommendationService._apply_source_interleaving(items)

    # Rien n'est retiré ; l'unique adjacence de queue (A2,A3) est tolérée.
    assert {c.id for c in out} == {c.id for c in items}
    adjacent = sum(
        1 for i in range(1, len(out)) if out[i].source_id == out[i - 1].source_id
    )
    assert adjacent <= 1


# ─── _apply_cluster_dedup ────────────────────────────────────────────────────


def test_cluster_dedup_hides_narrative_duplicates():
    """Deux titres quasi-identiques (sources différentes) → un seul survit."""
    src_x, src_y, src_z = uuid4(), uuid4(), uuid4()
    dup_first = _content(src_x, "Réforme des retraites adoptée par le Parlement")
    dup_second = _content(src_y, "Réforme des retraites adoptée au Parlement")
    singleton = _content(src_z, "Tempête Ciaran frappe la côte atlantique bretonne")
    articles = [dup_first, dup_second, singleton]

    out = RecommendationService._apply_cluster_dedup(articles)

    out_ids = [c.id for c in out]
    # Le doublon narratif est masqué, le singleton conservé.
    assert dup_first.id in out_ids, "on garde le 1er (plus récent) du cluster"
    assert dup_second.id not in out_ids, "le doublon de cluster est masqué"
    assert singleton.id in out_ids
    assert len(out) == 2


def test_cluster_dedup_does_not_mutate_input():
    """La liste d'entrée (future `pre_regroup_map`) garde la couverture complète."""
    src_x, src_y = uuid4(), uuid4()
    articles = [
        _content(src_x, "Le président annonce une réforme fiscale ambitieuse"),
        _content(src_y, "Le président annonce une réforme fiscale majeure"),
    ]
    snapshot_ids = [c.id for c in articles]

    out = RecommendationService._apply_cluster_dedup(articles)

    # L'entrée reste intacte : le carrousel « Actu chaude » voit toujours tout.
    assert [c.id for c in articles] == snapshot_ids
    # Le scroll linéaire, lui, est dédupliqué.
    assert len(out) == 1
