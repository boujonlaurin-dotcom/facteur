#!/usr/bin/env python3
"""Preuve empirique avant/après — curation des sections thématiques (Tournée).

Fait tourner le **vrai** `PillarScoringEngine` sur les candidats réels de la
section « tech » du compte de référence `fd6b9d0b-4c16-422b-9688-bae34d63f41c`,
et imprime le reclassement :

  AVANT  = tri chronologique pur (comportement bugué : aucun scoring)
  APRÈS  = tri par score des 4 piliers + interleaving doux (le fix)

But (attendu par le PO) : montrer que les articles `content_quality='full'` +
image remontent, que les teasers `none` (non lisibles in-app) descendent, et que
le post Reddit EN tombe en bas — sur les données réelles du compte.

Les données du fixture sont les 20 candidats tech réels (fenêtre 24h, sources
suivies) extraits de la DB le 2026-06-01 10:09 UTC, avec les sous-thèmes pondérés
et les signaux de source réels du compte. Les signaux *appris* (affinité de
source, impressions) sont neutres ici — ils ne changent pas le reclassement
qualité-vs-récence démontré. Le rôle PG read-only `claude_analytics_ro` n'expose
pas `user_sources` / `contents` en SELECT direct, d'où le fixture (cf. hand-off).

Usage :
    cd packages/api && PYTHONPATH=. python scripts/prove_thematic_scoring.py
"""

import datetime
import sys
from pathlib import Path
from uuid import UUID, uuid4

sys.path.insert(0, str(Path(__file__).parent.parent))

UTC = datetime.UTC
NOW = datetime.datetime(2026, 6, 1, 10, 9, 0, tzinfo=UTC)

# --- Sources réelles (flags du compte) -------------------------------------
# name -> (is_curated, source_tier, reliability, priority_multiplier, subscribed)
SOURCES = {
    "Next.ink": (True, "deep", "high", 1.0, False),
    "Flux général Developpez.com": (False, "mainstream", "unknown", 0.2, False),
    "Le Monde": (True, "mainstream", "high", 0.2, False),
    "BDM": (False, "mainstream", "unknown", 2.0, False),
    "Mediapart": (True, "mainstream", "high", 1.0, False),
    "Courrier International": (True, "deep", "high", 2.0, False),
    "Le Grand Continent": (True, "deep", "high", 2.0, False),
    "Reddit's Startup Community": (False, "mainstream", "unknown", 2.0, True),
}

# --- 20 candidats tech réels (ordre chronologique DESC) ---------------------
# (titre, source, topics, content_quality, has_image, minutes_avant_now)
CANDIDATES = [
    (
        "SoftBank investit 75 Md€ pour 5 GW d'infra IA en France",
        "Next.ink",
        ["ai", "economy"],
        "full",
        True,
        51,
    ),
    (
        "Les LLM continuent de croire à des affirmations fausses…",
        "Flux général Developpez.com",
        ["ai"],
        "full",
        True,
        69,
    ),
    (
        "Nvidia lance ses propres processeurs pour PC Windows",
        "Le Monde",
        ["tech", "ai"],
        "none",
        False,
        98,
    ),
    (
        "IA : les meilleurs modèles pour le code en juin 2026",
        "BDM",
        ["ai", "tech"],
        "none",
        True,
        99,
    ),
    (
        "Instagram intègre un prompteur pour les Reels",
        "BDM",
        ["tech"],
        "none",
        True,
        115,
    ),
    (
        "☕️ Canonical s'occupe désormais de Flutter Desktop",
        "Next.ink",
        ["tech"],
        "none",
        False,
        121,
    ),
    (
        "Harvard : l'orateur fustige l'IA, « détruisez l'IA »",
        "Flux général Developpez.com",
        ["ai"],
        "full",
        True,
        144,
    ),
    (
        "Windows 11 : la barre des tâches redevient libre",
        "Next.ink",
        ["tech"],
        "none",
        True,
        151,
    ),
    (
        "☕️ Microsoft voudrait ranger tous ses Copilot dans une app",
        "Next.ink",
        ["ai", "tech"],
        "full",
        True,
        196,
    ),
    (
        "☕️ Paint.NET dispose enfin du domaine paint.net",
        "Next.ink",
        ["tech"],
        "full",
        True,
        218,
    ),
    (
        "Censés « vivre ensemble », 50 % des agents IA s'entretuent",
        "Next.ink",
        ["ai", "tech"],
        "full",
        True,
        242,
    ),
    (
        "☕️ Brûler des tokens n'est pas travailler : Amazon ferme…",
        "Next.ink",
        ["ai", "tech"],
        "full",
        True,
        277,
    ),
    (
        "Facebook a-t-il encore sa place en social media ?",
        "BDM",
        ["tech", "media"],
        "none",
        True,
        308,
    ),
    (
        "Enquête blanchiment 500 M€ vise la société Wise",
        "Mediapart",
        ["cybersecurity", "finance"],
        "none",
        True,
        310,
    ),
    (
        "« L'alerte de l'encyclique du pape sur l'IA »",
        "Le Monde",
        ["ai", "religion"],
        "none",
        False,
        368,
    ),
    ("Génération IA", "Le Grand Continent", ["ai"], "full", True, 369),
    (
        "Choose France : la course au gigantisme des datacenters IA",
        "Le Monde",
        ["ai", "tech"],
        "none",
        False,
        383,
    ),
    (
        "« L'IA a été créée par un petit groupe d'hommes blancs »",
        "Courrier International",
        ["ai", "science"],
        "none",
        True,
        428,
    ),
    (
        "I fired my SEO agency after 4 years. The weird thing…",
        "Reddit's Startup Community",
        ["ai", "startups"],
        "full",
        False,
        608,
    ),
    (
        "« Chine – États-Unis, la guerre de l'IA » sur France 5",
        "Le Monde",
        ["ai", "geopolitics"],
        "none",
        False,
        1089,
    ),
]

# --- Sous-thèmes pondérés réels du compte (extrait) -------------------------
USER_SUBTOPIC_WEIGHTS = {
    "ai": 3.0,
    "environment": 3.0,
    "tech": 3.0,
    "science": 2.99,
    "politics": 2.88,
    "media": 2.69,
    "privacy": 2.44,
    "inequality": 2.32,
    "economy": 2.28,
    "climate": 2.22,
    "startups": 2.19,
    "geopolitics": 1.12,
    "cybersecurity": 1.12,
    "finance": 1.24,
    "religion": 1.03,
}


def _build():
    from app.models.content import Content
    from app.models.enums import ContentType, ReliabilityScore
    from app.models.source import Source

    src_objs: dict[str, Source] = {}
    src_ids: dict[str, UUID] = {}
    for name, (curated, tier, rel, _mult, _sub) in SOURCES.items():
        sid = uuid4()
        src_ids[name] = sid
        src_objs[name] = Source(
            id=sid,
            name=name,
            theme="tech",
            is_curated=curated,
            source_tier=tier,
            reliability_score=ReliabilityScore(rel),
            secondary_themes=[],
            tone=None,
        )

    contents = []
    for title, sname, topics, quality, has_img, mins in CANDIDATES:
        contents.append(
            Content(
                id=uuid4(),
                title=title,
                theme="tech",
                topics=topics,
                content_quality=quality,
                thumbnail_url="https://img" if has_img else None,
                language=None,  # comme en DB — le post Reddit EN passe (language=null)
                published_at=NOW - datetime.timedelta(minutes=mins),
                source_id=src_ids[sname],
                source=src_objs[sname],
                description="",
                content_type=ContentType.ARTICLE,
                duration_seconds=None,
                entities=[],
            )
        )
    return contents, src_ids


def _context(src_ids):
    from app.models.enums import InterestState
    from app.services.recommendation.scoring_engine import ScoringContext

    priority = {src_ids[n]: SOURCES[n][3] for n in SOURCES}
    subscribed = {src_ids[n] for n in SOURCES if SOURCES[n][4]}
    followed = set(src_ids.values())
    return ScoringContext(
        user_profile=None,
        user_interests={"tech", "science", "environment"},
        user_interest_weights={"tech": 3.0, "science": 2.99, "environment": 3.0},
        followed_source_ids=followed,
        user_prefs={},
        now=NOW,
        user_subtopics=set(USER_SUBTOPIC_WEIGHTS),
        user_subtopic_weights=USER_SUBTOPIC_WEIGHTS,
        source_priority_multipliers=priority,
        subscribed_source_ids=subscribed,
        user_interest_states={"tech": InterestState.FAVORITE},
    )


def _flag(c) -> str:
    q = (getattr(c, "content_quality", None) or "none")[:4].ljust(4)
    img = "IMG" if (c.thumbnail_url or "").strip() else " · "
    return f"{q} {img}"


def main() -> int:
    from app.services.recommendation.scoring_engine import PillarScoringEngine
    from app.services.recommendation_service import RecommendationService

    contents, src_ids = _build()
    context = _context(src_ids)
    engine = PillarScoringEngine()
    scores = {c.id: engine.compute_score(c, context) for c in contents}

    before = sorted(contents, key=lambda c: c.published_at, reverse=True)
    after = RecommendationService._apply_source_interleaving(
        sorted(contents, key=lambda c: scores[c.id].final_score, reverse=True)
    )

    print(
        f"\n{'=' * 92}\nSection « tech » — {len(contents)} candidats réels (compte fd6b9d0b)\n{'=' * 92}"
    )
    print("\n--- AVANT (chronologique pur — bug actuel) ---")
    print(f"{'#':>2}  qual img  {'source':<22} titre")
    for i, c in enumerate(before, 1):
        print(f"{i:>2}  {_flag(c)} {(c.source.name):<22} {c.title[:50]}")

    print("\n--- APRÈS (PillarScoringEngine + interleaving — fix) ---")
    print(f"{'#':>2}  score qual img  {'source':<22} titre")
    for i, c in enumerate(after, 1):
        print(
            f"{i:>2}  {scores[c.id].final_score:>5.1f} {_flag(c)} {(c.source.name):<22} {c.title[:46]}"
        )

    _verdict(before, after)
    return 0


def _verdict(before, after) -> None:
    def rank(lst, pred):
        return [i for i, c in enumerate(lst, 1) if pred(c)]

    def avg(rs):
        return sum(rs) / len(rs) if rs else 0.0

    def is_rich(c):
        return c.content_quality == "full" and bool((c.thumbnail_url or "").strip())

    def is_none(c):
        return c.content_quality == "none"

    def is_reddit(c):
        return "reddit" in c.source.name.lower()

    rb, ra = rank(before, is_rich), rank(after, is_rich)
    nb, na = rank(before, is_none), rank(after, is_none)
    n = len(after)
    print(f"\n{'=' * 92}\nVERDICT\n{'=' * 92}")
    print(
        f"full+image — rang moyen : {avg(rb):.1f} → {avg(ra):.1f}  (plus bas = mieux)"
    )
    print(
        f"full+image dans le top 5 : {len([r for r in rb if r <= 5])} → {len([r for r in ra if r <= 5])} / 5"
    )
    print(
        f"teasers 'none' — rang moyen : {avg(nb):.1f} → {avg(na):.1f}  (plus haut = mieux)"
    )
    print(
        f"teasers 'none' dans le top 5 : {len([r for r in nb if r <= 5])} → {len([r for r in na if r <= 5])} / 5"
    )
    print(
        f"post Reddit EN — rang : {rank(before, is_reddit)} → {rank(after, is_reddit)}  (sur {n})"
    )


if __name__ == "__main__":
    raise SystemExit(main())
