"""Tests pour scripts/apply_source_evaluations.py + source_eval_schema.py.

Couvre : schéma rejette enum/em-dash invalides ; gate de confiance ;
sélection gap-only (curated protégé sans --refresh-curated) ; bias_origin='llm'
posé ; **reliability DÉRIVÉE des scores** (pas la valeur LLM) ; justifs +
sources_consulted acceptés/ignorés à l'écriture ; low-confidence -> unknown +
scores NULL + description gardée ; re-run idempotent.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from pydantic import ValidationError
from sqlalchemy import text

from app.models.enums import (
    BiasOrigin,
    BiasStance,
    ReliabilityScore,
    SourceType,
)
from app.models.source import Source
from scripts.apply_source_evaluations import (
    compute_changes,
    load_current,
    write_changes,
)
from scripts.source_eval_schema import EvaluationArtifact, SourceEvaluation

pytestmark = pytest.mark.asyncio


def make_source(**kw) -> Source:
    defaults = {
        "id": uuid4(),
        "name": "Gap Source",
        "url": "https://gap.test",
        "feed_url": f"https://gap.test/{uuid4()}.xml",
        "type": SourceType.ARTICLE,
        "theme": "society",
        "is_active": True,
        "is_curated": False,
        "bias_stance": BiasStance.UNKNOWN,
        "reliability_score": ReliabilityScore.UNKNOWN,
        "bias_origin": BiasOrigin.UNKNOWN,
    }
    defaults.update(kw)
    return Source(**defaults)


def ev(source_id, **kw) -> SourceEvaluation:
    base = {
        "source_id": str(source_id),
        "name": "X",
        "description": "Un média généraliste français reconnu.",
        "bias_stance": "center",
        "reliability_score": "high",
        "score_independence": 0.6,
        "score_rigor": 0.7,
        "score_ux": 0.8,
        "confidence": 0.9,
    }
    base.update(kw)
    return SourceEvaluation(**base)


# --------------------------------------------------------------------------- #
# Schéma
# --------------------------------------------------------------------------- #


def test_schema_rejects_bad_bias():
    with pytest.raises(ValidationError):
        ev(uuid4(), bias_stance="purple")


def test_schema_rejects_bad_reliability():
    with pytest.raises(ValidationError):
        ev(uuid4(), reliability_score="excellent")


def test_schema_rejects_em_dash_in_description():
    with pytest.raises(ValidationError):
        ev(uuid4(), description="Un média — souvent clivant.")


def test_schema_rejects_score_out_of_range():
    with pytest.raises(ValidationError):
        ev(uuid4(), score_rigor=1.4)


def test_gate_low_confidence_blanks_eval_keeps_description():
    e = ev(
        uuid4(), confidence=0.3, bias_stance="left", description="Présentation utile."
    )
    g = e.gated(0.5)
    assert g.bias_stance == "unknown"
    assert g.score_independence is None
    assert g.score_rigor is None
    assert g.derived_reliability() == "unknown"  # scores null -> unknown
    assert g.description == "Présentation utile."  # conservée


def test_gate_high_confidence_unchanged():
    e = ev(uuid4(), confidence=0.8, bias_stance="right")
    assert e.gated(0.5).bias_stance == "right"


# --------------------------------------------------------------------------- #
# compute_changes (pur)
# --------------------------------------------------------------------------- #


def _current(source_id, **over) -> dict:
    base = {
        "name": "S",
        "bias_origin": "unknown",
        "bias_stance": "unknown",
        "reliability_score": "unknown",
        "description": None,
        "score_independence": None,
        "score_rigor": None,
        "score_ux": None,
    }
    base.update(over)
    return {str(source_id): base}


def test_compute_writes_gap_sets_llm():
    sid = uuid4()
    art = EvaluationArtifact(evaluations=[ev(sid)])
    res = compute_changes(art, _current(sid), threshold=0.5, refresh_curated=False)
    assert len(res.writes) == 1
    assert res.writes[0].new["bias_origin"] == "llm"
    assert res.writes[0].new["bias_stance"] == "center"


def test_compute_writes_derived_reliability_not_llm_value():
    # L'éval prétend "low" mais les scores (rigor 0.7, indep 0.6) dérivent "medium".
    sid = uuid4()
    art = EvaluationArtifact(
        evaluations=[
            ev(sid, reliability_score="low", score_rigor=0.7, score_independence=0.6)
        ]
    )
    res = compute_changes(art, _current(sid), threshold=0.5, refresh_curated=False)
    assert res.writes[0].new["reliability_score"] == "medium"  # dérivé, pas "low"


def test_compute_accepts_rationales_and_sources():
    # Justifs + sources_consulted présents dans l'artefact -> acceptés, ignorés à
    # l'écriture (pas de champ DB), reliability toujours dérivée.
    sid = uuid4()
    art = EvaluationArtifact(
        evaluations=[
            ev(
                sid,
                bias_rationale="b",
                independence_rationale="i",
                rigor_rationale="r",
                ux_rationale="u",
                sources_consulted=["https://x.example"],
            )
        ]
    )
    res = compute_changes(art, _current(sid), threshold=0.5, refresh_curated=False)
    assert len(res.writes) == 1
    assert set(res.writes[0].new) == {
        "description",
        "bias_stance",
        "reliability_score",
        "score_independence",
        "score_rigor",
        "score_ux",
        "bias_origin",
    }


def test_compute_skips_curated_without_refresh():
    sid = uuid4()
    art = EvaluationArtifact(evaluations=[ev(sid)])
    cur = _current(sid, bias_origin="curated", bias_stance="center-right")
    res = compute_changes(art, cur, threshold=0.5, refresh_curated=False)
    assert res.writes == []
    assert res.skipped_curated == [str(sid)]


def test_compute_refresh_curated_writes():
    sid = uuid4()
    art = EvaluationArtifact(evaluations=[ev(sid)])
    cur = _current(sid, bias_origin="curated", bias_stance="center-right")
    res = compute_changes(art, cur, threshold=0.5, refresh_curated=True)
    assert len(res.writes) == 1


def test_compute_low_confidence_blanks():
    sid = uuid4()
    art = EvaluationArtifact(evaluations=[ev(sid, confidence=0.2, bias_stance="left")])
    res = compute_changes(art, _current(sid), threshold=0.5, refresh_curated=False)
    new = res.writes[0].new
    assert new["bias_stance"] == "unknown"
    assert new["score_independence"] is None
    assert new["description"]  # description conservée
    assert new["bias_origin"] == "llm"


def test_compute_missing_source_skipped():
    art = EvaluationArtifact(evaluations=[ev(uuid4())])
    res = compute_changes(art, {}, threshold=0.5, refresh_curated=False)
    assert len(res.skipped_missing) == 1
    assert res.writes == []


# --------------------------------------------------------------------------- #
# DB round-trip + idempotence
# --------------------------------------------------------------------------- #


async def test_apply_db_writes_and_idempotent(db_session):
    gap = make_source()
    curated = make_source(
        name="Curated",
        is_curated=True,
        bias_stance=BiasStance.CENTER_RIGHT,
        reliability_score=ReliabilityScore.HIGH,
        bias_origin=BiasOrigin.CURATED,
        description="Curé à la main.",
    )
    db_session.add_all([gap, curated])
    await db_session.commit()

    art = EvaluationArtifact(
        evaluations=[
            # L'éval prétend "low" mais scores (rigor 0.7, indep 0.6) -> dérivé "medium".
            ev(
                gap.id,
                bias_stance="center-left",
                reliability_score="low",
                score_rigor=0.7,
                score_independence=0.6,
            ),
            ev(curated.id, bias_stance="left"),  # doit être ignoré (curated)
        ]
    )
    ids = [e.source_id for e in art.evaluations]

    current = await load_current(db_session, ids)
    res = compute_changes(art, current, threshold=0.5, refresh_curated=False)
    await write_changes(db_session, res.writes)

    # gap écrit en llm ; reliability DÉRIVÉE (medium), pas la valeur LLM (low)
    r = await db_session.execute(
        text(
            "SELECT bias_stance, bias_origin, reliability_score FROM sources WHERE id=:i"
        ),
        {"i": gap.id},
    )
    row = r.mappings().one()
    assert row["bias_stance"] == "center-left"
    assert row["bias_origin"] == "llm"
    assert row["reliability_score"] == "medium"

    rc = await db_session.execute(
        text("SELECT bias_stance, bias_origin FROM sources WHERE id=:i"),
        {"i": curated.id},
    )
    rowc = rc.mappings().one()
    assert rowc["bias_stance"] == "center-right"  # inchangé
    assert rowc["bias_origin"] == "curated"

    # 2e passe : plus aucune écriture (old == new) -> idempotent
    current2 = await load_current(db_session, ids)
    res2 = compute_changes(art, current2, threshold=0.5, refresh_curated=False)
    assert res2.writes == []


async def test_apply_low_confidence_db(db_session):
    gap = make_source()
    db_session.add(gap)
    await db_session.commit()

    art = EvaluationArtifact(
        evaluations=[
            ev(gap.id, confidence=0.2, bias_stance="left", description="Desc gardée.")
        ]
    )
    current = await load_current(db_session, [str(gap.id)])
    res = compute_changes(art, current, threshold=0.5, refresh_curated=False)
    await write_changes(db_session, res.writes)

    r = await db_session.execute(
        text(
            "SELECT bias_stance, reliability_score, description, score_rigor, bias_origin "
            "FROM sources WHERE id=:i"
        ),
        {"i": gap.id},
    )
    row = r.mappings().one()
    assert row["bias_stance"] == "unknown"
    assert row["reliability_score"] == "unknown"
    assert row["score_rigor"] is None
    assert row["description"] == "Desc gardée."
    assert row["bias_origin"] == "llm"
