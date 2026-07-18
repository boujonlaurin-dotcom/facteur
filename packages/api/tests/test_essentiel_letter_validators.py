"""Tests purs du plan déterministe + validation de la lettre Essentiel (9.6)."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from app.schemas.content import SourceMini
from app.schemas.essentiel import EssentielArticle
from app.schemas.essentiel_letter import LetterSegmentType
from app.services.essentiel_letter_service import (
    LetterPlan,
    _parse_segments,
    _plan_covers_all_picks,
    _repair_dashes,
    build_letter_plan,
    validate_letter_output,
)


def _article(rank: int, theme: str | None, source_name: str = "Le Monde"):
    return EssentielArticle(
        content_id=uuid4(),
        title=f"Titre {rank}",
        url=f"https://example.org/{rank}",
        description=f"Description {rank}",
        published_at=datetime.now(UTC),
        source=SourceMini(
            id=uuid4(), name=source_name, logo_url=None, type="rss", theme=theme
        ),
        source_letter=source_name[0],
        section_label=f"Sujet {rank}",
        rank=rank,
        theme=theme,
    )


# ─── build_letter_plan ────────────────────────────────────────────────────


def test_plan_five_picks_three_themes():
    articles = [
        _article(1, "politique"),
        _article(2, "environnement"),
        _article(3, "economie"),
        _article(4, "economie"),
        _article(5, "tech"),
    ]
    plan = build_letter_plan(articles)
    assert plan.chapo_ranks == [1, 2]
    assert plan.rubriques == [("economie", [3, 4]), ("tech", [5])]
    assert _plan_covers_all_picks(plan, articles)


def test_plan_three_picks_keeps_rank2_in_rubriques():
    # < 4 picks : le chapô reste sur le seul sujet fort (rank 1).
    articles = [_article(1, "politique"), _article(2, "eco"), _article(3, "eco")]
    plan = build_letter_plan(articles)
    assert plan.chapo_ranks == [1]
    assert plan.rubriques == [("eco", [2, 3])]
    assert _plan_covers_all_picks(plan, articles)


def test_plan_theme_none_goes_to_chapo():
    articles = [
        _article(1, "politique"),
        _article(2, "eco"),
        _article(3, None),
        _article(4, "tech"),
    ]
    plan = build_letter_plan(articles)
    assert 3 in plan.chapo_ranks
    assert all(theme != "" for theme, _ in plan.rubriques)
    assert _plan_covers_all_picks(plan, articles)


def test_plan_single_theme_multi_picks_rubrique():
    articles = [
        _article(1, "international"),
        _article(2, "international"),
        _article(3, "international"),
    ]
    plan = build_letter_plan(articles)
    assert plan.chapo_ranks == [1]
    assert plan.rubriques == [("international", [2, 3])]


def test_plan_footer_excludes_covered_themes_and_caps_at_4():
    articles = [_article(1, "politique"), _article(2, "eco"), _article(3, "tech")]
    plan = build_letter_plan(
        articles,
        followed_themes=["eco", "culture", "sante", "sport", "sciences", "societe"],
    )
    assert "eco" not in plan.footer_themes
    assert plan.footer_themes == ["culture", "sante", "sport", "sciences"]


def test_plan_empty_articles():
    plan = build_letter_plan([])
    assert plan == LetterPlan()


# ─── validate_letter_output ───────────────────────────────────────────────

_PLAN = LetterPlan(chapo_ranks=[1, 2], rubriques=[("economie", [3])])


def _articles_for_plan():
    return [
        _article(1, "politique", "Le Monde"),
        _article(2, "environnement", "franceinfo"),
        _article(3, "economie", "Les Échos"),
    ]


_VALID_CHAPO = (
    "L'actualite du jour s'organise autour du budget presente par le "
    "gouvernement [[1]] et d'une vague de chaleur qui s'installe sur une "
    "large partie du pays [[2]]. Les prochaines heures doivent en preciser "
    "la portee."
)
_VALID_RUBRIQUE = (
    "Les negociations commerciales entre Bruxelles et Washington entrent "
    "dans leur derniere ligne droite [[3]]."
)


def _valid_raw():
    return {
        "chapo": _VALID_CHAPO,
        "rubriques": [{"theme": "economie", "text": _VALID_RUBRIQUE}],
    }


def test_validate_nominal_passes():
    blocks, violations = validate_letter_output(
        _valid_raw(), _PLAN, _articles_for_plan()
    )
    assert violations == []
    assert blocks is not None
    assert "[[1]]" in blocks["chapo"]
    assert "[[3]]" in blocks["economie"]


def test_validate_missing_marker_rejected():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace("[[2]]", "")
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert any("marqueurs" in v for v in violations)


def test_validate_duplicate_marker_rejected():
    raw = _valid_raw()
    raw["chapo"] += " Encore [[1]]."
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None


def test_validate_marker_in_wrong_block_rejected():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace("[[2]]", "[[3]]")
    raw["rubriques"][0]["text"] = raw["rubriques"][0]["text"].replace("[[3]]", "[[2]]")
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert len(violations) == 2


def test_validate_first_person_rejected():
    raw = _valid_raw()
    raw["rubriques"][0]["text"] = (
        "Je retiens surtout que les negociations commerciales avancent "
        "vers un accord equilibre [[3]]."
    )
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert any("personne" in v for v in violations)


def test_validate_em_dash_auto_repaired_silently():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace(
        "Les prochaines heures", "Un point reste ouvert — les prochaines heures"
    )
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert violations == []
    assert "—" not in blocks["chapo"]


def test_validate_exclamation_rejected():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace("la portee.", "la portee !")
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None


def test_validate_source_name_in_prose_rejected():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace(
        "le gouvernement", "le gouvernement selon Le Monde"
    )
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert any("Le Monde" in v for v in violations)


def test_validate_length_bounds_rejected():
    raw = _valid_raw()
    raw["rubriques"][0]["text"] = "Trop court [[3]]."
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert any("longueur" in v for v in violations)


def test_validate_markdown_and_url_rejected():
    raw = _valid_raw()
    raw["chapo"] = raw["chapo"].replace("du budget", "du **budget**")
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None


def test_validate_theme_mismatch_rejected():
    raw = _valid_raw()
    raw["rubriques"][0]["theme"] = "tech"
    blocks, violations = validate_letter_output(raw, _PLAN, _articles_for_plan())
    assert blocks is None
    assert any("themes du plan" in v for v in violations)


def test_validate_missing_chapo_rejected():
    blocks, violations = validate_letter_output(
        {"rubriques": []}, _PLAN, _articles_for_plan()
    )
    assert blocks is None


# ─── _parse_segments / _repair_dashes ─────────────────────────────────────


def test_parse_segments_interleaves_text_and_refs():
    articles = _articles_for_plan()
    rank_to_content = {a.rank: a.content_id for a in articles}
    segments = _parse_segments("Avant [[1]] milieu [[2]] fin.", rank_to_content)
    assert [s.type for s in segments] == [
        LetterSegmentType.TEXT,
        LetterSegmentType.SOURCE_REF,
        LetterSegmentType.TEXT,
        LetterSegmentType.SOURCE_REF,
        LetterSegmentType.TEXT,
    ]
    assert segments[1].content_id == rank_to_content[1]
    assert segments[3].content_id == rank_to_content[2]


def test_parse_segments_skips_unknown_rank():
    segments = _parse_segments("Texte [[9]] suite.", {1: uuid4()})
    assert all(s.type == LetterSegmentType.TEXT for s in segments)


def test_repair_dashes_variants():
    assert "—" not in _repair_dashes("a — b")
    assert "–" not in _repair_dashes("a–b")
    assert "  " not in _repair_dashes("a — b — c")
