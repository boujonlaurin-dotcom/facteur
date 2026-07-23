"""Cœur de la promotion catalogue (`is_curated`) — logique pure + couche DB.

Extrait de `scripts/retag_and_promote_sources.py` pour être importable depuis
l'app (le job hebdo `app/jobs/promote_sources_job.py`) sans dépendre du package
`scripts/` — celui-ci n'est pas embarqué dans l'image Docker, donc un
`from scripts...` au boot plante le conteneur. Le script CLI importe désormais
d'ici (dépendance script -> app, le bon sens).

Contenu : le gate de promotion (biais/fiabilité/volume/denylist), les
dataclasses `SourceMeta`/`Promotion`, le sous-plan léger `compute_promotions`
(promotions seules, sans re-tag ni audit) et les helpers DB `load_metas` /
`write_promotions`. Le re-tag `granular_topics`, l'audit de couverture et la
régénération CSV restent dans le script (usage manuel + revue PO).
"""

from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import text

from app.services.source_recommendation_gate import QUALITY_CATALOG_EXCLUDED_BIAS

PROMO_WINDOW_DAYS = 30  # fenêtre du volume pour la promotion
PROMO_MIN_VOLUME = 20  # articles_30d mini pour promouvoir
PROMO_RELIABILITY = {"medium", "high"}
# Biais exclus de la promotion. **Dérivé** (pas copié) du gate de RECOMMANDATION
# `source_recommendation_gate.QUALITY_CATALOG_EXCLUDED_BIAS` -> une seule source
# de vérité : une source `alternative`/`unknown` ne doit JAMAIS être stampée
# `is_curated=true` (elle entrerait au catalogue curé sans jamais remonter dans
# « Étoffer »). `specialized` reste promouvable (biais thématique, pas idéologique).
PROMO_EXCLUDED_BIAS = frozenset(b.value for b in QUALITY_CATALOG_EXCLUDED_BIAS)


def _norm_url(u: str | None) -> str:
    return (u or "").strip().rstrip("/").lower()


# Denylist ÉDITORIALE (décision PO 2026-07-22) : sources qui passent le gate
# automatique (biais connu + fiabilité medium/high + volume) mais dont la
# promotion au « catalogue qualité Facteur » se discute — l'auto-promotion ne
# peut pas juger la valeur éditoriale. On les exclut par URL (normalisée) tant
# qu'un choix PO explicite ne les réintègre pas. Réversible : retirer la ligne.
PROMO_DENYLIST_RAW: dict[str, str] = {
    # Blogs corpo / vendor (contenu promotionnel par nature)
    "https://huggingface.co/blog": "Blog de Hugging Face (corpo)",
    "https://thestack.technology/": "The Stack by Humanloop (vendor)",
    # Newsletters / agrégateurs (pas du reportage primaire)
    "https://tldr.tech/rss": "TLDR (agrégateur newsletter)",
    "https://www.lennysnewsletter.com/": "Lenny's Newsletter",
    "https://www.latent.space/": "Latent Space (newsletter)",
    "https://towardsdatascience.com": "Towards Data Science (Medium UGC)",
    "https://korben.info/feed": "Korben (blog perso)",
    # Hyper-niche / hors ligne éditoriale
    "https://www.reggae.fr/dev/rss/news.php": "Reggae.fr (niche musique)",
    "https://www.h2-mobile.fr/feed/": "H2-mobile.fr (niche hydrogène)",
    "https://www.vertigemedia.fr/blog-feed.xml": "Vertige Media (niche)",
    # Data aggregator
    "https://www.statista.com": "Statista (agrégateur data)",
    # ONG militante (pas un média d'information)
    "https://www.amnesty.org/": "Amnesty International (ONG)",
}
PROMO_DENYLIST = frozenset(_norm_url(u) for u in PROMO_DENYLIST_RAW)


@dataclass
class SourceMeta:
    source_id: str
    name: str
    url: str
    theme: str | None
    type: str
    is_curated: bool
    bias_stance: str
    reliability_score: str
    description: str | None
    score_independence: float | None
    score_rigor: float | None
    score_ux: float | None
    source_tier: str
    granular_topics: list[str] | None
    articles_30d: int


@dataclass
class Promotion:
    source_id: str
    name: str
    url: str
    theme: str | None
    type: str
    bias_stance: str
    reliability_score: str
    description: str | None
    score_independence: float | None
    score_rigor: float | None
    score_ux: float | None
    source_tier: str
    granular_topics: list[str] | None
    articles_30d: int


def is_promotable(
    m: SourceMeta,
    *,
    min_volume: int = PROMO_MIN_VOLUME,
    reliability_set: set[str] = PROMO_RELIABILITY,
    excluded_bias: frozenset[str] = PROMO_EXCLUDED_BIAS,
    denylist: frozenset[str] = PROMO_DENYLIST,
) -> bool:
    """Source évaluée + productive, non curée, non denylistée : candidate.

    Biais **connu et non alternatif** (aligné sur le gate de recommandation),
    fiabilité medium/high, volume suffisant, et pas dans la denylist éditoriale.
    """
    return (
        not m.is_curated
        and m.bias_stance not in excluded_bias
        and m.reliability_score in reliability_set
        and m.articles_30d >= min_volume
        and _norm_url(m.url) not in denylist
    )


def _to_promotion(m: SourceMeta, granular_topics: list[str] | None) -> Promotion:
    """Projette une source promue en `Promotion` (report / CSV / DB)."""
    return Promotion(
        source_id=m.source_id,
        name=m.name,
        url=m.url,
        theme=m.theme,
        type=m.type,
        bias_stance=m.bias_stance,
        reliability_score=m.reliability_score,
        description=m.description,
        score_independence=m.score_independence,
        score_rigor=m.score_rigor,
        score_ux=m.score_ux,
        source_tier=m.source_tier,
        granular_topics=granular_topics,
        articles_30d=m.articles_30d,
    )


def compute_promotions(
    metas: list[SourceMeta],
    *,
    min_volume: int = PROMO_MIN_VOLUME,
    reliability_set: set[str] = PROMO_RELIABILITY,
    excluded_bias: frozenset[str] = PROMO_EXCLUDED_BIAS,
    denylist: frozenset[str] = PROMO_DENYLIST,
) -> list[Promotion]:
    """Sous-plan léger « promotions seules » — sans dériver `granular_topics`
    ni auditer la couverture. Utilisé par le job hebdo (qui ne réécrit que
    `is_curated`) ; conserve `granular_topics` tel quel (jamais écrit)."""
    return [
        _to_promotion(m, m.granular_topics)
        for m in metas
        if is_promotable(
            m,
            min_volume=min_volume,
            reliability_set=reliability_set,
            excluded_bias=excluded_bias,
            denylist=denylist,
        )
    ]


async def load_metas(session) -> list[SourceMeta]:
    sql = text(
        f"""
        SELECT s.id, s.name, s.url, s.theme, s.type, s.is_curated,
               s.bias_stance, s.reliability_score, s.description,
               s.score_independence, s.score_rigor, s.score_ux,
               s.source_tier, s.granular_topics,
               COALESCE(a30.n, 0) AS articles_30d
        FROM sources s
        LEFT JOIN (
            SELECT source_id, COUNT(*) AS n
            FROM contents
            WHERE published_at >= now() - interval '{PROMO_WINDOW_DAYS} days'
            GROUP BY source_id
        ) a30 ON a30.source_id = s.id
        WHERE s.is_active
        """
    )
    result = await session.execute(sql)
    metas: list[SourceMeta] = []
    for r in result.mappings():
        metas.append(
            SourceMeta(
                source_id=str(r["id"]),
                name=r["name"],
                url=r["url"],
                theme=r["theme"],
                type=str(r["type"]),
                is_curated=bool(r["is_curated"]),
                bias_stance=str(r["bias_stance"]),
                reliability_score=str(r["reliability_score"]),
                description=r["description"],
                score_independence=r["score_independence"],
                score_rigor=r["score_rigor"],
                score_ux=r["score_ux"],
                source_tier=r["source_tier"] or "mainstream",
                granular_topics=list(r["granular_topics"])
                if r["granular_topics"]
                else None,
                articles_30d=int(r["articles_30d"]),
            )
        )
    return metas


async def write_promotions(session, promotions: list[Promotion]) -> None:
    """Applique UNIQUEMENT les promotions `is_curated=true` (idempotent).

    Isolé de `write_plan` pour que le job hebdo puisse promouvoir sans toucher
    `granular_topics` (le re-tag reste réservé au run manuel + revue CSV PO)."""
    promote_stmt = text("UPDATE sources SET is_curated = true WHERE id = :id")
    for p in promotions:
        await session.execute(promote_stmt, {"id": UUID(p.source_id)})
