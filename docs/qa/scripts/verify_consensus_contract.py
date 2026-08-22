"""Vérification live du contrat `consensus` + `display` (Story 35.2, 6C PR 2).

Contrat vérifié de bout en bout, à travers un vrai serveur HTTP et une vraie
base, sur ``GET /contents/{id}/perspectives`` :

- plafonds servis : ≤ 3 accords, ≤ 2 désaccords, CTA = ≤ 1 accord + ≤ 1
  désaccord (même quand la ligne en base en porte davantage) ;
- cohérence d'attribution : ≤ 2 `display_domains` par constat, tous issus du
  corpus servi (alternatives + média lu), `plus_count == max(0, support-2)` ;
- états : `available` avec qualificatif ∈ {polarized, varied, convergent} ;
  sujet sans analyse → `pending` **sans** qualificatif ; sujet à 1 média →
  `unavailable` + `display.is_solo` (ni CTA ni barre ni carrousel) ;
- gates `display` dérivées du même `coverage_count` que la réponse ;
- stabilité cache : un 2ᵉ appel (cache hit) sert les mêmes blocs.

Usage (cf. `verify_consensus_contract.sh`, qui orchestre uvicorn) :

    python verify_consensus_contract.py seed     # écrit le jeu d'essai
    python verify_consensus_contract.py verify   # curl + assertions
    python verify_consensus_contract.py cleanup  # supprime le jeu d'essai
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from datetime import UTC, date, datetime, timedelta

import httpx
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "packages", "api")
)

from app.models.content import Content  # noqa: E402
from app.models.coverage_analysis import (  # noqa: E402
    CoverageAnalysis,
    CoverageAnalysisArticle,
)
from app.models.daily_digest import DailyDigest  # noqa: E402
from app.models.enums import ContentType, SourceType  # noqa: E402
from app.models.source import Source  # noqa: E402

# Namespace fixe : le seed est idempotent et le cleanup ciblé.
NS = uuid.UUID("22222222-3333-4444-5555-666666666666")
DIGEST_ID = uuid.uuid5(NS, "digest")
ANALYSIS_ID = uuid.uuid5(NS, "analysis")

NOMINAL = [
    ("qa6c-nominal-01.example", "QA 6C Nominal 01", "left"),
    ("qa6c-nominal-02.example", "QA 6C Nominal 02", "center-left"),
    ("qa6c-nominal-03.example", "QA 6C Nominal 03", "center"),
    ("qa6c-nominal-04.example", "QA 6C Nominal 04", "center-right"),
    ("qa6c-nominal-05.example", "QA 6C Nominal 05", "right"),
]
PENDING = [
    ("qa6c-pending-01.example", "QA 6C Pending 01", "left"),
    ("qa6c-pending-02.example", "QA 6C Pending 02", "center"),
    ("qa6c-pending-03.example", "QA 6C Pending 03", "right"),
]
SOLO = [("qa6c-solo-01.example", "QA 6C Solo 01", "center")]

ALL_DOMAINS = NOMINAL + PENDING + SOLO


def _content_id(domain: str) -> uuid.UUID:
    return uuid.uuid5(NS, f"content:{domain}")


def _source_id(domain: str) -> uuid.UUID:
    return uuid.uuid5(NS, f"source:{domain}")


def _session_maker():
    url = os.environ["DATABASE_URL"]
    engine = create_async_engine(url, echo=False)
    return engine, async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )


async def _cleanup(db: AsyncSession) -> None:
    await db.execute(delete(CoverageAnalysis).where(CoverageAnalysis.id == ANALYSIS_ID))
    await db.execute(delete(DailyDigest).where(DailyDigest.id == DIGEST_ID))
    await db.execute(
        delete(Content).where(
            Content.id.in_([_content_id(d) for d, _, _ in ALL_DOMAINS])
        )
    )
    await db.execute(
        delete(Source).where(Source.id.in_([_source_id(d) for d, _, _ in ALL_DOMAINS]))
    )
    await db.commit()


def _coverage_articles(domains, published) -> list[dict]:
    return [
        {
            "content_id": str(_content_id(domain)),
            "title": f"Sujet QA 6C ({name})",
            "url": f"https://{domain}/article",
            "source_name": name,
            "source_domain": domain,
            "bias_stance": bias,
            "published_at": published.isoformat(),
            "description": "Article de test du contrat consensus.",
            "reliability_score": None,
            "language": "fr",
        }
        for domain, name, bias in domains
    ]


def _subject(topic_id: str, domains, published) -> dict:
    return {
        "topic_id": topic_id,
        "label": topic_id,
        "representative_content_id": str(_content_id(domains[0][0])),
        "actu_article": {"content_id": str(_content_id(domains[0][0]))},
        "extra_actu_articles": [],
        "perspective_count": len(domains) - 1,
        "coverage_count": len(domains),
        "coverage_articles": _coverage_articles(domains, published),
        "bias_distribution": {},
        "divergence_level": "medium",
    }


# Ligne volontairement HORS contrat (4 accords, 3 désaccords, compteur gonflé) :
# le service doit replafonner et resserrer, jamais servir tel quel.
def _analysis_consensus() -> dict:
    nominal_domains = [d for d, _, _ in NOMINAL]
    return {
        "state": "available",
        "qualifier": "polarized",
        "agreements": [
            {
                "text": f"Accord numéro {i} porté par le corpus nominal.",
                "source_domains": nominal_domains[: 3 + (i % 2)],
                "support_count": 9 if i == 0 else len(nominal_domains[: 3 + (i % 2)]),
            }
            for i in range(4)
        ],
        "disagreements": [
            {
                "text": f"Désaccord numéro {i}, formulé en axe et non en verdict.",
                "source_domains": [nominal_domains[0], nominal_domains[4]],
                "support_count": 2,
            }
            for i in range(3)
        ],
        "cta": {
            "agreement": {
                "text": "Accord court pour le CTA.",
                "source_domains": nominal_domains[:4],
                "support_count": 4,
            },
            "disagreement": {
                "text": "Désaccord court : portée durable ou parenthèse.",
                "source_domains": [nominal_domains[0], nominal_domains[4]],
                "support_count": 2,
            },
        },
    }


async def seed(user_id: uuid.UUID) -> None:
    engine, maker = _session_maker()
    published = datetime.now(UTC) - timedelta(hours=3)
    async with maker() as db:
        await _cleanup(db)

        for domain, name, _bias in ALL_DOMAINS:
            db.add(
                Source(
                    id=_source_id(domain),
                    name=name,
                    url=f"https://{domain}",
                    feed_url=f"https://{domain}/rss-qa-6c",
                    type=SourceType.ARTICLE,
                    theme="politics",
                    is_curated=True,
                    is_active=True,
                )
            )
            db.add(
                Content(
                    id=_content_id(domain),
                    source_id=_source_id(domain),
                    title=f"Sujet QA 6C ({name})",
                    url=f"https://{domain}/article",
                    guid=f"qa-6c-{domain}",
                    description="Article de test du contrat consensus.",
                    published_at=published,
                    content_type=ContentType.ARTICLE,
                    theme="politics",
                    language="fr",
                    topics=["qa"],
                    entities=[json.dumps({"name": "QA", "type": "ORG"})],
                )
            )
        await db.flush()

        db.add(
            DailyDigest(
                id=DIGEST_ID,
                user_id=user_id,
                target_date=date.today(),
                format_version="editorial_v2",
                generated_at=datetime.now(UTC),
                items={
                    "subjects": [
                        _subject("qa-6c-nominal", NOMINAL, published),
                        _subject("qa-6c-pending", PENDING, published),
                        _subject("qa-6c-solo", SOLO, published),
                    ]
                },
            )
        )

        db.add(
            CoverageAnalysis(
                id=ANALYSIS_ID,
                subject_key=str(uuid.uuid5(NS, "subject-key"))[:40],
                consensus=_analysis_consensus(),
                qualifier="polarized",
                state="available",
                model_version="qa-fixture",
                corpus_domains=[d for d, _, _ in NOMINAL],
                coverage_count=len(NOMINAL),
                generated_at=datetime.now(UTC),
            )
        )
        await db.flush()
        for domain, _, _ in NOMINAL:
            db.add(
                CoverageAnalysisArticle(
                    coverage_analysis_id=ANALYSIS_ID,
                    content_id=_content_id(domain),
                )
            )
        await db.commit()
    await engine.dispose()
    print(
        f"seeded — nominal={len(NOMINAL)} pending={len(PENDING)} solo={len(SOLO)} "
        f"pour user {user_id}"
    )


async def cleanup() -> None:
    engine, maker = _session_maker()
    async with maker() as db:
        await _cleanup(db)
    await engine.dispose()
    print("cleaned up")


def _check_statement(tag: str, statement: dict, served_domains: set[str], failures):
    domains = statement.get("display_domains")
    if not isinstance(domains, list) or len(domains) > 2:
        failures.append(f"{tag}: display_domains invalide ({domains})")
        return
    for domain in domains:
        if domain not in served_domains:
            failures.append(f"{tag}: domaine hors corpus servi ({domain})")
    support = statement.get("support_count")
    plus = statement.get("plus_count")
    if not isinstance(support, int) or support < len(domains):
        failures.append(f"{tag}: support_count={support} < logos affichés")
    if plus != max(0, (support or 0) - 2):
        failures.append(f"{tag}: plus_count={plus} incohérent avec support={support}")


def _check_body(tag: str, body: dict, failures) -> None:
    consensus = body.get("consensus")
    display = body.get("display")
    if not isinstance(consensus, dict) or not isinstance(display, dict):
        failures.append(f"{tag}: blocs consensus/display absents")
        return

    coverage = int(body.get("coverage_count") or 0)
    served_domains = {
        (p.get("source_domain") or "").removeprefix("www.").lower()
        for p in body.get("perspectives") or []
    }
    served_domains.add(tag.split("|", 1)[1])  # le média lu fait partie du corpus

    # Gates dérivées du même coverage_count que la réponse.
    expected = {
        "is_solo": coverage <= 1,
        "has_cta": coverage >= 2,
        "has_cards": coverage >= 2,
        "has_ai_card": coverage >= 3,
        "has_bar": coverage >= 3,
    }
    if display != expected:
        failures.append(f"{tag}: display={display}, attendu {expected}")

    state = consensus.get("state")
    if state not in ("available", "pending", "unavailable"):
        failures.append(f"{tag}: state inconnu ({state})")
    if state != "available" and consensus.get("qualifier") is not None:
        failures.append(f"{tag}: qualificatif présent hors available")
    if state == "available" and consensus.get("qualifier") not in (
        "polarized",
        "varied",
        "convergent",
    ):
        failures.append(f"{tag}: qualificatif invalide ({consensus.get('qualifier')})")

    agreements = consensus.get("agreements") or []
    disagreements = consensus.get("disagreements") or []
    if len(agreements) > 3:
        failures.append(f"{tag}: {len(agreements)} accords servis (> 3)")
    if len(disagreements) > 2:
        failures.append(f"{tag}: {len(disagreements)} désaccords servis (> 2)")
    if state != "available" and (agreements or disagreements):
        failures.append(f"{tag}: constats servis hors state=available")

    for i, statement in enumerate(agreements):
        _check_statement(f"{tag}:accord{i}", statement, served_domains, failures)
    for i, statement in enumerate(disagreements):
        _check_statement(f"{tag}:désaccord{i}", statement, served_domains, failures)

    cta = consensus.get("cta")
    if not isinstance(cta, dict) or set(cta) != {"agreement", "disagreement"}:
        failures.append(f"{tag}: forme du CTA invalide ({cta})")
    else:
        for side, statement in cta.items():
            if statement is not None:
                _check_statement(f"{tag}:cta-{side}", statement, served_domains, failures)


async def verify(base_url: str, token: str) -> int:
    failures: list[str] = []
    cases = [
        ("nominal", NOMINAL[1][0], "available"),
        ("pending", PENDING[0][0], "pending"),
        ("solo", SOLO[0][0], "unavailable"),
    ]
    async with httpx.AsyncClient(timeout=60.0) as client:
        for label, domain, expected_state in cases:
            cid = _content_id(domain)
            bodies = []
            # 2 appels : le 2ᵉ passe par `_perspectives_cache` et doit servir
            # les mêmes blocs (résolus par requête, jamais stockés).
            for _ in range(2):
                r = await client.get(
                    f"{base_url}/contents/{cid}/perspectives",
                    headers={"Authorization": f"Bearer {token}"},
                )
                if r.status_code != 200:
                    failures.append(f"{label}: HTTP {r.status_code} {r.text[:200]}")
                    break
                bodies.append(r.json())
            if len(bodies) != 2:
                continue

            for pass_index, body in enumerate(bodies):
                tag = f"{label}#{pass_index}|{domain}"
                _check_body(tag, body, failures)
                state = (body.get("consensus") or {}).get("state")
                if state != expected_state:
                    failures.append(
                        f"{tag}: state={state}, attendu {expected_state}"
                    )

            consensus = bodies[1].get("consensus") or {}
            print(
                f"  {label:8s} coverage={bodies[1].get('coverage_count')} "
                f"state={consensus.get('state')} "
                f"qualifier={consensus.get('qualifier')} "
                f"accords={len(consensus.get('agreements') or [])} "
                f"désaccords={len(consensus.get('disagreements') or [])}"
            )

    if failures:
        print("\nECHECS :")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("\nOK — contrat consensus/display vérifié (nominal, pending, solo, x2 cache)")
    return 0


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "seed":
        asyncio.run(seed(uuid.UUID(os.environ["QA_USER_ID"])))
        return 0
    if mode == "cleanup":
        asyncio.run(cleanup())
        return 0
    return asyncio.run(
        verify(
            os.environ.get("API_BASE_URL", "http://127.0.0.1:8080/api"),
            os.environ["QA_ACCESS_TOKEN"],
        )
    )


if __name__ == "__main__":
    raise SystemExit(main())
