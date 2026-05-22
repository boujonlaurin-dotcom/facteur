"""Cartographie de la pipeline de highlighting des titres (Story 7.4).

Sélectionne les N "pseudo-clusters" récents les plus actifs (groupes
d'articles partageant une entité PERSON/ORG/EVENT, fenêtre 48h par défaut)
et exporte la sortie réelle de `TitleAnnotationService` (strong_tokens +
highlight_spans + shared_tokens + reference_pivot) dans un rapport Markdown
lisible. Le rapport contient une section "Cible attendue" vide à chaque
cluster pour annotation manuelle avec le PO.

Pourquoi entity-based et pas `Content.cluster_id` ?
    En prod, `cluster_id` n'est PAS persisté (vérifié 2026-05-19 : 0/41308
    rows). Le clustering tourne en mémoire via `find_hot_cluster` qui
    indexe `Content.entities` (PERSON/ORG/EVENT). On reproduit la même
    logique ici.

Deux modes d'entrée :
    --input <path.json> : lit un dump JSON déjà extrait de la prod (forme
        documentée plus bas). Permet d'exécuter le script sans accès admin
        à la DB.
    (par défaut)        : se connecte via `settings.database_url` et
        requête `contents` + `sources`. Nécessite un rôle ayant SELECT sur
        ces tables (le rôle `claude_analytics_ro` ne suffit pas en prod —
        utiliser un `DATABASE_URL` admin).

Forme du dump JSON :
    {
      "generated_at": "2026-05-19T15:00:00Z",
      "articles": [
        {
          "id": "uuid",
          "title": "...",
          "url": "...",
          "published_at": "2026-05-19T08:00:00Z",
          "source_name": "Le Monde",
          "bias_stance": "center-left",
          "entities": ["{\"name\": \"Macron\", \"type\": \"PERSON\"}", ...]
        }, ...
      ]
    }

Usage :
    cd packages/api && source venv/bin/activate
    python scripts/inspect_title_annotations.py --limit 5 --hours 48
    # ou avec un dump
    python scripts/inspect_title_annotations.py --input /tmp/dump.json --limit 5

Sortie :
    .context/highlight-cartography-YYYY-MM-DD.md (à la racine du repo)
"""

import argparse
import asyncio
import json
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

sys.path.append(os.path.join(os.path.dirname(__file__), ".."))

from app.config import get_settings  # noqa: E402
from app.models.content import Content  # noqa: E402
from app.models.source import Source  # noqa: E402
from app.services.title_annotation_service import (  # noqa: E402
    TitleAnnotationService,
    get_title_annotation_service,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CONTEXT_DIR = REPO_ROOT / ".context"

# Entités jugées discriminantes pour pseudo-clusterer (cf. perspective_service)
DISCRIMINANT_TYPES = frozenset({"PERSON", "ORG", "EVENT"})


@dataclass
class Article:
    id: str
    title: str
    url: str
    published_at: datetime
    source_name: str
    bias_stance: str
    entities: list[str]

    def entity_keys(self) -> list[tuple[str, str]]:
        """Retourne (key=lower, display_name) pour chaque entité PERSON/ORG/EVENT."""
        out: list[tuple[str, str]] = []
        for raw in self.entities or []:
            try:
                obj = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if obj.get("type") not in DISCRIMINANT_TYPES:
                continue
            name = (obj.get("name") or "").strip()
            if name:
                out.append((name.lower(), name))
        return out


async def fetch_articles_from_db(hours: int) -> list[Article]:
    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    since = datetime.now(timezone.utc) - timedelta(hours=hours)
    try:
        async with async_session() as db:
            stmt = (
                select(
                    Content.id,
                    Content.title,
                    Content.url,
                    Content.published_at,
                    Content.entities,
                    Source.name.label("source_name"),
                    Source.bias_stance,
                )
                .join(Source, Source.id == Content.source_id)
                .where(Content.published_at >= since)
                .where(Content.entities.is_not(None))
            )
            rows = (await db.execute(stmt)).all()
    finally:
        await engine.dispose()
    return [
        Article(
            id=str(r.id),
            title=r.title or "",
            url=r.url or "",
            published_at=r.published_at,
            source_name=r.source_name or "?",
            bias_stance=r.bias_stance.value if r.bias_stance else "unknown",
            entities=list(r.entities or []),
        )
        for r in rows
    ]


def load_articles_from_dump(path: Path) -> list[Article]:
    data = json.loads(path.read_text(encoding="utf-8"))
    out: list[Article] = []
    for a in data["articles"]:
        out.append(
            Article(
                id=str(a["id"]),
                title=a["title"] or "",
                url=a.get("url") or "",
                published_at=datetime.fromisoformat(
                    a["published_at"].replace("Z", "+00:00")
                ),
                source_name=a.get("source_name") or "?",
                bias_stance=a.get("bias_stance") or "unknown",
                entities=list(a.get("entities") or []),
            )
        )
    return out


def build_pseudo_clusters(
    articles: list[Article], min_size: int, top_n: int
) -> list[tuple[str, str, list[Article]]]:
    """Reproduit `find_hot_cluster` : entity → articles, top par taille."""
    entity_to_articles: dict[str, list[Article]] = defaultdict(list)
    display_by_key: dict[str, str] = {}
    seen_by_entity: dict[str, set[str]] = defaultdict(set)
    for art in articles:
        for key, name in art.entity_keys():
            if art.id in seen_by_entity[key]:
                continue
            seen_by_entity[key].add(art.id)
            entity_to_articles[key].append(art)
            display_by_key.setdefault(key, name)
    eligible = [
        (key, arts)
        for key, arts in entity_to_articles.items()
        if len(arts) >= min_size
    ]
    eligible.sort(key=lambda kv: len(kv[1]), reverse=True)
    # Dédupliquer les clusters quasi-identiques (sous-ensemble strict) : on
    # garde le plus large quand deux entités ont les mêmes articles.
    deduped: list[tuple[str, str, list[Article]]] = []
    seen_signatures: list[frozenset[str]] = []
    for key, arts in eligible:
        sig = frozenset(a.id for a in arts)
        if any(sig.issubset(s) for s in seen_signatures):
            continue
        seen_signatures.append(sig)
        deduped.append((key, display_by_key[key], arts))
        if len(deduped) >= top_n:
            break
    return deduped


def format_span(span: dict) -> str:
    return f"`{span['text']}` [{span['start']}-{span['end']}]"


def format_token(tok: dict) -> str:
    parts = [f"`{tok['text']}`", f"lemma={tok['lemma']}", f"pos={tok['pos']}"]
    if tok.get("entity_kind"):
        parts.append(f"entity={tok['entity_kind']}")
    return " · ".join(parts)


def render_cluster(
    entity_key: str,
    entity_display: str,
    articles: list[Article],
    tokens_by_id: dict[str, list[dict]],
    ref_id: str,
    svc: TitleAnnotationService,
) -> str:
    ref = next(a for a in articles if a.id == ref_id)
    ref_tokens = tokens_by_id.get(ref_id, [])
    pivot = svc.compute_reference_pivot(ref_tokens)

    out: list[str] = []
    out.append(
        f"## Pseudo-cluster `{entity_display}` ({len(articles)} articles)\n"
    )
    out.append(
        f"**Référence** (la plus ancienne) — *{ref.source_name}* "
        f"({ref.bias_stance}) — {ref.published_at.isoformat()}\n"
    )
    out.append(f"> {ref.title}\n")
    if pivot:
        out.append(f"- **Pivot verbe (ref)** : {format_span(pivot)}")
    if ref_tokens:
        out.append("- **Strong tokens (ref)** :")
        for tok in ref_tokens:
            out.append(f"  - {format_token(tok)}")
    out.append("")

    out.append("### Perspectives (diff vs référence)\n")
    others = sorted(
        (a for a in articles if a.id != ref_id),
        key=lambda a: a.published_at,
    )
    for art in others:
        alt_tokens = tokens_by_id.get(art.id, [])
        highlight_spans = svc.diff_spans(ref_tokens, alt_tokens, art.bias_stance)
        shared_tokens = svc.compute_shared_tokens(ref_tokens, alt_tokens)

        out.append(
            f"#### *{art.source_name}* ({art.bias_stance}) — "
            f"{art.published_at.isoformat()}"
        )
        out.append(f"> {art.title}\n")
        if highlight_spans:
            out.append("- **highlight_spans (key)** :")
            for s in highlight_spans:
                out.append(f"  - {format_span(s)} bias={s['bias']}")
        else:
            out.append("- **highlight_spans (key)** : *(aucun)*")
        if shared_tokens:
            out.append("- **shared_tokens** :")
            for s in shared_tokens:
                out.append(f"  - {format_span(s)}")
        else:
            out.append("- **shared_tokens** : *(aucun)*")
        out.append("")

    out.append("### 🎯 Cible attendue (à remplir manuellement)\n")
    out.append(
        "<!-- Pour chaque perspective ci-dessus, lister les mots qui DEVRAIENT "
        "être surlignés selon le PO, et ceux à exclure. Format libre. -->\n"
    )
    out.append("---\n")
    return "\n".join(out)


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--hours", type=int, default=48)
    parser.add_argument("--min-size", type=int, default=3)
    parser.add_argument(
        "--max-per-cluster",
        type=int,
        default=6,
        help="Cap articles par cluster (les plus récents conservés)",
    )
    parser.add_argument(
        "--input",
        type=str,
        default=None,
        help="Dump JSON local (cf. forme dans le docstring). Si omis, "
        "interroge la DB via settings.database_url.",
    )
    parser.add_argument("--out", type=str, default=None)
    args = parser.parse_args()

    svc = get_title_annotation_service()
    if not svc.is_nlp_available:
        print(
            "❌ spaCy fr_core_news_md indisponible. "
            "Installe : pip install spacy==3.8.11 "
            "&& python -m spacy download fr_core_news_md",
            file=sys.stderr,
        )
        sys.exit(2)

    if args.input:
        articles = load_articles_from_dump(Path(args.input))
        # En mode dump, on respecte la fenêtre `hours` aussi.
        cutoff = datetime.now(timezone.utc) - timedelta(hours=args.hours)
        articles = [a for a in articles if a.published_at >= cutoff]
    else:
        articles = await fetch_articles_from_db(args.hours)

    if not articles:
        print("⚠️ Aucun article dans la fenêtre demandée.", file=sys.stderr)
        sys.exit(1)

    clusters = build_pseudo_clusters(
        articles, min_size=args.min_size, top_n=args.limit
    )
    if not clusters:
        print(
            f"⚠️ Aucun pseudo-cluster ≥{args.min_size} articles trouvé sur "
            f"{args.hours}h. Baisse --min-size ou élargis --hours.",
            file=sys.stderr,
        )
        sys.exit(1)

    sections: list[str] = []
    for entity_key, entity_display, arts in clusters:
        # Cap par cluster : on garde les plus récents pour rester lisible.
        arts = sorted(arts, key=lambda a: a.published_at, reverse=True)[
            : args.max_per_cluster
        ]
        titles = [a.title for a in arts]
        tokens_list = await svc.compute_strong_tokens_batch(titles)
        tokens_by_id = {arts[i].id: tokens_list[i] for i in range(len(arts))}
        ref = min(arts, key=lambda a: a.published_at)
        sections.append(
            render_cluster(
                entity_key, entity_display, arts, tokens_by_id, ref.id, svc
            )
        )

    today = datetime.now(timezone.utc).date().isoformat()
    out_path = (
        Path(args.out)
        if args.out
        else CONTEXT_DIR / f"highlight-cartography-{today}.md"
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)

    header = (
        f"# Cartographie highlighting — {today}\n\n"
        f"Généré par `packages/api/scripts/inspect_title_annotations.py`.\n"
        f"Fenêtre : {args.hours}h · Pseudo-clusters : {len(sections)} · "
        f"Taille min : {args.min_size}\n\n"
        f"Pipeline : `TitleAnnotationService` "
        f"(version `{svc.MODEL_VERSION}`, cap "
        f"`MAX_HIGHLIGHTED_PER_TITLE={svc.MAX_HIGHLIGHTED_PER_TITLE}`).\n\n"
        "> Pseudo-cluster = groupe d'articles partageant une entité "
        "discriminante (PERSON/ORG/EVENT) dans la fenêtre. Reproduit la "
        "logique de `find_hot_cluster` qui tourne en prod (sans persister "
        "`cluster_id`).\n\n"
        "---\n\n"
    )
    out_path.write_text(header + "\n".join(sections), encoding="utf-8")
    print(f"✅ Rapport écrit : {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
