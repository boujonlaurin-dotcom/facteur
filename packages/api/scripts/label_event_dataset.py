"""Pré-étiquetage LLM du gold « appartenance à un événement » + substrat de
revue PO (cf. `docs/maintenance/maintenance-clustering-calibration.md`).

Approche **cluster-assign** (1 prompt par pool, pas O(n²) de paires) : on
demande à Mistral-large de re-partitionner les titres d'un pool — qui
mentionnent tous l'entité seed — par **événement concret** (mêmes
acteurs / action / moment). Deux titres qui ne partagent que la personnalité
seed mais des sujets différents ne sont PAS le même événement → sentinelle
`NOISE`.

Le LLM ne fait qu'un *brouillon* : le PO relit ensuite chaque pool, corrige
les `event_id` et passe `label_reviewed=true` directement dans le JSON
`.context/`. Le validateur **n'écrase jamais** un article déjà revu.

Modes :
    --mode fill  : étiquette les pools NON revus (aucun `label_reviewed=true`).
    --mode blind : ré-étiquette les pools DÉJÀ revus, dans un champ fantôme
                   `event_id_blind`, pour mesurer l'accord LLM↔PO (qualité du
                   gold) sans toucher au gold.
    --mode all   : les deux.

Garde-fous :
    - `EVENT_LABEL_DRY_RUN=1` → stub déterministe (1 événement par article,
      slug `evt-<i>`), aucun appel API. Utilisé par les tests hermétiques.

Usage :
    cd packages/api && python scripts/label_event_dataset.py \\
        --dataset ../../.context/gold-events-2026-06-09.json --mode fill
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

import structlog  # noqa: E402

from app.services.editorial.llm_client import EditorialLLMClient  # noqa: E402

logger = structlog.get_logger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

NOISE_EVENT_ID = "NOISE"
DEFAULT_MODEL = "mistral-large-latest"


# ---------------------------------------------------------------------------
# Slug
# ---------------------------------------------------------------------------


def slugify(text: str) -> str:
    """slug stable : minuscules, sans accents, [a-z0-9-], compacté."""
    if not text:
        return "event"
    text = text.lower()
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = re.sub(r"[^a-z0-9]+", "-", text)
    text = text.strip("-")
    return text or "event"


# ---------------------------------------------------------------------------
# Prompt LLM
# ---------------------------------------------------------------------------


def build_system_prompt(seed_name: str) -> str:
    return (
        "Tu es un analyste média. On te donne une liste de titres d'actualité "
        f"qui mentionnent tous « {seed_name} ». Regroupe-les par ÉVÉNEMENT "
        "CONCRET : même acteurs, même action, même moment. "
        f"Deux titres qui ne partagent QUE la personnalité/organisation « {seed_name} » "
        "mais traitent de sujets différents ne sont PAS le même événement.\n\n"
        "Réponds en JSON STRICT :\n"
        '{"events": [{"event_id": "slug-court", "label": "Libellé humain", '
        '"article_indices": [0, 2]}], "noise_indices": [1, 3]}\n\n'
        "Règles :\n"
        "- `article_indices` = indices (0-based) des titres de l'événement.\n"
        "- Un événement doit regrouper ≥2 titres ; un titre isolé va dans "
        "`noise_indices`.\n"
        "- Chaque indice apparaît AU PLUS une fois (dans un seul événement, "
        "ou dans noise).\n"
        "- `event_id` : slug court, stable, en minuscules (ex: "
        '"iran-israel-frappes").\n'
        "- Ne renvoie QUE le JSON, rien d'autre."
    )


def build_user_message(titles: list[str]) -> str:
    lines = [f"{i}. {t}" for i, t in enumerate(titles)]
    return "Titres :\n" + "\n".join(lines)


# ---------------------------------------------------------------------------
# Appel LLM (avec dry-run)
# ---------------------------------------------------------------------------


def _is_dry_run() -> bool:
    return os.environ.get("EVENT_LABEL_DRY_RUN") == "1"


def _dry_run_partition(titles: list[str]) -> dict:
    """Stub déterministe : 1 événement par article (aucun appel API)."""
    return {
        "events": [
            {"event_id": f"evt-{i}", "label": titles[i][:40], "article_indices": [i]}
            for i in range(len(titles))
        ],
        "noise_indices": [],
    }


async def partition_pool(
    client: EditorialLLMClient | None,
    pool: dict,
    model: str = DEFAULT_MODEL,
) -> dict | None:
    """Demande au LLM la partition par événement d'un pool. None sur échec."""
    titles = [a.get("title") or "" for a in pool["articles"]]
    if _is_dry_run():
        return _dry_run_partition(titles)
    assert client is not None, "client requis hors dry-run"
    seed_name = (pool.get("seed_entity") or {}).get("name") or pool.get(
        "pool_display", ""
    )
    result = await client.chat_json(
        system=build_system_prompt(seed_name),
        user_message=build_user_message(titles),
        model=model,
        temperature=0.0,
        max_tokens=2000,
    )
    if not isinstance(result, dict) or "events" not in result:
        return None
    return result


# ---------------------------------------------------------------------------
# Validateur + application
# ---------------------------------------------------------------------------


def resolve_assignment(partition: dict, n: int) -> tuple[list[str], dict[str, str]]:
    """Calcule l'assignation finale par index.

    Règle (tolérante) : un index assigné à **exactement un** événement →
    cet événement ; assigné à 0 ou ≥2 événements → `NOISE`. Les labels sont
    slugifiés.

    Retourne (assignment[index] = event_id, {event_id: label}).
    """
    counts: Counter = Counter()
    first_event: dict[int, str] = {}
    labels: dict[str, str] = {}

    for ev in partition.get("events") or []:
        eid = slugify(ev.get("event_id") or ev.get("label") or "event")
        labels.setdefault(eid, (ev.get("label") or eid))
        for idx in ev.get("article_indices") or []:
            if not isinstance(idx, int) or idx < 0 or idx >= n:
                continue
            counts[idx] += 1
            first_event.setdefault(idx, eid)

    assignment: list[str] = [NOISE_EVENT_ID] * n
    for idx in range(n):
        if counts[idx] == 1:
            assignment[idx] = first_event[idx]
        else:
            assignment[idx] = NOISE_EVENT_ID
    return assignment, labels


def apply_partition(
    pool: dict,
    partition: dict,
    *,
    target_field: str = "event_id",
    skip_reviewed: bool = True,
    label_source: str = "llm_pass1",
    confidence: float = 0.8,
) -> int:
    """Écrit l'assignation dans le pool. Retourne le nb d'articles écrits.

    - `target_field` : `event_id` (mode fill) ou `event_id_blind` (mode blind).
    - `skip_reviewed` : ne jamais écraser un article `label_reviewed=true`
      (toujours True en mode fill ; False en blind où l'on écrit un champ
      fantôme distinct).
    """
    articles = pool["articles"]
    n = len(articles)
    assignment, labels = resolve_assignment(partition, n)

    written = 0
    used_events: Counter = Counter()
    for i, art in enumerate(articles):
        if skip_reviewed and art.get("label_reviewed"):
            used_events[art.get("event_id") or NOISE_EVENT_ID] += 1
            continue
        eid = assignment[i]
        art[target_field] = eid
        if target_field == "event_id":
            art["label_source"] = label_source
            art["label_confidence"] = confidence
        used_events[eid] += 1
        written += 1

    # Reconstruit la liste `events` du pool (event_id → label + size) en mode fill.
    if target_field == "event_id":
        pool["events"] = [
            {
                "event_id": eid,
                "label": labels.get(eid, eid),
                "size": size,
            }
            for eid, size in sorted(used_events.items())
            if eid != NOISE_EVENT_ID
        ]
        if used_events.get(NOISE_EVENT_ID):
            pool["events"].append({
                "event_id": NOISE_EVENT_ID,
                "label": "singletons / hors-événement",
                "size": used_events[NOISE_EVENT_ID],
            })
    return written


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------


def pool_is_reviewed(pool: dict) -> bool:
    return any(a.get("label_reviewed") for a in pool["articles"])


def iter_pools_to_label(dataset: dict, mode: str):
    """Yield (pool, reviewed) selon le mode."""
    for pool in dataset["pools"]:
        reviewed = pool_is_reviewed(pool)
        if mode == "fill" and reviewed:
            continue
        if mode == "blind" and not reviewed:
            continue
        yield pool, reviewed


async def run(
    dataset_path: Path,
    mode: str,
    model: str,
    out_path: Path,
    limit: int | None,
) -> None:
    dataset = json.loads(dataset_path.read_text(encoding="utf-8"))

    client: EditorialLLMClient | None = None
    if not _is_dry_run():
        client = EditorialLLMClient()
        if not client.is_ready:
            print(
                "❌ MISTRAL_API_KEY non défini. Set EVENT_LABEL_DRY_RUN=1 "
                "pour un run sans API.",
                file=sys.stderr,
            )
            sys.exit(2)

    n_done = 0
    n_failed = 0
    try:
        for pool, reviewed in iter_pools_to_label(dataset, mode):
            if limit is not None and n_done >= limit:
                break
            partition = await partition_pool(client, pool, model=model)
            if partition is None:
                n_failed += 1
                logger.warning("event_label.failed", pool=pool.get("pool_key"))
                continue
            target_field = "event_id_blind" if reviewed else "event_id"
            written = apply_partition(
                pool,
                partition,
                target_field=target_field,
                skip_reviewed=(not reviewed),
            )
            n_done += 1
            n_events = len(partition.get("events") or [])
            print(
                f"  ✅ {pool.get('pool_key', '?')[:24]:<24} "
                f"events={n_events} écrits={written} "
                f"({'blind' if reviewed else 'fill'})"
            )
    finally:
        if client is not None:
            await client.close()

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(dataset, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"\n✅ Étiquetage terminé : {n_done} pools, {n_failed} échecs")
    print(f"   Dataset enrichi : {out_path}")
    if mode != "blind":
        print(
            "   → Revue PO : éditer les `event_id` douteux et passer "
            "`label_reviewed: true` pool par pool."
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--mode", choices=("fill", "blind", "all"), default="fill")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--limit", type=int, default=None, help="Cap N pools (utile en dev)"
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Chemin de sortie (défaut : écrase le dataset d'entrée)",
    )
    args = parser.parse_args()

    out_path = Path(args.out) if args.out else Path(args.dataset)

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
