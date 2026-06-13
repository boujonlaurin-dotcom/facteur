"""Tests du sélecteur hybride du mot du jour (extraction / scoring / occurrence)."""

from types import SimpleNamespace
from uuid import uuid4

from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialSubject,
)
from app.services.grille_quality_pool import get_quality_pool
from app.services.grille_selector import (
    FIELD_DESCRIPTION,
    FIELD_TITLE,
    _build_cluster_index,
    _scan_field,
    _select_from_corpus,
    _subject_label_words,
)

_POOL_INDEX = {w.lower(): w for w in get_quality_pool()}


def _art(title, description="", *, content_id=None, source="Le Monde", url="https://x.fr/a"):
    return SimpleNamespace(
        id=content_id or uuid4(),
        title=title,
        description=description,
        url=url,
        source=SimpleNamespace(name=source),
    )


def _ctx(subjects=None, clusters=None):
    return EditorialGlobalContext(
        subjects=subjects or [],
        cluster_data=clusters or [],
        generated_at=__import__("datetime").datetime.utcnow(),
    )


# ----- _scan_field ----------------------------------------------------------


def test_scan_whole_word_with_accents():
    hits = _scan_field("Les grèves se durcissent", _POOL_INDEX)
    assert hits["GREVES"] == ("grèves", True)


def test_scan_flexion():
    hits = _scan_field("La transition climatique s'accélère", _POOL_INDEX)
    assert hits["CLIMAT"] == ("climatique", False)


def test_scan_prefers_whole_word_over_flexion():
    hits = _scan_field("Le climat et la loi climatique", _POOL_INDEX)
    assert hits["CLIMAT"] == ("climat", True)


def test_scan_empty_when_absent():
    assert _scan_field("Aucune correspondance ici", _POOL_INDEX) == {}
    assert _scan_field(None, _POOL_INDEX) == {}


# ----- _select_from_corpus (cœur pur) ---------------------------------------


def test_selects_word_present_in_title():
    corpus = [
        _art("La rencontre de la coupe approche"),
        _art("Nouvel espoir pour le climat à Belém"),
    ]
    sel = _select_from_corpus(corpus, {}, set(), exclude=None)
    assert sel is not None
    assert sel.word == "CLIMAT"
    assert sel.field == FIELD_TITLE
    assert sel.match_surface == "climat"
    assert sel.snippet == "Nouvel espoir pour le climat à Belém"


def test_title_whole_word_beats_description_only():
    corpus = [
        _art("Sans rapport", "On parle ici du budget de l'État"),
        _art("Le climat au coeur du sommet"),
    ]
    sel = _select_from_corpus(corpus, {}, set(), exclude=None)
    # CLIMAT (titre mot-entier +3) > BUDGET (desc mot-entier +2).
    assert sel.word == "CLIMAT"


def test_frequency_accumulates_across_articles():
    corpus = [
        _art("Le climat se réchauffe"),
        _art("Climat : nouveau rapport"),
        _art("Le budget en débat"),
    ]
    sel = _select_from_corpus(corpus, {}, set(), exclude=None)
    # CLIMAT apparaît dans 2 titres (3+3=6) > BUDGET (3).
    assert sel.word == "CLIMAT"


def test_description_occurrence_builds_window_snippet():
    long_desc = (
        "Texte d'introduction assez long pour dépasser la fenêtre. " * 4
        + "Le sommet européen s'achève. "
        + "Et beaucoup de texte derrière encore. " * 4
    )
    corpus = [_art("Titre neutre", long_desc)]
    sel = _select_from_corpus(corpus, {}, set(), exclude=None)
    assert sel is not None
    assert sel.field == FIELD_DESCRIPTION
    assert "sommet" in sel.snippet.lower()
    assert sel.match_surface == "sommet"


def test_excludes_yesterday_word():
    corpus = [_art("Le climat et le budget en débat")]
    sel = _select_from_corpus(corpus, {}, set(), exclude="CLIMAT")
    assert sel is not None
    assert sel.word != "CLIMAT"


def test_cluster_bonus_breaks_tie_by_score():
    cid = uuid4()
    corpus = [
        _art("Le budget en hausse", content_id=uuid4()),
        _art("Le climat se réchauffe", content_id=cid),
    ]
    # Le climat est dans un top cluster → bonus +2 (5) > budget (3).
    cluster_index = {str(cid): 0}
    sel = _select_from_corpus(corpus, cluster_index, set(), exclude=None)
    assert sel.word == "CLIMAT"


def test_subject_label_bonus():
    corpus = [
        _art("Le budget en hausse"),
        _art("Le climat se réchauffe"),
    ]
    sel = _select_from_corpus(corpus, {}, {"CLIMAT"}, exclude=None)
    assert sel.word == "CLIMAT"


def test_deterministic_alpha_tiebreak():
    # Deux mots à score strictement égal, sans cluster : tie-break alpha.
    corpus = [_art("Le budget et le climat"), _art("Climat et budget")]
    sel1 = _select_from_corpus(corpus, {}, set(), exclude=None)
    sel2 = _select_from_corpus(list(reversed(corpus)), {}, set(), exclude=None)
    assert sel1.word == sel2.word  # stable quelle que soit l'ordre du corpus


def test_returns_none_when_no_quality_word():
    corpus = [_art("Aucun terme pertinent ici ou la")]
    assert _select_from_corpus(corpus, {}, set(), exclude=None) is None


# ----- helpers contexte -----------------------------------------------------


def test_build_cluster_index_keeps_lowest_rank():
    cid = str(uuid4())
    ctx = _ctx(
        clusters=[
            {"content_ids": [cid]},
            {"content_ids": [cid]},
        ]
    )
    index = _build_cluster_index(ctx)
    assert index[cid] == 0


def test_subject_label_words_normalized():
    subj = EditorialSubject(
        rank=1, topic_id="t1", label="Le climat mondial", selection_reason="x"
    )
    words = _subject_label_words(_ctx(subjects=[subj]))
    assert "CLIMAT" in words


def test_helpers_handle_none_ctx():
    assert _build_cluster_index(None) == {}
    assert _subject_label_words(None) == set()
