#!/usr/bin/env python3
"""Dry-run qualité de l'analyse des angles 6C — READ-ONLY en base (Story 35.1).

Rejoue `PerspectiveService.analyze_consensus` sur les sujets des digests
récents, puis applique le post-traitement déterministe (`normalize_consensus`)
et imprime ce que le Reader afficherait : constats, attributions, « +N »,
qualificatif, variantes du CTA.

C'est le **vrai gate** de ce lot : le contrat est facile à tester (cf.
tests/editorial/test_consensus_schemas.py), la **copy** ne l'est pas. Ce que le
PO relit ici : les accords sont-ils à l'indicatif et sans « selon les médias » ;
les désaccords sont-ils formulés **en axe** (« Sa portée : X ou Y ») et jamais
en verdict ; les variantes du CTA tiennent-elles debout seules.

⚠️ Le script **appelle Mistral** (1 appel `mistral-large` par sujet, ~20 sujets
sur un jour). Il n'écrit rien en base : ni `coverage_analyses`, ni le digest.

Usage:
    cd packages/api && source venv/bin/activate
    PYTHONPATH=. python scripts/dryrun_consensus.py --tag 6c-pr1
    PYTHONPATH=. python scripts/dryrun_consensus.py --days 2 --limit 5

Sorties (même convention que dryrun_coverage_fold.py) :
    ../../.context/dryrun_consensus_<tag>.json  (machine)
    ../../.context/dryrun_consensus_<tag>.md    (relecture PO)
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

# packages/api sur sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

parser = argparse.ArgumentParser(
    description="Dry-run qualité de l'analyse des angles 6C (read-only en base)"
)
parser.add_argument("--tag", default="6c-pr1", help="Nom du run (défaut: 6c-pr1)")
parser.add_argument(
    "--days", type=int, default=1, help="Fenêtre de digests en jours (défaut: 1)"
)
parser.add_argument(
    "--limit", type=int, default=20, help="Nombre max de sujets (défaut: 20)"
)
parser.add_argument(
    "--min-perspectives",
    type=int,
    default=2,
    help="Seuil d'alternatives sous lequel on saute le sujet (défaut: 2, "
    "aligné sur divergence_llm_min_perspectives)",
)
args = parser.parse_args()

from sqlalchemy import desc, select  # noqa: E402

from app.database import async_session_maker, engine  # noqa: E402
from app.models.daily_digest import DailyDigest  # noqa: E402
from app.services.editorial.consensus import (  # noqa: E402
    build_corpus_index,
    normalize_consensus,
)
from app.services.perspective_service import (  # noqa: E402
    PerspectiveService,
    normalize_domain,
)


async def _load_subjects(session, *, days: int, limit: int) -> list[dict]:
    """Sujets distincts des digests récents, dédupliqués par pivot.

    La phase globale est mutualisée entre tous les users : les ~3 600 lignes-sujet
    d'une journée ne portent qu'une vingtaine de sujets réels. On déduplique sur
    `representative_content_id`, qui est justement l'identité de sujet que le
    pipeline propage.
    """
    since = datetime.now(UTC) - timedelta(days=days)
    stmt = (
        select(DailyDigest.items)
        .where(
            DailyDigest.generated_at >= since,
            DailyDigest.format_version.startswith("editorial_", autoescape=True),
        )
        .order_by(desc(DailyDigest.generated_at))
        .limit(400)
    )
    rows = (await session.execute(stmt)).scalars().all()

    subjects: list[dict] = []
    seen: set[str] = set()
    for items in rows:
        if not isinstance(items, dict):
            continue
        for subject in items.get("subjects", []) or []:
            key = str(subject.get("representative_content_id") or subject.get("label"))
            if not key or key in seen:
                continue
            coverage = subject.get("coverage_articles") or []
            if len(coverage) < args.min_perspectives + 1:
                continue
            seen.add(key)
            subjects.append(subject)
            if len(subjects) >= limit:
                return subjects
    return subjects


def _split_pivot(subject: dict) -> tuple[dict | None, list[dict]]:
    """Sépare le pivot des alternatives dans le snapshot de couverture."""
    coverage = [
        a for a in subject.get("coverage_articles") or [] if isinstance(a, dict)
    ]
    rep_id = str(subject.get("representative_content_id") or "")
    pivot = next(
        (a for a in coverage if str(a.get("content_id") or "") == rep_id),
        coverage[0] if coverage else None,
    )
    if pivot is None:
        return None, []
    pivot_domain = normalize_domain(pivot.get("source_domain"))
    alternatives = [
        a for a in coverage if normalize_domain(a.get("source_domain")) != pivot_domain
    ]
    return pivot, alternatives


def _render_statement(statement: dict) -> str:
    domains = statement["source_domains"]
    shown = ", ".join(domains[:2])
    extra = statement["support_count"] - 2
    plus = f" +{extra}" if extra > 0 else ""
    return f"{statement['text']}\n      → {shown}{plus} (appui: {statement['support_count']})"


async def main() -> int:
    service = PerspectiveService(db=None, session_maker=async_session_maker)
    results: list[dict] = []

    async with async_session_maker() as session:
        subjects = await _load_subjects(session, days=args.days, limit=args.limit)

    if not subjects:
        print("Aucun sujet exploitable sur la fenêtre demandée.")
        return 1

    print(f"{len(subjects)} sujets à rejouer (1 appel mistral-large chacun)...\n")

    for index, subject in enumerate(subjects, start=1):
        pivot, alternatives = _split_pivot(subject)
        if pivot is None or len(alternatives) < args.min_perspectives:
            continue

        # Même règle d'attribution que la prod : si elle change côté pipeline,
        # le gate PO relit ce que le Reader servira, pas une variante.
        corpus_domains, bias_by_domain = build_corpus_index([pivot, *alternatives])

        raw = await service.analyze_consensus(
            article_title=pivot.get("title") or "",
            source_name=pivot.get("source_name") or "",
            source_bias=pivot.get("bias_stance") or "unknown",
            source_domain=pivot.get("source_domain") or "",
            perspectives=alternatives,
            article_description=pivot.get("description"),
        )
        payload = normalize_consensus(raw, corpus_domains, bias_by_domain)

        results.append(
            {
                "label": subject.get("label"),
                "coverage_count": subject.get("coverage_count"),
                "corpus_domains": corpus_domains,
                "raw": raw,
                "consensus": payload.model_dump(mode="json"),
            }
        )
        print(f"[{index}/{len(subjects)}] {subject.get('label')} — {payload.state}")

    await engine.dispose()

    CONTEXT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = CONTEXT_DIR / f"dryrun_consensus_{args.tag}.json"
    json_path.write_text(json.dumps(results, ensure_ascii=False, indent=2))

    lines = [
        f"# Dry-run analyse des angles — `{args.tag}`",
        "",
        f"{len(results)} sujets, fenêtre {args.days} j. Relecture PO : ton des "
        "accords (indicatif, pas de « selon les médias »), désaccords **en axe** "
        "et non en verdict, variantes CTA autoportantes.",
        "",
    ]
    for entry in results:
        consensus = entry["consensus"]
        qualifier = consensus["qualifier"] or "—"
        lines += [
            f"## {entry['label']}",
            "",
            f"`{consensus['state']}` · qualificatif **{qualifier}** · "
            f"couverture {entry['coverage_count']} · corpus "
            f"{len(entry['corpus_domains'])} domaines",
            "",
            "**Accords**",
        ]
        lines += [f"  - {_render_statement(s)}" for s in consensus["agreements"]] or [
            "  - (aucun)"
        ]
        lines += ["", "**Désaccords**"]
        lines += [
            f"  - {_render_statement(s)}" for s in consensus["disagreements"]
        ] or ["  - (aucun)"]
        cta = consensus["cta"]
        lines += [
            "",
            "**CTA**",
            f"  - accord : {cta['agreement']['text'] if cta['agreement'] else '(aucun)'}",
            f"  - désaccord : "
            f"{cta['disagreement']['text'] if cta['disagreement'] else '(aucun)'}",
            "",
        ]
    md_path = CONTEXT_DIR / f"dryrun_consensus_{args.tag}.md"
    md_path.write_text("\n".join(lines))

    print(f"\nÉcrit : {json_path}\n        {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
