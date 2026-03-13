#!/usr/bin/env python3
"""Test réel de la pipeline éditoriale contre Supabase prod — Story 10.23.

READ-ONLY: Ce script n'écrit rien en base. Il observe et affiche les résultats
pour validation humaine avant tout ajustement.

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/test_editorial_pipeline.py           # Full pipeline avec LLM
    python scripts/test_editorial_pipeline.py --no-llm   # Fallback déterministe
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import time
from collections import Counter
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

# Ensure packages/api is on sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Parse args BEFORE importing app modules (--no-llm must unset env var early)
parser = argparse.ArgumentParser(description="Test editorial pipeline against prod data")
parser.add_argument("--no-llm", action="store_true", help="Disable LLM (test fallback)")
parser.add_argument("--hours", type=int, default=48, help="Content lookback hours (default: 48)")
parser.add_argument("--user", type=str, default=None, help="User display_name to search for (default: Laurin)")
args = parser.parse_args()

if args.no_llm:
    os.environ.pop("MISTRAL_API_KEY", None)
    os.environ["MISTRAL_API_KEY"] = ""
    print("\n[MODE] Fallback déterministe (LLM désactivé)\n")
else:
    print("\n[MODE] Pipeline complète avec LLM\n")

# Now import app modules (they read env vars at import time)
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app.database import async_session_maker, engine
from app.models.content import Content, UserContentStatus
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.services.briefing.importance_detector import ImportanceDetector, TopicCluster
from app.services.editorial.config import load_editorial_config
from app.services.editorial.curation import CurationService
from app.services.editorial.deep_matcher import DeepMatcher
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.pipeline import EditorialPipelineService
from app.services.editorial.schemas import EditorialGlobalContext


# ── Helpers ──────────────────────────────────────────────────────────────────

SEPARATOR = "=" * 70
SUBSEP = "-" * 50


def header(title: str) -> None:
    print(f"\n{SEPARATOR}")
    print(f"  {title}")
    print(SEPARATOR)


def elapsed(start: float) -> str:
    return f"{(time.time() - start) * 1000:.0f}ms"


# ── ÉTAPE 1: Charger contenus récents ────────────────────────────────────────

async def step1_load_contents(session, hours: int) -> list[Content]:
    header(f"ÉTAPE 1 — Charger contenus récents (< {hours}h)")

    since = datetime.now(UTC) - timedelta(hours=hours)
    stmt = (
        select(Content)
        .join(Content.source)
        .options(selectinload(Content.source))
        .where(
            Content.published_at >= since,
            Source.is_active.is_(True),
        )
        .order_by(Content.published_at.desc())
    )

    t0 = time.time()
    result = await session.execute(stmt)
    contents = list(result.scalars().all())
    print(f"  Chargés: {len(contents)} articles en {elapsed(t0)}")

    if not contents:
        print("  ⚠ Aucun contenu trouvé. Vérifiez DATABASE_URL et la fenêtre temporelle.")
        return []

    # Répartition par source
    source_counter = Counter(c.source.name if c.source else "?" for c in contents)
    print(f"\n  Répartition par source ({len(source_counter)} sources):")
    for name, count in source_counter.most_common(15):
        print(f"    {count:3d}  {name}")
    if len(source_counter) > 15:
        print(f"    ... et {len(source_counter) - 15} autres sources")

    # Répartition par theme
    theme_counter = Counter(c.theme or "null" for c in contents)
    print(f"\n  Répartition par thème:")
    for theme, count in theme_counter.most_common():
        print(f"    {count:3d}  {theme}")

    # Deep vs mainstream
    deep_count = sum(1 for c in contents if c.source and c.source.source_tier == "deep")
    print(f"\n  Tier: {len(contents) - deep_count} mainstream, {deep_count} deep")

    return contents


# ── ÉTAPE 2: compute_global_context() ────────────────────────────────────────

async def step2_global_context(
    session, contents: list[Content]
) -> tuple[EditorialGlobalContext | None, list[TopicCluster]]:
    header("ÉTAPE 2 — compute_global_context()")

    # 2a. Clustering
    t0 = time.time()
    detector = ImportanceDetector()
    clusters = detector.build_topic_clusters(contents)
    print(f"\n  2a. Clustering: {len(clusters)} clusters en {elapsed(t0)}")

    if not clusters:
        print("  ⚠ Aucun cluster. Pipeline ne peut pas continuer.")
        return None, []

    print(f"\n  Top 10 clusters:")
    for i, c in enumerate(clusters[:10]):
        trending = " [TRENDING]" if c.is_trending else ""
        print(f"    {i+1}. [{c.cluster_id[:8]}] {c.label[:70]}")
        print(f"       {len(c.contents)} articles, {len(c.source_ids)} sources, theme={c.theme}{trending}")

    # 2b. LLM Curation
    config = load_editorial_config()
    llm = EditorialLLMClient()
    curation = CurationService(llm, config)

    print(f"\n  {SUBSEP}")
    print(f"  2b. LLM Curation (llm.is_ready={llm.is_ready})")

    t0 = time.time()
    selected_topics = await curation.select_topics(clusters)
    print(f"  Durée: {elapsed(t0)}")

    if not selected_topics:
        print("  ⚠ Curation a échoué. Pas de sujets sélectionnés.")
        await llm.close()
        return None, clusters

    print(f"\n  {len(selected_topics)} sujets sélectionnés:")
    for j, topic in enumerate(selected_topics):
        print(f"\n    Sujet {j+1}:")
        print(f"      topic_id:         {topic.topic_id}")
        print(f"      label:            {topic.label}")
        print(f"      selection_reason:  {topic.selection_reason}")
        print(f"      deep_angle:       {topic.deep_angle}")

    # 2c. Deep matching
    print(f"\n  {SUBSEP}")
    print(f"  2c. Deep Matching")

    deep_matcher = DeepMatcher(session, llm, config)

    # Load deep articles for debug display
    deep_articles = await deep_matcher._load_deep_articles()
    print(f"  Pool deep articles: {len(deep_articles)}")
    if deep_articles:
        deep_source_counter = Counter(
            a.source.name if a.source else "?" for a in deep_articles
        )
        print(f"  Sources deep ({len(deep_source_counter)}):")
        for name, count in deep_source_counter.most_common():
            print(f"    {count:3d}  {name}")

    # Query expansion (enrich tokens before Jaccard)
    expanded_tokens: dict[str, set[str]] = {}
    if llm.is_ready:
        import asyncio as _aio

        expansion_tasks = [deep_matcher._expand_query(t) for t in selected_topics]
        expansion_results = await _aio.gather(*expansion_tasks, return_exceptions=True)
        for topic, result in zip(selected_topics, expansion_results, strict=False):
            if isinstance(result, set):
                expanded_tokens[topic.topic_id] = result
            else:
                print(f"    ⚠ Expansion failed for {topic.topic_id[:8]}: {result}")

    # Show Jaccard prefilter details for each topic
    threshold = config.pipeline.deep_jaccard_threshold
    prefilter_limit = config.pipeline.deep_candidates_prefilter
    print(f"\n  Jaccard threshold={threshold}, prefilter_limit={prefilter_limit}")

    for topic in selected_topics:
        extra = expanded_tokens.get(topic.topic_id, set())
        candidates = deep_matcher._prefilter(
            topic=topic,
            articles=deep_articles,
            limit=prefilter_limit,
            threshold=threshold,
            extra_tokens=extra,
        )
        print(f"\n    [{topic.topic_id[:8]}] \"{topic.label}\"")
        if extra:
            print(f"    Expanded tokens ({len(extra)}): {sorted(extra)}")
        print(f"    Jaccard candidates: {len(candidates)}")
        for k, (article, score) in enumerate(candidates[:5]):
            src = article.source.name if article.source else "?"
            pub = article.published_at.strftime("%Y-%m-%d")
            print(f"      {k+1}. score={score:.3f} | {article.title[:60]} ({src}, {pub})")

    # Now run full deep matching (with LLM pass 2 if available)
    t0 = time.time()
    deep_matches = await deep_matcher.match_for_topics(selected_topics)
    print(f"\n  Deep matching complet en {elapsed(t0)}")

    deep_hits = sum(1 for v in deep_matches.values() if v is not None)
    print(f"  Résultat: {deep_hits}/{len(selected_topics)} sujets avec article deep")

    for topic in selected_topics:
        match = deep_matches.get(topic.topic_id)
        print(f"\n    [{topic.topic_id[:8]}] \"{topic.label}\"")
        if match:
            print(f"      -> {match.title[:70]}")
            print(f"         source: {match.source_name}")
            print(f"         published: {match.published_at.strftime('%Y-%m-%d')}")
            print(f"         reason: {match.match_reason}")
        else:
            print(f"      -> (aucun article deep trouvé)")

    # Build global context (replicate pipeline logic)
    from app.services.editorial.schemas import EditorialSubject

    subjects = [
        EditorialSubject(
            rank=i + 1,
            topic_id=topic.topic_id,
            label=topic.label,
            selection_reason=topic.selection_reason,
            deep_angle=topic.deep_angle,
            deep_article=deep_matches.get(topic.topic_id),
        )
        for i, topic in enumerate(selected_topics)
    ]

    cluster_data = [
        {
            "cluster_id": c.cluster_id,
            "label": c.label,
            "content_ids": [str(content.id) for content in c.contents],
            "source_ids": [str(sid) for sid in c.source_ids],
            "theme": c.theme,
        }
        for c in clusters
    ]

    global_ctx = EditorialGlobalContext(
        subjects=subjects,
        cluster_data=cluster_data,
        generated_at=datetime.now(UTC),
    )

    await llm.close()
    return global_ctx, clusters


# ── ÉTAPE 3: run_for_user() ──────────────────────────────────────────────────

async def step3_run_for_user(
    session,
    global_ctx: EditorialGlobalContext,
    clusters: list[TopicCluster],
) -> dict | None:
    header("ÉTAPE 3 — run_for_user() pour un user réel")

    # Find user
    search_name = args.user or "Laurin"
    stmt = select(UserProfile).where(
        UserProfile.display_name.ilike(f"%{search_name}%")
    )
    result = await session.execute(stmt)
    user = result.scalars().first()

    if not user:
        # Fallback: first user with sources
        print(f"  User '{search_name}' non trouvé, recherche du premier user avec sources...")
        stmt = (
            select(UserSource.user_id, func.count(UserSource.id).label("cnt"))
            .group_by(UserSource.user_id)
            .order_by(func.count(UserSource.id).desc())
            .limit(1)
        )
        result = await session.execute(stmt)
        row = result.first()
        if row:
            user_id = row[0]
            source_count = row[1]
            print(f"  Utilisation du user {user_id} ({source_count} sources)")
        else:
            print("  ⚠ Aucun user avec des sources trouvé.")
            return None
    else:
        user_id = user.user_id
        print(f"  User trouvé: {user.display_name} (user_id={user_id})")

    # Load followed source IDs
    stmt = select(UserSource).where(UserSource.user_id == user_id)
    result = await session.execute(stmt)
    user_sources = list(result.scalars().all())
    followed_source_ids = {us.source_id for us in user_sources}
    print(f"  Sources suivies: {len(followed_source_ids)}")

    # Load excluded content IDs (seen/hidden/saved)
    stmt = select(UserContentStatus.content_id).where(
        UserContentStatus.user_id == user_id,
        or_(
            UserContentStatus.is_hidden.is_(True),
            UserContentStatus.is_saved.is_(True),
            UserContentStatus.status.in_(["seen", "consumed"]),
        ),
    )
    result = await session.execute(stmt)
    excluded_content_ids = {row[0] for row in result.all()}
    print(f"  Contenus exclus: {len(excluded_content_ids)}")

    # Run per-user matching
    pipeline = EditorialPipelineService(session)
    t0 = time.time()
    pipeline_result = pipeline.run_for_user(
        global_ctx=global_ctx,
        clusters=clusters,
        user_source_ids=followed_source_ids,
        excluded_content_ids=excluded_content_ids,
    )
    print(f"\n  run_for_user() en {elapsed(t0)}")

    # Display results
    print(f"\n  Metadata: {json.dumps(pipeline_result.metadata, indent=4)}")

    for s in pipeline_result.subjects:
        print(f"\n  Sujet {s.rank}: \"{s.label}\"")
        print(f"    selection_reason: {s.selection_reason}")
        print(f"    deep_angle:      {s.deep_angle}")

        if s.actu_article:
            a = s.actu_article
            print(f"    ACTU: {a.title[:70]}")
            print(f"          source={a.source_name}, is_user_source={a.is_user_source}")
            print(f"          published={a.published_at.strftime('%Y-%m-%d %H:%M')}")
        else:
            print(f"    ACTU: (aucun article actu trouvé)")

        if s.deep_article:
            d = s.deep_article
            print(f"    DEEP: {d.title[:70]}")
            print(f"          source={d.source_name}")
            print(f"          published={d.published_at.strftime('%Y-%m-%d')}")
            print(f"          reason={d.match_reason}")
        else:
            print(f"    DEEP: (aucun article deep)")

    # Build editorial_v1 JSON (Step 4)
    return _build_editorial_json(pipeline_result)


# ── ÉTAPE 4: JSON editorial_v1 ───────────────────────────────────────────────

def _build_editorial_json(pipeline_result) -> dict:
    """Build the editorial_v1 JSONB exactly as _create_digest_record_editorial() does."""
    return {
        "format_version": "editorial_v1",
        "header_text": None,
        "mode": "pour_vous",
        "subjects": [
            {
                "rank": s.rank,
                "topic_id": s.topic_id,
                "label": s.label,
                "selection_reason": s.selection_reason,
                "deep_angle": s.deep_angle,
                "intro_text": s.intro_text,
                "transition_text": s.transition_text,
                "actu_article": {
                    "content_id": str(s.actu_article.content_id),
                    "title": s.actu_article.title,
                    "source_name": s.actu_article.source_name,
                    "source_id": str(s.actu_article.source_id),
                    "is_user_source": s.actu_article.is_user_source,
                    "badge": "actu",
                    "published_at": s.actu_article.published_at.isoformat(),
                }
                if s.actu_article
                else None,
                "deep_article": {
                    "content_id": str(s.deep_article.content_id),
                    "title": s.deep_article.title,
                    "source_name": s.deep_article.source_name,
                    "source_id": str(s.deep_article.source_id),
                    "badge": "pas_de_recul",
                    "match_reason": s.deep_article.match_reason,
                    "published_at": s.deep_article.published_at.isoformat(),
                }
                if s.deep_article
                else None,
            }
            for s in pipeline_result.subjects
        ],
        "pepite": None,
        "coup_de_coeur": None,
        "closure_text": None,
        "cta_text": None,
        "generated_at": datetime.utcnow().isoformat(),
        "metadata": pipeline_result.metadata,
    }


# ── Main ─────────────────────────────────────────────────────────────────────

async def main():
    print(f"Connexion à la DB...")

    async with async_session_maker() as session:
        # Step 1
        contents = await step1_load_contents(session, args.hours)
        if not contents:
            return

        # Step 2
        global_ctx, clusters = await step2_global_context(session, contents)
        if not global_ctx:
            return

        # Step 3 + 4
        editorial_json = await step3_run_for_user(session, global_ctx, clusters)

        if editorial_json:
            header("ÉTAPE 4 — JSON editorial_v1 complet")
            print(json.dumps(editorial_json, indent=2, ensure_ascii=False, default=str))

    # Cleanup
    await engine.dispose()
    print(f"\n{SEPARATOR}")
    print("  Test terminé.")
    print(SEPARATOR)


if __name__ == "__main__":
    asyncio.run(main())
