"""Vérification live de l'invariant `coverage_count`.

Bug : « couverture médiatique gonflée par le compteur de ranking »
(`docs/bugs/bug-couverture-medias-disponibles.md`).

Invariant vérifié de bout en bout, à travers un vrai serveur HTTP et une vraie
base : pour **chaque** article d'un même sujet,
``GET /contents/{id}/perspectives`` renvoie exactement ``coverage_count - 1``
autres domaines, et jamais le domaine de l'article ouvert.

Usage (cf. `verify_coverage_count_invariant.sh`, qui orchestre uvicorn) :

    python verify_coverage_count_invariant.py seed     # écrit le jeu d'essai
    python verify_coverage_count_invariant.py verify   # curl + assertions
    python verify_coverage_count_invariant.py cleanup  # supprime le jeu d'essai

Le jeu d'essai reproduit le cas du bug : 14 domaines sur le même sujet, un seul
au biais connu. L'ancien code affichait « 14 sources » pour une seule
alternative consultable.
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

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "packages", "api"))

from app.models.content import Content  # noqa: E402
from app.models.daily_digest import DailyDigest  # noqa: E402
from app.models.enums import ContentType, SourceType  # noqa: E402
from app.models.source import Source  # noqa: E402

# Namespace fixe : le seed est idempotent et le cleanup ciblé.
NS = uuid.UUID("11111111-2222-3333-4444-555555555555")
DIGEST_ID = uuid.uuid5(NS, "digest")
TOPIC_ID = "qa-coverage-invariant"

# 14 domaines, un seul au biais connu (lemonde.fr est dans DOMAIN_BIAS_MAP).
DOMAINS = [
    ("lemonde.fr", "Le Monde"),
    ("qa-media-02.example", "QA Média 02"),
    ("qa-media-03.example", "QA Média 03"),
    ("qa-media-04.example", "QA Média 04"),
    ("qa-media-05.example", "QA Média 05"),
    ("qa-media-06.example", "QA Média 06"),
    ("qa-media-07.example", "QA Média 07"),
    ("qa-media-08.example", "QA Média 08"),
    ("qa-media-09.example", "QA Média 09"),
    ("qa-media-10.example", "QA Média 10"),
    ("qa-media-11.example", "QA Média 11"),
    ("qa-media-12.example", "QA Média 12"),
    ("qa-media-13.example", "QA Média 13"),
    ("qa-media-14.example", "QA Média 14"),
]

TITLE = "Conférence sur le climat : accord trouvé après deux semaines"


def _content_id(domain: str) -> uuid.UUID:
    return uuid.uuid5(NS, f"content:{domain}")


def _source_id(domain: str) -> uuid.UUID:
    return uuid.uuid5(NS, f"source:{domain}")


def _session_maker():
    url = os.environ["DATABASE_URL"]
    engine = create_async_engine(url, echo=False)
    return engine, async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def _cleanup(db: AsyncSession) -> None:
    await db.execute(delete(DailyDigest).where(DailyDigest.id == DIGEST_ID))
    await db.execute(
        delete(Content).where(Content.id.in_([_content_id(d) for d, _ in DOMAINS]))
    )
    await db.execute(
        delete(Source).where(Source.id.in_([_source_id(d) for d, _ in DOMAINS]))
    )
    await db.commit()


async def seed(user_id: uuid.UUID) -> None:
    engine, maker = _session_maker()
    published = datetime.now(UTC) - timedelta(hours=3)
    async with maker() as db:
        await _cleanup(db)

        for rank, (domain, name) in enumerate(DOMAINS, start=1):
            db.add(
                Source(
                    id=_source_id(domain),
                    name=name,
                    url=f"https://{domain}",
                    feed_url=f"https://{domain}/rss-qa-coverage",
                    type=SourceType.ARTICLE,
                    theme="politique",
                    is_curated=True,
                    is_active=True,
                )
            )
            db.add(
                Content(
                    id=_content_id(domain),
                    source_id=_source_id(domain),
                    title=f"{TITLE} ({name})",
                    url=f"https://{domain}/climat/accord-{rank}",
                    guid=f"qa-coverage-{domain}",
                    description="Les délégations ont annoncé un accord sur le climat.",
                    published_at=published,
                    content_type=ContentType.ARTICLE,
                    theme="politique",
                    language="fr",
                    topics=["climat"],
                    # `contents.entities` est un ARRAY(Text) de JSON sérialisé
                    # (cf. `_parse_entity_names`), pas du JSONB.
                    entities=[
                        json.dumps({"name": "Antonio Guterres", "type": "PERSON"}),
                        json.dumps({"name": "ONU", "type": "ORG"}),
                    ],
                )
            )
        await db.flush()

        coverage_articles = [
            {
                "content_id": str(_content_id(domain)),
                "title": f"{TITLE} ({name})",
                "url": f"https://{domain}/climat/accord-{rank}",
                "source_name": name,
                "source_domain": domain,
                "bias_stance": "center_left" if domain == "lemonde.fr" else "unknown",
                "published_at": published.isoformat(),
                "description": "Les délégations ont annoncé un accord sur le climat.",
                "reliability_score": None,
                "language": "fr",
            }
            for rank, (domain, name) in enumerate(DOMAINS, start=1)
        ]

        db.add(
            DailyDigest(
                id=DIGEST_ID,
                user_id=user_id,
                target_date=date.today(),
                format_version="editorial_v2",
                generated_at=datetime.now(UTC),
                items={
                    "subjects": [
                        {
                            "topic_id": TOPIC_ID,
                            "label": "Climat",
                            "representative_content_id": str(
                                _content_id(DOMAINS[0][0])
                            ),
                            "actu_article": {
                                "content_id": str(_content_id(DOMAINS[0][0]))
                            },
                            "extra_actu_articles": [],
                            "perspective_count": 1,
                            "coverage_count": len(DOMAINS),
                            "coverage_articles": coverage_articles,
                            "bias_distribution": {"center_left": 1},
                            "divergence_level": "low",
                        }
                    ]
                },
            )
        )
        await db.commit()
    await engine.dispose()
    print(f"seeded {len(DOMAINS)} domains for user {user_id}")
    for domain, _ in DOMAINS:
        print(f"{_content_id(domain)}\t{domain}")


async def cleanup() -> None:
    engine, maker = _session_maker()
    async with maker() as db:
        await _cleanup(db)
    await engine.dispose()
    print("cleaned up")


async def verify(base_url: str, token: str) -> int:
    failures: list[str] = []
    async with httpx.AsyncClient(timeout=60.0) as client:
        for domain, _ in DOMAINS:
            cid = _content_id(domain)
            r = await client.get(
                f"{base_url}/contents/{cid}/perspectives",
                headers={"Authorization": f"Bearer {token}"},
            )
            if r.status_code != 200:
                failures.append(f"{domain}: HTTP {r.status_code} {r.text[:200]}")
                continue
            body = r.json()
            coverage = body.get("coverage_count")
            alternatives = body.get("perspectives") or []
            returned_domains = {
                (p.get("source_domain") or "").removeprefix("www.").lower()
                for p in alternatives
            }

            if coverage != len(DOMAINS):
                failures.append(
                    f"{domain}: coverage_count={coverage}, attendu {len(DOMAINS)}"
                )
            if coverage != len(alternatives) + 1:
                failures.append(
                    f"{domain}: invariant cassé — coverage_count={coverage}, "
                    f"alternatives={len(alternatives)}"
                )
            if domain in returned_domains:
                failures.append(f"{domain}: le domaine lu est dans ses propres alternatives")
            if len(returned_domains) != len(alternatives):
                failures.append(f"{domain}: doublon de domaine dans les alternatives")

            print(
                f"  {domain:24s} coverage_count={coverage:3d} "
                f"alternatives={len(alternatives):3d} "
                f"self_excluded={'oui' if domain not in returned_domains else 'NON'}"
            )

    if failures:
        print("\nECHECS :")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"\nOK — invariant coverage_count == alternatives + 1 vérifié sur {len(DOMAINS)} articles")
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
