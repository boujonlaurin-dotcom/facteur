"""Tests du cœur de promotion `app.services.source_promotion`.

La logique est aussi couverte via le script CLI (qui la ré-exporte) dans
`tests/scripts/test_retag_and_promote_sources.py` ; ici on la teste en
first-class depuis l'app + un garde-fou anti-régression sur l'import (le job ne
doit JAMAIS réimporter `scripts`, sinon le conteneur Docker plante au boot —
`scripts/` n'est pas embarqué dans l'image).
"""

from __future__ import annotations

from app.services.source_promotion import (
    PROMO_DENYLIST_RAW,
    PROMO_EXCLUDED_BIAS,
    SourceMeta,
    compute_promotions,
    is_promotable,
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


def test_excluded_bias_derived_from_reco_gate():
    assert frozenset({"unknown", "alternative"}) == PROMO_EXCLUDED_BIAS


def test_gate_excludes_alternative_and_denylist_keeps_specialized():
    assert is_promotable(_meta("ok")) is True
    assert is_promotable(_meta("spec", bias_stance="specialized")) is True
    assert is_promotable(_meta("alt", bias_stance="alternative")) is False
    assert is_promotable(_meta("deny", url=next(iter(PROMO_DENYLIST_RAW)))) is False


def test_compute_promotions_filters_and_keeps_granular_topics():
    metas = [
        _meta("ok", granular_topics=["politics"]),
        _meta("alt", bias_stance="alternative"),
        _meta("thin", articles_30d=5),
    ]
    promos = compute_promotions(metas)
    assert {p.source_id for p in promos} == {"ok"}
    assert promos[0].granular_topics == ["politics"]  # conservé, jamais dérivé


def test_promotion_job_does_not_import_scripts_package():
    # Garde-fou anti-régression du crash boot Docker (ModuleNotFoundError:
    # No module named 'scripts') : le job passe par app.services, pas scripts.
    import inspect

    import app.jobs.promote_sources_job as job

    src = inspect.getsource(job)
    assert "import scripts" not in src
    assert "from scripts" not in src
