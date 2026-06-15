"""Tests hermétiques pour `scripts/llm_annotate_titles.py`.

Le script délègue prompt + validation au `LLMBiasAnnotationService` (testé
exhaustivement dans `tests/services/test_llm_bias_annotation_service.py`).
Les tests ici couvrent la logique script-spécifique : few-shot diversifié
depuis le gold, itération de dataset selon mode, run dry-run end-to-end.
"""

from __future__ import annotations

import asyncio
import json
from unittest.mock import AsyncMock, MagicMock

from app.services.llm_bias_annotation_service import SCHEMA_DESCRIPTION
from scripts.llm_annotate_titles import (
    annotate_one,
    build_fewshot_examples,
    build_system_prompt,
    iter_perspectives_to_annotate,
    run,
)


# ---------------------------------------------------------------------------
# Toy dataset (couvre po_reviewed, dropped, multi-bias)
# ---------------------------------------------------------------------------


def _toy_dataset() -> dict:
    return {
        "clusters": [
            {
                "cluster_key": "fixture",
                "reference_article_id": "REF",
                "articles": [
                    {
                        "id": "REF",
                        "title": "Trump bat Massie",
                        "bias_stance": "center",
                    },
                    {
                        "id": "ALT1",
                        "title": "Trump écrase Massie : la mainmise",
                        "bias_stance": "left",
                        "annotations": {
                            "po_synchronous": {
                                "po_reviewed": True,
                                "target_spans": [
                                    {
                                        "start": 6,
                                        "end": 12,
                                        "text": "écrase",
                                        "category": "editorial_angle",
                                        "weight": 1.0,
                                    },
                                    {
                                        "start": 25,
                                        "end": 33,
                                        "text": "mainmise",
                                        "category": "framing_noun",
                                        "weight": 1.0,
                                    },
                                ],
                                "exclude_spans": [],
                                "notes": "verbes chargés",
                            },
                        },
                    },
                    {
                        "id": "ALT2",
                        "title": "Trump élimine Massie",
                        "bias_stance": "right",
                        "annotations": {
                            "po_synchronous": {
                                "po_reviewed": False,
                                "target_spans": [],
                                "exclude_spans": [],
                            },
                        },
                    },
                    {
                        "id": "ALT3",
                        "title": "Massie battu en primaire",
                        "bias_stance": "left",
                        "annotations": {
                            "dropped": True,
                            "po_synchronous": {
                                "po_reviewed": False,
                                "target_spans": [],
                                "exclude_spans": [],
                            },
                        },
                    },
                ],
            },
        ],
    }


# ---------------------------------------------------------------------------
# iter_perspectives_to_annotate
# ---------------------------------------------------------------------------


def test_iter_blind_yields_only_reviewed():
    out = list(iter_perspectives_to_annotate(_toy_dataset(), mode="blind"))
    assert len(out) == 1
    assert out[0][2]["id"] == "ALT1"


def test_iter_fill_yields_only_unreviewed_and_not_dropped():
    out = list(iter_perspectives_to_annotate(_toy_dataset(), mode="fill"))
    assert len(out) == 1
    assert out[0][2]["id"] == "ALT2"  # ALT3 droppée


def test_iter_all_yields_both_but_not_dropped():
    out = list(iter_perspectives_to_annotate(_toy_dataset(), mode="all"))
    ids = {p[2]["id"] for p in out}
    assert ids == {"ALT1", "ALT2"}


def test_iter_provides_peers_excluding_self():
    out = list(iter_perspectives_to_annotate(_toy_dataset(), mode="all"))
    by_id = {p[2]["id"]: p for p in out}
    persp_peers = by_id["ALT1"][3]
    assert "Trump écrase Massie : la mainmise" not in persp_peers
    assert len(persp_peers) >= 1


# ---------------------------------------------------------------------------
# Few-shot building + prompt assembly
# ---------------------------------------------------------------------------


def test_build_fewshot_examples_picks_reviewed_only():
    examples = build_fewshot_examples(_toy_dataset())
    # 1 seule perspective po_reviewed dans le toy dataset → 1 exemple
    assert len(examples) == 1
    assert "écrase" in examples[0]
    assert "bias left" in examples[0]


def test_build_system_prompt_combines_service_schema_and_fewshot():
    prompt = build_system_prompt(_toy_dataset())
    assert prompt.startswith(SCHEMA_DESCRIPTION)
    assert "Exemples calibrés par le PO" in prompt
    assert "écrase" in prompt


def test_build_system_prompt_returns_just_schema_when_no_reviewed():
    empty_dataset = {
        "clusters": [
            {
                "cluster_key": "k",
                "reference_article_id": "REF",
                "articles": [
                    {"id": "REF", "title": "ref", "bias_stance": "center"},
                ],
            }
        ]
    }
    prompt = build_system_prompt(empty_dataset)
    assert prompt == SCHEMA_DESCRIPTION


# ---------------------------------------------------------------------------
# annotate_one — délégation au service
# ---------------------------------------------------------------------------


def test_annotate_one_dry_returns_empty(monkeypatch):
    monkeypatch.setenv("LLM_ANNOTATE_DRY_RUN", "1")
    persp = {"id": "x", "title": "any", "bias_stance": "left"}
    result = asyncio.run(
        annotate_one(
            service=None,
            persp=persp,
            ref_title="ref",
            peers=[],
            fewshot_examples=[],
        )
    )
    assert result == {
        "target_spans": [],
        "exclude_spans": [],
        "notes": "DRY RUN — aucun appel API",
        "confidence": 0.0,
    }


def test_annotate_one_delegates_to_service_with_correct_args():
    service = MagicMock()
    service.annotate_variant = AsyncMock(
        return_value={"target_spans": [], "exclude_spans": [], "notes": "", "confidence": 0.5}
    )
    persp = {"id": "x", "title": "Trump écrase Massie", "bias_stance": "left"}
    asyncio.run(
        annotate_one(
            service=service,
            persp=persp,
            ref_title="Trump bat Massie",
            peers=["peer1"],
            fewshot_examples=["### ex"],
        )
    )
    service.annotate_variant.assert_awaited_once_with(
        ref_title="Trump bat Massie",
        variant_title="Trump écrase Massie",
        bias_stance="left",
        peers=["peer1"],
        fewshot_examples=["### ex"],
    )


# ---------------------------------------------------------------------------
# End-to-end dry-run — invariant po_synchronous + skip dropped
# ---------------------------------------------------------------------------


def test_run_dry_does_not_mutate_po_synchronous(tmp_path, monkeypatch):
    monkeypatch.setenv("LLM_ANNOTATE_DRY_RUN", "1")
    dataset_path = tmp_path / "ds.json"
    ds = _toy_dataset()
    dataset_path.write_text(json.dumps(ds), encoding="utf-8")
    out_path = tmp_path / "out.json"

    asyncio.run(
        run(
            dataset_path=dataset_path,
            mode="blind",
            model="mistral-medium-latest",
            out_path=out_path,
            limit=None,
        )
    )

    out_ds = json.loads(out_path.read_text(encoding="utf-8"))
    alt1 = next(a for a in out_ds["clusters"][0]["articles"] if a["id"] == "ALT1")
    assert (
        alt1["annotations"]["po_synchronous"]["target_spans"]
        == ds["clusters"][0]["articles"][1]["annotations"]["po_synchronous"]["target_spans"]
    )
    assert "llm_pass2" in alt1["annotations"]
    assert alt1["annotations"]["llm_pass2"]["annotated_by"] == "dry-run"


def test_run_dry_skips_dropped(tmp_path, monkeypatch):
    monkeypatch.setenv("LLM_ANNOTATE_DRY_RUN", "1")
    dataset_path = tmp_path / "ds.json"
    dataset_path.write_text(json.dumps(_toy_dataset()), encoding="utf-8")
    out_path = tmp_path / "out.json"

    asyncio.run(
        run(
            dataset_path=dataset_path,
            mode="all",
            model="mistral-medium-latest",
            out_path=out_path,
            limit=None,
        )
    )

    out_ds = json.loads(out_path.read_text(encoding="utf-8"))
    alt3 = next(a for a in out_ds["clusters"][0]["articles"] if a["id"] == "ALT3")
    assert "llm_pass2" not in alt3["annotations"]


def test_run_dry_respects_limit(tmp_path, monkeypatch):
    monkeypatch.setenv("LLM_ANNOTATE_DRY_RUN", "1")
    dataset_path = tmp_path / "ds.json"
    dataset_path.write_text(json.dumps(_toy_dataset()), encoding="utf-8")
    out_path = tmp_path / "out.json"

    asyncio.run(
        run(
            dataset_path=dataset_path,
            mode="all",
            model="mistral-medium-latest",
            out_path=out_path,
            limit=1,
        )
    )

    out_ds = json.loads(out_path.read_text(encoding="utf-8"))
    annotated = [
        a
        for a in out_ds["clusters"][0]["articles"]
        if "llm_pass2" in (a.get("annotations") or {})
    ]
    assert len(annotated) == 1
