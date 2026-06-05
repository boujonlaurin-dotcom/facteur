#!/usr/bin/env python3
"""Preuve empirique avant/après — curation veille par score (Story 23.4).

Fait tourner le **vrai** pipeline `_score_and_rank` (floor + scoring piliers +
seuil + anti-starvation) sur un pool de candidats mixtes typique du bug observé
sur le compte proton (`fd6b9d0b…`) : une poignée d'articles on-angle noyés sous
le flot d'une source suivie qui « déverse » tout son flux.

  AVANT  = dump OR chronologique (bug : la source est un free-pass, son flux
           entier passe le seuil grâce au pilier Source + Fraîcheur)
  APRÈS  = floor (« la source est un boost, pas un free-pass ») + scoring v2
           (topic canonique +50, mots-clés escaladants, combo +15)

Angle de veille : topic canonique ``ai`` (« IA ») + grappe ``[llm, gpt, agent]``.

Verdict attendu (PO) :
  - les articles source-seule **off-angle** (ni topic ni mot-clé) sont écartés
    par le floor → le flood est tué ;
  - l'article topic + 2 mots-clés d'une source suivie est **#1** ;
  - un article on-topic d'une source **non suivie** survit (la source n'est pas
    une condition d'entrée).

Usage :
    cd packages/api && PYTHONPATH=. python scripts/prove_veille_curation.py
"""

import datetime
import sys
from pathlib import Path
from uuid import UUID, uuid4

sys.path.insert(0, str(Path(__file__).parent.parent))

UTC = datetime.UTC
NOW = datetime.datetime(2026, 6, 2, 10, 0, 0, tzinfo=UTC)

# Angle principal de la veille.
ANGLE_TOPIC = "ai"
ANGLE_LABEL = "IA"
ANGLE_KEYWORDS = ["llm", "gpt", "agent"]

# --- Sources (name -> followed?) -------------------------------------------
SOURCES = {
    "Next.ink": True,
    "Le Monde": True,
    "BDM": True,
    "TechCrunch": False,  # non suivie : sert à prouver qu'un on-topic survit
}

# --- Candidats mixtes -------------------------------------------------------
# (titre, source, topics, theme, mins_avant_now)
# Les mots-clés d'angle apparaissent (ou non) littéralement dans le titre.
CANDIDATES = [
    # on-angle forts (source suivie)
    ("Nouveau LLM GPT-5 : un agent IA autonome", "Next.ink", ["ai"], "tech", 30),
    ("Le nouveau LLM de Mistral impressionne", "Le Monde", ["ai"], "tech", 65),
    ("Avancées en intelligence artificielle générale", "Next.ink", ["ai"], "tech", 90),
    # mot-clé seul (pas de topic ai) — reste on-angle via le keyword 'agent'
    ("Un agent conversationnel pour le support client", "BDM", ["tech"], "tech", 120),
    # on-topic d'une source NON suivie — doit survivre
    ("OpenAI dévoile un nouveau modèle de raisonnement", "TechCrunch", ["ai"], "tech", 75),
    # source-seule OFF-angle (ni topic ni keyword) — DOIT être floor-pruned
    ("Résultats du PSG hier soir en Ligue 1", "Next.ink", ["sport"], "sport", 40),
    # flood d'une source suivie, tout off-angle — DOIT être tué par le floor
    ("Test du dernier smartphone pliable", "BDM", ["tech"], "tech", 50),
    ("Comparatif des meilleures consoles 2026", "BDM", ["gaming"], "tech", 55),
    ("Bons plans : -40% sur les écouteurs", "BDM", ["tech"], "tech", 60),
    ("Tuto : installer Linux sur un vieux PC", "BDM", ["tech"], "tech", 70),
    ("Le clavier mécanique qu'il vous faut", "BDM", ["tech"], "tech", 80),
    ("Windows 11 : la mise à jour de juin", "Next.ink", ["tech"], "tech", 100),
]


def _build():
    from app.models.content import Content
    from app.models.enums import ContentType
    from app.models.source import Source

    src_ids: dict[str, UUID] = {}
    src_objs: dict[str, Source] = {}
    for name in SOURCES:
        sid = uuid4()
        src_ids[name] = sid
        src_objs[name] = Source(
            id=sid,
            name=name,
            theme="tech",
            is_curated=True,
            secondary_themes=[],
            tone=None,
        )

    contents = []
    for title, sname, topics, theme, mins in CANDIDATES:
        contents.append(
            Content(
                id=uuid4(),
                title=title,
                description="",
                theme=theme,
                topics=topics,
                published_at=NOW - datetime.timedelta(minutes=mins),
                source_id=src_ids[sname],
                source=src_objs[sname],
                content_type=ContentType.ARTICLE,
                duration_seconds=None,
                entities=[],
                content_quality="full",
                thumbnail_url="https://img",
            )
        )
    return contents, src_ids


def _filters_and_context(src_ids):
    from app.services.recommendation.scoring_engine import ScoringContext
    from app.services.veille.feed_filter import VeilleAngle, VeilleFilters
    from app.services.veille.scoring_context import VeilleAngleTopic

    followed = {src_ids[n] for n in SOURCES if SOURCES[n]}
    filters = VeilleFilters(
        theme_id="tech",
        angles=[VeilleAngle(topic_id=ANGLE_TOPIC, label=ANGLE_LABEL, keywords=ANGLE_KEYWORDS)],
        source_ids=list(followed),
        global_keywords=[],
    )
    context = ScoringContext(
        user_profile=None,
        user_interests={"tech"},
        user_interest_weights={},
        followed_source_ids=followed,
        user_prefs={},
        now=NOW,
        user_subtopics={ANGLE_TOPIC},
        user_subtopic_weights={},
        user_custom_topics=[
            VeilleAngleTopic(
                slug_parent=ANGLE_TOPIC,
                keywords=ANGLE_KEYWORDS,
                topic_name=ANGLE_LABEL,
                is_veille=True,
            )
        ],
    )
    return filters, context


def main() -> int:
    from app.services.veille.feed_filter import _matched_axes, _score_block

    contents, src_ids = _build()
    filters, context = _filters_and_context(src_ids)

    topic_slugs = set(filters.topic_slugs)
    source_ids = set(filters.source_ids)
    keywords = filters.all_keywords

    kept = _score_block(
        list(contents), context, filters, apply_floor=True, apply_threshold=True
    )
    kept_ids = {c.id for c, _s, _a in kept}

    print("=" * 92)
    print(f"Veille — angle ({ANGLE_TOPIC!r}, {ANGLE_LABEL!r}, {ANGLE_KEYWORDS}) — "
          f"{len(contents)} candidats mixtes")
    print("=" * 92)

    print("\n--- AVANT (dump OR chronologique — la source est un free-pass) ---")
    print(f"{'#':>2}  {'axes':<18} {'source':<12} titre")
    chrono = sorted(contents, key=lambda c: c.published_at, reverse=True)
    for i, c in enumerate(chrono, 1):
        axes = _matched_axes(c, topic_slugs, source_ids, keywords)
        print(f"{i:>2}  {','.join(axes) or '∅':<18} {c.source.name:<12} {c.title[:46]}")

    print("\n--- APRÈS (floor + scoring v2 + seuil) ---")
    print(f"{'#':>2}  {'score':>5} {'axes':<18} {'source':<12} titre")
    for i, (c, score, axes) in enumerate(kept, 1):
        print(f"{i:>2}  {score:>5.1f} {','.join(axes):<18} {c.source.name:<12} {c.title[:46]}")

    _verdict(contents, kept, kept_ids, topic_slugs, source_ids, keywords)
    return 0


def _verdict(contents, kept, kept_ids, topic_slugs, source_ids, keywords):
    from app.services.veille.feed_filter import _matched_axes

    print("\n" + "=" * 92)
    print("VERDICT")
    print("=" * 92)

    # 1. Tout candidat source-seule off-angle (axes ⊆ {source}) est écarté.
    off_angle = [
        c for c in contents
        if "topic" not in _matched_axes(c, topic_slugs, source_ids, keywords)
        and "keyword" not in _matched_axes(c, topic_slugs, source_ids, keywords)
    ]
    off_angle_kept = [c for c in off_angle if c.id in kept_ids]
    ok_floor = not off_angle_kept
    print(f"[{'OK' if ok_floor else 'FAIL'}] floor : {len(off_angle)} articles source-seule "
          f"off-angle écartés ({len(off_angle_kept)} ont survécu)")

    # 2. L'article topic + 2 mots-clés est #1.
    top = kept[0][0] if kept else None
    ok_top = top is not None and "GPT-5" in top.title
    print(f"[{'OK' if ok_top else 'FAIL'}] #1 = topic + mots-clés : "
          f"{top.title[:50] if top else '∅'!r}")

    # 3. Un on-topic d'une source NON suivie survit.
    non_followed_on_topic = next(
        (c for c in contents if "OpenAI" in c.title), None
    )
    ok_nf = non_followed_on_topic is not None and non_followed_on_topic.id in kept_ids
    print(f"[{'OK' if ok_nf else 'FAIL'}] on-topic source non suivie conservé : {ok_nf}")

    all_ok = ok_floor and ok_top and ok_nf
    print(f"\n{'✅ VERDICT GLOBAL : OK' if all_ok else '❌ VERDICT GLOBAL : FAIL'}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
