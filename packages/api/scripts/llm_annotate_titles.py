"""Annotation LLM-assistée des perspectives (Story 7.4 → Phase 4 PR 2).

Itère sur le dataset d'annotations gold et demande au `LLMBiasAnnotationService`
(Mistral-medium par défaut, cf. décision PO 2026-05-20) de produire une
annotation au schéma v2 (`target_spans` avec `weight ∈ {0.25, 0.5, 1.0}` +
`exclude_spans` binaires + `justification` par span).

Écrit le résultat dans `annotations.llm_pass2` — **`po_synchronous` n'est
jamais modifié**. Le PO relit ensuite et fusionne manuellement.

Modes :
    --mode blind  : refait les perspectives PO-reviewed sans leur montrer le
                    gold (pour mesurer l'accord LLM↔PO via compare_annotations).
    --mode fill   : annote les perspectives unreviewed (po_reviewed=false).
    --mode all    : les deux.

Garde-fous :
    - Skip toute perspective `annotations.dropped == true` (ex : 3b85efa6).
    - `LLM_ANNOTATE_DRY_RUN=1` → mock réponse vide (utilisé par les tests).

Le validateur du service est tolérant : spans hallucinants ou catégorie/poids
invalides sont droppés + logués (graceful degradation). L'annotation reste
écrite dans le dataset avec les spans restants.

Usage :
    cd packages/api && python scripts/llm_annotate_titles.py \\
        --dataset ../../.context/highlight-dataset-llm-pass2-2026-05-20.json \\
        --mode blind --tag llm-pass-3
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections.abc import Iterable
from datetime import datetime, timezone
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import structlog  # noqa: E402

from app.services.llm_bias_annotation_service import (  # noqa: E402
    DEFAULT_MODEL,
    LLMBiasAnnotationService,
)

logger = structlog.get_logger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"


# ---------------------------------------------------------------------------
# Few-shot selection from PO-reviewed examples
# ---------------------------------------------------------------------------


def _format_example(persp: dict, ref_title: str) -> str:
    ann = persp["annotations"]["po_synchronous"]
    return (
        f"### Exemple — bias {persp.get('bias_stance', 'unknown')}\n"
        f"Titre référence : {ref_title}\n"
        f"Titre perspective : {persp['title']}\n"
        f"Annotation attendue :\n"
        + json.dumps(
            {
                "target_spans": ann.get("target_spans", []),
                "exclude_spans": ann.get("exclude_spans", []),
                "notes": ann.get("notes", ""),
                "confidence": 1.0,
            },
            ensure_ascii=False,
            indent=2,
        )
    )


def _select_fewshot(dataset: dict, max_examples: int = 10) -> list[dict]:
    """Sélectionne des perspectives PO-reviewed diversifiées (axes : bias,
    target catégorie × weight, exclude catégorie). Retourne la liste brute
    de candidats — `_build_examples_from_selection` les formate."""
    candidates: list[tuple[dict, str, set[tuple]]] = []
    for cluster in dataset["clusters"]:
        ref_id = cluster["reference_article_id"]
        ref = next(a for a in cluster["articles"] if a["id"] == ref_id)
        for art in cluster["articles"]:
            if art["id"] == ref_id:
                continue
            if (art.get("annotations") or {}).get("dropped"):
                continue
            ann = (art.get("annotations") or {}).get("po_synchronous") or {}
            if not ann.get("po_reviewed"):
                continue
            signature: set[tuple] = set()
            signature.add(("bias", art.get("bias_stance", "unknown")))
            for s in ann.get("target_spans", []):
                signature.add(
                    (
                        "target",
                        s.get("category", "?"),
                        float(s.get("weight", 1.0)),
                    )
                )
            for s in ann.get("exclude_spans", []):
                signature.add(("exclude", s.get("category", "?")))
            candidates.append((art, ref["title"], signature))

    selected: list[dict] = []
    covered: set[tuple] = set()
    while candidates and len(selected) < max_examples:
        candidates.sort(key=lambda c: len(c[2] - covered), reverse=True)
        best, ref_title, sig = candidates.pop(0)
        if not (sig - covered) and selected:
            break
        selected.append({"persp": best, "ref_title": ref_title})
        covered |= sig
    return selected


def build_fewshot_examples(dataset: dict, max_examples: int = 10) -> list[str]:
    """Formate les few-shot du gold dataset pour injection dans le prompt."""
    return [
        _format_example(s["persp"], s["ref_title"])
        for s in _select_fewshot(dataset, max_examples=max_examples)
    ]


def build_system_prompt(dataset: dict, max_examples: int = 10) -> str:
    """Construit le prompt système complet (service + few-shot gold)."""
    service = LLMBiasAnnotationService()
    return service.build_system_prompt(
        fewshot_examples=build_fewshot_examples(dataset, max_examples=max_examples)
    )


# ---------------------------------------------------------------------------
# LLM call (avec dry-run + delegation au service)
# ---------------------------------------------------------------------------


def _is_dry_run() -> bool:
    return os.environ.get("LLM_ANNOTATE_DRY_RUN") == "1"


async def annotate_one(
    service: LLMBiasAnnotationService | None,
    persp: dict,
    ref_title: str,
    peers: list[str],
    fewshot_examples: list[str],
) -> dict | None:
    """Annote UNE perspective via le service. Retourne dict validé ou None."""
    if _is_dry_run():
        return {
            "target_spans": [],
            "exclude_spans": [],
            "notes": "DRY RUN — aucun appel API",
            "confidence": 0.0,
        }
    assert service is not None, "service requis hors dry-run"
    return await service.annotate_variant(
        ref_title=ref_title,
        variant_title=persp["title"],
        bias_stance=persp.get("bias_stance", "unknown"),
        peers=peers,
        fewshot_examples=fewshot_examples,
    )


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def iter_perspectives_to_annotate(
    dataset: dict, mode: str
) -> Iterable[tuple[str, dict, dict, list[str]]]:
    """Yield (cluster_key, ref_article, perspective, peers) à annoter.

    Modes :
        - blind : po_reviewed=True (réannote pour mesurer l'accord LLM↔PO)
        - fill  : po_reviewed=False et non dropped
        - all   : les deux
    """
    for cluster in dataset["clusters"]:
        ref_id = cluster["reference_article_id"]
        ref = next(a for a in cluster["articles"] if a["id"] == ref_id)
        other_titles = [
            a["title"] for a in cluster["articles"] if a["id"] != ref_id
        ]
        for art in cluster["articles"]:
            if art["id"] == ref_id:
                continue
            ann = art.get("annotations") or {}
            if ann.get("dropped"):
                continue
            po = ann.get("po_synchronous") or {}
            reviewed = bool(po.get("po_reviewed"))
            if mode == "blind" and not reviewed:
                continue
            if mode == "fill" and reviewed:
                continue
            peers = [t for t in other_titles if t != art["title"]][:3]
            yield cluster["cluster_key"], ref, art, peers


async def run(
    dataset_path: Path,
    mode: str,
    model: str,
    out_path: Path,
    limit: int | None,
) -> None:
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))
    fewshot_examples = build_fewshot_examples(dataset)

    service: LLMBiasAnnotationService | None = None
    if not _is_dry_run():
        service = LLMBiasAnnotationService(model=model)
        if not service.is_ready:
            print(
                "❌ MISTRAL_API_KEY non défini. Set LLM_ANNOTATE_DRY_RUN=1 "
                "pour un run sans API.",
                file=sys.stderr,
            )
            sys.exit(2)

    n_done = 0
    n_failed = 0
    annotated_by = model if not _is_dry_run() else "dry-run"
    try:
        for cluster_key, ref, persp, peers in iter_perspectives_to_annotate(
            dataset, mode
        ):
            if limit is not None and n_done >= limit:
                break
            result = await annotate_one(
                service=service,
                persp=persp,
                ref_title=ref["title"],
                peers=peers,
                fewshot_examples=fewshot_examples,
            )
            if result is None:
                n_failed += 1
                logger.warning(
                    "llm_annotate.failed",
                    article_id=persp["id"][:8],
                    title=persp["title"][:60],
                )
                continue
            persp.setdefault("annotations", {})["llm_pass2"] = {
                "annotated_by": annotated_by,
                "annotated_at": datetime.now(timezone.utc).isoformat(),
                **result,
            }
            n_done += 1
            print(
                f"  ✅ {cluster_key[:24]:<24} {persp['id'][:8]} "
                f"targets={len(result['target_spans'])} "
                f"excludes={len(result['exclude_spans'])}"
            )
    finally:
        if service is not None:
            await service.close()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(dataset, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"\n✅ Annotation LLM terminée : {n_done} succès, {n_failed} échecs")
    print(f"   Dataset enrichi : {out_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True)
    parser.add_argument(
        "--mode", choices=("blind", "fill", "all"), default="blind"
    )
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--limit", type=int, default=None, help="Cap N annotations (utile en dev)"
    )
    parser.add_argument(
        "--tag",
        default="llm-pass2",
        help="Tag intégré au nom de fichier de sortie (défaut : llm-pass2).",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Chemin de sortie explicite (sinon : .context/highlight-dataset-<tag>-<date>.json)",
    )
    args = parser.parse_args()

    today = datetime.now(timezone.utc).date().isoformat()
    out_path = (
        Path(args.out)
        if args.out
        else (CONTEXT_DIR / f"highlight-dataset-{args.tag}-{today}.json")
    )

    asyncio.run(
        run(
            dataset_path=Path(args.dataset),
            mode=args.mode,
            model=args.model,
            out_path=out_path,
            limit=args.limit,
        )
    )


if __name__ == "__main__":
    main()
