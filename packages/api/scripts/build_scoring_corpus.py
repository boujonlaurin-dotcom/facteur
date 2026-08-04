"""Gèle un **corpus de candidats** réels pour le harnais de tuning du scoring
(cf. `docs/maintenance/maintenance-scoring-tuning-harness.md`).

Le corpus est l'entrée « articles » de `evaluate_scoring_personas.py` : les
personas fournissent le contexte utilisateur, ce fichier fournit les candidats à
classer. Les deux réunis, le harnais rejoue le **vrai** `PillarScoringEngine`
sans DB ni réseau.

Contrairement à `build_persona_dataset.py` (tables `user_*`, interdites au rôle
RO → dump MCP), ce script lit **directement** la prod : `claude_analytics_ro` a
bien le SELECT sur `contents` et `sources` (vérifié : 72 791 / 412 lignes).

### La règle qui compte : append-only

La sortie est `tests/fixtures/scoring_corpus_<date>.json` et **n'est jamais
mutée**. Un nouveau snapshot = un nouveau fichier daté. C'est le garde-fou
anti-overfit du lot : deux runs de sensibilité ne sont comparables que s'ils
portent le même `corpus_file`, et `evaluate_scoring_personas.py --compare`
**refuse** de comparer deux runs dont le corpus diffère. Réécrire un corpus
existant reviendrait à déplacer la cible sous la mesure — le script refuse donc
d'écraser un fichier existant (`--force` pour passer outre, en connaissance de
cause).

### Champs retenus

**Union exacte de ce que lisent les 5 piliers** (relevée sur
`app/services/recommendation/pillars/`), plus un identifiant stable et deux
champs de diagnostic. Ni `html_content` ni `url` (sha1 seul) : le corpus est un
jeu de test versionné dans le repo, pas une copie de la base.

Le `content_quality` est lu par `QualitePillar`, `cluster_id` par
`PertinencePillar` (bonus de couverture multi-sources) — le harnais recalcule
`cluster_source_counts` depuis le corpus lui-même, exactement comme la prod le
fait sur sa fenêtre 24 h.

Usage :
    cd packages/api
    PYTHONPATH=. python scripts/build_scoring_corpus.py --hours 24
    PYTHONPATH=. python scripts/build_scoring_corpus.py --hours 24 --sample 200

Sortie :
    packages/api/tests/fixtures/scoring_corpus_<date>.json
    (+ `.context/scoring-corpus-full-<date>.json` si `--sample` et que le
     corpus complet dépasse `MAX_FIXTURE_BYTES`)
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Any

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import text  # noqa: E402
from sqlalchemy.ext.asyncio import create_async_engine  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"
FIXTURES_DIR = Path(__file__).resolve().parents[1] / "tests" / "fixtures"

SCHEMA_VERSION = 1
DATASET_KIND = "scoring_corpus"

# Au-delà, le corpus complet part dans `.context/` et seul l'échantillon
# déterministe est versionné (cf. `--sample`).
MAX_FIXTURE_BYTES = 2 * 1024 * 1024

DESCRIPTION_MAX_CHARS = 300
ENTITIES_MAX = 5


SQL = """
SELECT
    c.id::text                AS id,
    c.title                   AS title,
    c.description             AS description,
    c.url                     AS url,
    c.theme                   AS theme,
    c.topics                  AS topics,
    c.entities                AS entities,
    c.published_at            AS published_at,
    c.content_type            AS content_type,
    c.duration_seconds        AS duration_seconds,
    c.content_quality         AS content_quality,
    c.thumbnail_url           AS thumbnail_url,
    c.cluster_id::text        AS cluster_id,
    c.language                AS language,
    s.id::text                AS source_id,
    s.name                    AS source_name,
    s.theme                   AS source_theme,
    s.is_curated              AS source_is_curated,
    s.secondary_themes        AS source_secondary_themes,
    s.tone                    AS source_tone,
    s.source_tier             AS source_tier,
    s.reliability_score       AS source_reliability_score
FROM contents c
JOIN sources s ON s.id = c.source_id
WHERE c.published_at >= :since
  AND c.published_at <= :until
  AND s.is_active
ORDER BY c.id
"""


def _load_env_file(path: Path) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key and key not in os.environ:
            os.environ[key] = value.strip().strip('"').strip("'")


def _database_url() -> str:
    """URL de lecture. `DATABASE_URL_RO` d'abord — ce script ne fait que du
    SELECT et n'a aucune raison de tenir une connexion en écriture."""
    _load_env_file(REPO_ROOT / "packages" / "api" / ".env")
    _load_env_file(REPO_ROOT / ".env")

    url = os.environ.get("DATABASE_URL_RO") or os.environ.get("DATABASE_URL")
    if not url:
        raise SystemExit("DATABASE_URL_RO (ou DATABASE_URL) est requis")
    if url.startswith("postgres://"):
        return "postgresql+psycopg://" + url.removeprefix("postgres://")
    if url.startswith("postgresql://"):
        return "postgresql+psycopg://" + url.removeprefix("postgresql://")
    return url


def _iso(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.UTC)
    return value.isoformat()


def _url_sha1(url: str | None) -> str | None:
    """L'URL n'est pas versionnée (données brutes) mais son empreinte permet de
    dédupliquer et de recouper deux snapshots sans exposer le lien."""
    if not url:
        return None
    return hashlib.sha1(url.encode("utf-8")).hexdigest()


def build_article(row: dict[str, Any]) -> dict[str, Any]:
    """Projette une ligne SQL sur le sous-ensemble lu par les piliers."""
    description = row.get("description") or ""
    entities = list(row.get("entities") or [])
    return {
        "id": row["id"],
        "title": row.get("title") or "",
        "description": description[:DESCRIPTION_MAX_CHARS],
        "url_sha1": _url_sha1(row.get("url")),
        "theme": row.get("theme"),
        "topics": list(row.get("topics") or []),
        "entities": entities[:ENTITIES_MAX],
        "published_at": _iso(row.get("published_at")),
        "content_type": row.get("content_type"),
        "duration_seconds": row.get("duration_seconds"),
        "content_quality": row.get("content_quality"),
        # Seule la présence compte pour `QualitePillar` — on ne versionne pas
        # l'URL de la vignette.
        "has_thumbnail": bool((row.get("thumbnail_url") or "").strip()),
        "cluster_id": row.get("cluster_id"),
        "language": row.get("language"),
        "source": {
            "id": row["source_id"],
            "name": row.get("source_name"),
            "theme": row.get("source_theme"),
            "is_curated": bool(row.get("source_is_curated")),
            "secondary_themes": list(row.get("source_secondary_themes") or []),
            "tone": row.get("source_tone"),
            "source_tier": row.get("source_tier"),
            "reliability_score": row.get("source_reliability_score"),
        },
    }


def sample_articles(articles: list[dict[str, Any]], size: int) -> list[dict[str, Any]]:
    """Sous-échantillon **déterministe** : les `size` premiers par `id`.

    Pas de `random`, même pas seedé : un corpus est une pièce à conviction, il
    doit se reconstruire à l'identique depuis la même fenêtre.
    """
    if size <= 0 or size >= len(articles):
        return articles
    ordered = sorted(articles, key=lambda a: a["id"])
    return ordered[:size]


def build_payload(
    articles: list[dict[str, Any]],
    *,
    since: dt.datetime,
    until: dt.datetime,
    hours: int,
    sample: int | None,
) -> dict[str, Any]:
    """En-tête miroir de `veille_curation_gold.json`.

    `generated_at` **est** le `NOW` du harnais : la fraîcheur d'un article se
    calcule contre lui, jamais contre l'horloge du run. Sans ça, le même corpus
    donnerait des scores différents d'un jour à l'autre et aucune campagne de
    sensibilité ne serait reproductible.
    """
    return {
        "schema_version": SCHEMA_VERSION,
        "dataset_kind": DATASET_KIND,
        "generated_at": until.isoformat(),
        "source_window": {
            "hours": hours,
            "since": since.isoformat(),
            "until": until.isoformat(),
        },
        "sample": sample,
        "article_count": len(articles),
        "source_count": len({a["source"]["id"] for a in articles}),
        "note": (
            "Corpus gelé, append-only : ne jamais muter ce fichier. Un nouveau "
            "snapshot = un nouveau fichier daté. `generated_at` est le NOW figé "
            "du scoring."
        ),
        "articles": articles,
    }


async def fetch_rows(since: dt.datetime, until: dt.datetime) -> list[dict[str, Any]]:
    url = _database_url()
    connect_args: dict[str, Any] = {}
    if "+psycopg" in url:
        connect_args["prepare_threshold"] = None

    engine = create_async_engine(url, pool_pre_ping=False, connect_args=connect_args)
    try:
        async with engine.connect() as conn:
            result = await conn.execute(text(SQL), {"since": since, "until": until})
            return [dict(row._mapping) for row in result.fetchall()]
    finally:
        await engine.dispose()


def _serialize(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2)


def _write(path: Path, payload: dict[str, Any]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    blob = _serialize(payload)
    path.write_text(blob, encoding="utf-8")
    return len(blob.encode("utf-8"))


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hours", type=int, default=24, help="Fenêtre (défaut 24 h)")
    parser.add_argument(
        "--sample",
        type=int,
        default=None,
        help="Taille du sous-échantillon déterministe versionné (ex. 200)",
    )
    parser.add_argument("--out", default=None, help="Chemin de sortie explicite")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Autorise l'écrasement d'un corpus existant (append-only par défaut)",
    )
    return parser.parse_args(argv)


async def _main(argv: list[str]) -> int:
    args = _parse_args(argv)

    until = dt.datetime.now(dt.UTC).replace(microsecond=0)
    since = until - dt.timedelta(hours=args.hours)

    # Garde append-only **avant** la requête : inutile de faire travailler la
    # prod pour jeter le résultat ensuite.
    today = until.date().isoformat()
    out_path = Path(args.out or FIXTURES_DIR / f"scoring_corpus_{today}.json")
    if out_path.exists() and not args.force:
        print(
            f"❌ {out_path.name} existe déjà. Le corpus est append-only : "
            "produire un nouveau fichier daté, ou --force en connaissance de cause."
        )
        return 1

    rows = await fetch_rows(since, until)
    articles = [build_article(row) for row in rows]
    if not articles:
        print("❌ 0 article sur la fenêtre — corpus non écrit.")
        return 1

    full_payload = build_payload(
        articles, since=since, until=until, hours=args.hours, sample=None
    )
    # Mesuré sur la sérialisation **effectivement écrite** (indentée) — sinon le
    # seuil se juge sur un blob qui n'existe nulle part sur disque.
    full_bytes = len(_serialize(full_payload).encode("utf-8"))

    if args.sample and full_bytes > MAX_FIXTURE_BYTES:
        # Corpus trop gros pour le repo : le complet part dans `.context/`
        # (non versionné) et l'échantillon versionné sert la CI.
        full_out = CONTEXT_DIR / f"scoring-corpus-full-{today}.json"
        _write(full_out, full_payload)
        kept = sample_articles(articles, args.sample)
        payload = build_payload(
            kept, since=since, until=until, hours=args.hours, sample=args.sample
        )
        print(f"ℹ️  Corpus complet ({full_bytes / 1e6:.1f} Mo) → {full_out}")
    elif args.sample:
        kept = sample_articles(articles, args.sample)
        payload = build_payload(
            kept, since=since, until=until, hours=args.hours, sample=args.sample
        )
    else:
        payload = full_payload

    written = _write(out_path, payload)
    print(
        f"✅ {payload['article_count']} articles / "
        f"{payload['source_count']} sources → {out_path} ({written / 1e6:.2f} Mo)"
    )
    print(f"   NOW figé = {payload['generated_at']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main(sys.argv[1:])))
