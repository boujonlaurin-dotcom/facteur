#!/usr/bin/env python3
"""Construction du prompt de génération des évaluations de sources (Composant 1).

Formalise la génération (avant : rubrique inline dans le prompt des sous-agents).
Lit **`sources/source_eval_rubric.md`** (source de vérité, verbatim) +
`.context/source_eval_targets.json`, et émet **un prompt par lot** (~10 sources)
embarquant :
  - la rubrique complète (les ajustements PO s'y propagent automatiquement) ;
  - le **contexte** de chaque source (name/url/feed_url/type/theme/derniers titres
    + éval actuelle) ;
  - la **spec JSON stricte** de sortie (scores + 4 justifs + `sources_consulted` ;
    **PAS de `reliability_score`**, dérivé côté schéma) ;
  - la consigne de **recherche web** (3-4 requêtes mainstream, 1-2 niche).

Les sous-agents du run complet liront ce prompt construit (plus de rubrique inline).

Usage :
    cd packages/api
    python3 scripts/build_source_eval_prompt.py                 # tous les lots -> stdout
    python3 scripts/build_source_eval_prompt.py --batch 0       # un seul lot
    python3 scripts/build_source_eval_prompt.py --out-dir .context/source_eval_prompts
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RUBRIC = _ROOT / "sources" / "source_eval_rubric.md"
DEFAULT_TARGETS = _ROOT / ".context" / "source_eval_targets.json"
DEFAULT_BATCH_SIZE = 10

# Champs JSON demandés à l'agent (DANS CET ORDRE). `reliability_score` est ABSENT
# volontairement : il est dérivé des scores (cf. source_eval_schema.derive_reliability).
REQUIRED_FIELDS: list[str] = [
    "source_id",
    "name",
    "description",
    "bias_stance",
    "score_independence",
    "score_rigor",
    "score_ux",
    "confidence",
    "bias_rationale",
    "independence_rationale",
    "rigor_rationale",
    "ux_rationale",
    "sources_consulted",
]


def load_rubric(path: Path = DEFAULT_RUBRIC) -> str:
    return path.read_text()


def load_targets(path: Path = DEFAULT_TARGETS) -> list[dict]:
    return json.loads(path.read_text()).get("targets", [])


def batched(items: list[dict], size: int) -> list[list[dict]]:
    if size < 1:
        raise ValueError("batch-size doit être >= 1")
    return [items[i : i + size] for i in range(0, len(items), size)]


def render_source_context(t: dict) -> str:
    """Bloc de contexte lisible pour une source cible (factuel, pas de jugement)."""
    cur = t.get("current") or {}
    titles = t.get("recent_titles") or []
    titles_block = (
        "\n".join(f"      - {x}" for x in titles) if titles else "      (aucun)"
    )
    return (
        f"- source_id: {t.get('source_id')}\n"
        f"  name (stocké, peut être faux): {t.get('name')!r}\n"
        f"  url: {t.get('url')}\n"
        f"  feed_url: {t.get('feed_url')}\n"
        f"  type: {t.get('type')}  |  theme: {t.get('theme')}  |  "
        f"n_content: {t.get('n_content')}\n"
        f"  éval actuelle: bias={cur.get('bias_stance')} "
        f"reliability={cur.get('reliability_score')} "
        f"indep={cur.get('score_independence')} rigor={cur.get('score_rigor')} "
        f"ux={cur.get('score_ux')}\n"
        f"  derniers titres:\n{titles_block}"
    )


def _spec_block() -> str:
    fields = "\n".join(f'    "{f}": ...' for f in REQUIRED_FIELDS)
    return (
        "Pour CHAQUE source, renvoie un objet JSON avec EXACTEMENT ces champs "
        "(et seulement ceux-là) :\n"
        "```json\n{\n"
        f"{fields}\n"
        "}\n```\n"
        "Contraintes de sortie :\n"
        "  - NE renvoie PAS `reliability_score` : il est dérivé des scores.\n"
        "  - `bias_stance` ∈ {left, center-left, center, center-right, right, "
        "alternative, specialized, unknown}.\n"
        "  - `score_independence`/`score_rigor`/`score_ux` ∈ [0.0, 1.0] ou null si "
        "indéterminable.\n"
        "  - `confidence` ∈ [0.0, 1.0]. Doute réel -> bias_stance='unknown', "
        "scores null, confidence < 0.5.\n"
        "  - `description` : 2-3 phrases FR, **sans tiret cadratin** (—).\n"
        "  - 4 justifs (`*_rationale`) : 1 phrase courte chacune, le fait qui motive "
        "la note.\n"
        "  - `sources_consulted` : liste des URLs web réellement ouvertes.\n"
        "  - Ne génère JAMAIS `recommended_by` / `recommendation_reason`."
    )


def build_prompt(rubric: str, batch: list[dict], *, batch_index: int = 0) -> str:
    """Prompt complet pour un lot (rubrique verbatim + contextes + spec JSON)."""
    contexts = "\n\n".join(render_source_context(t) for t in batch)
    ids = ", ".join(t.get("source_id", "") for t in batch)
    return (
        f"# Mission — évaluation éditoriale de sources (lot {batch_index}, "
        f"{len(batch)} sources)\n\n"
        "Tu es un sous-agent chargé d'évaluer des sources médias françaises pour "
        "Facteur. Applique **strictement la rubrique ci-dessous** (source de vérité, "
        "verrouillée par le PO). Utilise la **recherche web** : 3-4 requêtes pour les "
        "médias mainstream (actionnariat, indépendance rédactionnelle, "
        "sanctions/réputation, ligne), 1-2 pour le niche. Le `name`/`theme` stockés "
        "peuvent être faux : identifie la **vraie** source via l'URL.\n\n"
        "## Rubrique (verbatim)\n\n"
        f"{rubric}\n\n"
        "## Sources à évaluer dans ce lot\n\n"
        f"source_ids: {ids}\n\n"
        f"{contexts}\n\n"
        "## Format de sortie\n\n"
        f"{_spec_block()}\n\n"
        "Renvoie un tableau JSON `[...]` d'un objet par source, dans l'ordre."
    )


def build_all(rubric_path: Path, targets_path: Path, batch_size: int) -> list[str]:
    rubric = load_rubric(rubric_path)
    targets = load_targets(targets_path)
    return [
        build_prompt(rubric, batch, batch_index=i)
        for i, batch in enumerate(batched(targets, batch_size))
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rubric", type=Path, default=DEFAULT_RUBRIC)
    parser.add_argument("--targets", type=Path, default=DEFAULT_TARGETS)
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    parser.add_argument(
        "--batch", type=int, default=None, help="n'imprime qu'un seul lot (index)"
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="écrit un fichier prompt_<i>.md par lot au lieu de stdout",
    )
    args = parser.parse_args()

    prompts = build_all(args.rubric, args.targets, args.batch_size)
    if not prompts:
        print("(aucune cible dans le fichier targets — rien à construire)")
        sys.exit(0)

    if args.out_dir is not None:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for i, p in enumerate(prompts):
            (args.out_dir / f"prompt_{i:02d}.md").write_text(p)
        print(f"Écrit {len(prompts)} prompt(s) dans {args.out_dir}")
        return

    if args.batch is not None:
        print(prompts[args.batch])
        return

    print((f"\n\n{'=' * 78}\n").join(prompts))


if __name__ == "__main__":
    main()
