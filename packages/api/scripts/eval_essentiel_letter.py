"""Harnais d'éval du prompt `essentiel_letter` (Story 9.6).

Rejoue les cas de `docs/qa/essentiel_letter_cases.jsonl` contre le vrai
Mistral et mesure la discipline des marqueurs / du ton :

    cd packages/api && python scripts/eval_essentiel_letter.py --runs 3

Sortie : taux de pass 1er coup / après retry, violations par type, et les
lettres rendues lisibles pour relecture humaine du ton (gate PO avant merge).
Nécessite MISTRAL_API_KEY dans l'environnement (.env).
"""

import argparse
import asyncio
import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.schemas.essentiel import EssentielArticle  # noqa: E402
from app.schemas.essentiel_letter import LetterSegmentType  # noqa: E402
from app.services.editorial.llm_client import EditorialLLMClient  # noqa: E402
from app.services.essentiel_letter_service import (  # noqa: E402
    build_letter_plan,
    validate_letter_output,
)

CASES_PATH = (
    Path(__file__).parent.parent.parent.parent
    / "docs"
    / "qa"
    / "essentiel_letter_cases.jsonl"
)


def load_cases() -> list[dict]:
    cases = []
    for line in CASES_PATH.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            cases.append(json.loads(line))
    return cases


async def run_case(case: dict, llm: EditorialLLMClient, stats: Counter) -> None:
    from app.services.editorial.config import load_editorial_config
    from app.services.essentiel_letter_service import (
        _blocks_to_letter,
        _build_user_message,
    )

    articles = [EssentielArticle.model_validate(a) for a in case["articles"]]
    is_serene = bool(case.get("is_serene"))
    plan = build_letter_plan(articles, case.get("followed_themes") or [])

    prompt_cfg = load_editorial_config().essentiel_letter_prompt
    from app.services.essentiel_letter_service import _SEREIN_TONE_NOTE

    system = prompt_cfg.system.format(tone_note=_SEREIN_TONE_NOTE if is_serene else "")

    corrections = None
    for attempt in (1, 2):
        raw = await llm.chat_json(
            system=system,
            user_message=_build_user_message(plan, articles, corrections),
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
            call_site="essentiel_letter_eval",
        )
        if not raw or not isinstance(raw, dict):
            stats["llm_error"] += 1
            print(f"  ✗ {case['name']} : erreur LLM (tentative {attempt})")
            return
        blocks, violations = validate_letter_output(raw, plan, articles)
        if blocks is not None:
            stats["pass_first" if attempt == 1 else "pass_retry"] += 1
            letter = _blocks_to_letter(blocks, plan, articles, prompt_cfg.model)
            articles_by_id = {a.content_id: a for a in articles}

            def _render(segments):
                parts = []
                for seg in segments:
                    if seg.type == LetterSegmentType.TEXT:
                        parts.append(seg.text or "")
                    else:
                        article = articles_by_id.get(seg.content_id)
                        parts.append(f"〔{article.source.name if article else '?'} ↗〕")
                return "".join(parts).strip()

            marker = "✓" if attempt == 1 else "✓(retry)"
            print(f"  {marker} {case['name']}")
            print(f"     CHAPO : {_render(letter.chapo)}")
            for rubrique in letter.rubriques:
                print(f"     [{rubrique.theme} ↘] {_render(rubrique.segments)}")
            if letter.footer_themes:
                print(f"     Aussi dans ta tournée : {letter.footer_themes}")
            return
        for violation in violations:
            stats[f"violation:{violation.split(':')[0].strip()}"] += 1
        if attempt == 1:
            corrections = violations
    stats["fail"] += 1
    print(f"  ✗ {case['name']} : rejeté après retry — {violations}")


async def main(runs: int, only: str | None) -> None:
    cases = load_cases()
    if only:
        cases = [c for c in cases if only in c["name"]]
    llm = EditorialLLMClient()
    if not llm.is_ready:
        print("MISTRAL_API_KEY absent : impossible de lancer l'éval.")
        sys.exit(1)

    stats: Counter = Counter()
    try:
        for run in range(1, runs + 1):
            print(f"\n=== Run {run}/{runs} ===")
            for case in cases:
                await run_case(case, llm, stats)
    finally:
        await llm.close()

    total = runs * len(cases)
    passed = stats["pass_first"] + stats["pass_retry"]
    print("\n=== Bilan ===")
    print(f"Cas exécutés        : {total}")
    print(
        f"Pass 1er coup       : {stats['pass_first']} ({stats['pass_first'] / total:.0%})"
    )
    print(f"Pass après retry    : {passed} ({passed / total:.0%})  ← cible ≥95%")
    print(f"Échecs              : {stats['fail']} | erreurs LLM : {stats['llm_error']}")
    violations = {k: v for k, v in stats.items() if k.startswith("violation:")}
    if violations:
        print("Violations par type :")
        for key, count in sorted(violations.items(), key=lambda kv: -kv[1]):
            print(f"  {key.removeprefix('violation:')} : {count}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--only", type=str, default=None, help="filtre par nom de cas")
    args = parser.parse_args()
    asyncio.run(main(args.runs, args.only))
