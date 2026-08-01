"""Politique du pool d'articles soumis au clustering éditorial.

Un seul endroit décide **quels articles le clustering « Actus du jour » a le droit
de voir**. Deux appelants en dépendent et doivent rester alignés :

- `digest_generation_job._get_global_candidates` (chemin batch, 1× par cycle) ;
- `digest_selector._fetch_editorial_global_pool` (chemin on-demand, cache miss).

## Pourquoi ce module existe

La section promet « les sujets les + couverts en France ». Ce décompte n'a de sens
que si le regroupement voit **la couverture réelle du jour**. Or les deux appelants
plafonnaient leur pool à `LIMIT 200` par récence, ce qui — mesuré sur production —
donnait 246 articles, soit **10,5 % du corpus 24 h**, issus de 64 médias sur 192,
sur une fenêtre de **1,7 à 2,9 h en journée**. Un sujet couvert par 18 médias dans
la journée n'en montrait que 2 ou 3, et les deux plus gros sujets du jour
n'atteignaient jamais la section.

Le clustering n'est pas le goulot : **0,45 s pour 2 200 articles**. Le plafond
n'achetait donc pas de la latence, il achetait de la cécité. Il est remplacé ici par
une fenêtre temporelle explicite et une borne de sécurité très au-dessus du volume
réel.

Cf. `docs/bugs/bug-clustering-actus-du-jour-fragmentation.md` (diagnostic) et
`docs/bugs/bug-clustering-actus-du-jour-verification.md` (mesures).

## Ce que le pool exclut, et pourquoi

- **Articles post-datés** (`published_at > now()`). 19 articles portaient une date
  RSS future ; comme le pool est trié par récence décroissante, ils occupaient en
  permanence 19 des 200 places. Le tri les remonte toujours en tête, donc le garde
  reste utile même sans plafond.
- **Bulletins et chroniques régulières** (« JOURNAL DE 8H du jeudi… », « Le journal
  RTL de 6h… »). Ces titres partagent un **gabarit**, pas un sujet : élargir le pool
  les fait se regrouper entre eux et fabriquer de faux « sujets » à 3 médias. Mesuré
  avant ce filtre : un cluster de 20 bulletins / 3 médias, à cheval sur 3 jours,
  comptait comme un sujet du jour.

  `pipeline._is_non_actu_cluster` existait déjà mais exige que **tous** les contenus
  du cluster soient des bulletins — un seul intrus (« Ce soir à la télé : notre
  sélection ») suffisait à sauver le cluster entier. On traite ici la cause : un
  bulletin n'entre pas dans le calcul. Il reste évidemment consultable ailleurs dans
  l'app — c'est un filtre d'entrée du clustering, pas une suppression de contenu.
"""

import datetime

import structlog
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.source import Source

logger = structlog.get_logger()

# Fenêtre de regroupement. « Actus du jour » est un produit quotidien : un sujet se
# définit dans la journée. Une fenêtre plus large laisse des articles de la veille
# se raccrocher à ceux du jour et fabrique des clusters à cheval sur plusieurs
# jours (observé sur les bulletins radio, sur 3 jours).
EDITORIAL_CLUSTERING_WINDOW_HOURS = 24

# Si la fenêtre nominale rend un pool anormalement maigre (nuit de réveillon,
# panne d'ingestion), on ré-élargit à la fenêtre de repli plutôt que de produire un
# digest vide. Valeur = l'ancien plafond, qui devient donc un **plancher**.
EDITORIAL_CLUSTERING_MIN_POOL = 200

# Borne de sécurité mémoire, pas de qualité : ~2 400 articles/24 h en régime
# normal, on garde une marge ×2,5 avant de tronquer. Une troncature ici serait un
# signal d'anomalie d'ingestion — elle est loguée par les appelants.
EDITORIAL_CLUSTERING_MAX_ARTICLES = 6000


def build_editorial_pool_stmt(
    mode: str,
    cutoff: datetime.datetime,
    now: datetime.datetime,
) -> Select:
    """Requête de base du pool de clustering éditorial, filtres métier compris.

    Args:
        mode: ``"serein"`` applique le filtre bonne-nouvelle (qui inclut déjà le
            filtre pub) ; tout autre mode applique le seul filtre pub.
        cutoff: borne basse de publication.
        now: borne haute — écarte les articles post-datés.

    Returns:
        Un ``Select`` sur ``Content`` (source *eager-loaded*), sans tri ni limite :
        c'est à l'appelant de les poser selon sa tranche.
    """
    from sqlalchemy.orm import selectinload

    from app.services.recommendation.filter_presets import (
        apply_ad_filter,
        apply_good_news_filter,
    )

    stmt = select(Content).options(selectinload(Content.source))
    if mode == "serein":
        # Mode « Bonnes nouvelles » : hard-filter is_good_news. `apply_good_news_filter`
        # inclut déjà `apply_ad_filter`, d'où le join explicite sur Source (le filtre
        # référence `Source.theme`).
        stmt = stmt.join(Source, Content.source_id == Source.id)
        stmt = apply_good_news_filter(stmt)
    else:
        # `pour_vous` ne passe pas par le filtre bonne-nouvelle : sans ce filtre
        # explicite, les articles `is_ad=True` entrent dans le clustering.
        stmt = apply_ad_filter(stmt)

    return stmt.where(Content.published_at >= cutoff, Content.published_at <= now)


async def fetch_editorial_pool(
    session: AsyncSession,
    mode: str,
    fallback_hours: int,
    now: datetime.datetime | None = None,
) -> list[Content]:
    """Corpus de la fenêtre de regroupement, ré-élargi si le pool est maigre.

    C'est ici — et pas chez les appelants — que vivent la fenêtre, le
    ré-élargissement et la borne de sécurité : les deux chemins (batch et
    on-demand) doivent voir le même corpus, et dupliquer cette séquence chez
    chacun est précisément ce qui les avait laissés diverger.

    Args:
        session: session async.
        mode: ``"serein"`` ou autre (cf. `build_editorial_pool_stmt`).
        fallback_hours: fenêtre de repli quand le pool nominal est trop maigre.
        now: borne haute, injectable pour les tests. Défaut : maintenant, UTC.

    Returns:
        Les contenus bruts de la fenêtre, **sans** `drop_unclusterable` : les
        appelants qui unionnent d'autres tranches doivent filtrer une seule fois,
        à la fin.
    """
    now = now or datetime.datetime.now(datetime.UTC)

    async def _fetch(hours: int) -> list[Content]:
        stmt = (
            build_editorial_pool_stmt(mode, now - datetime.timedelta(hours=hours), now)
            .order_by(Content.published_at.desc())
            .limit(EDITORIAL_CLUSTERING_MAX_ARTICLES)
        )
        return list((await session.execute(stmt)).scalars().all())

    contents = await _fetch(EDITORIAL_CLUSTERING_WINDOW_HOURS)

    if len(contents) < EDITORIAL_CLUSTERING_MIN_POOL:
        # Nuit creuse / panne d'ingestion : mieux vaut une fenêtre plus large
        # qu'un digest vide.
        widened = await _fetch(fallback_hours)
        logger.info(
            "editorial_pool_widened",
            mode=mode,
            window_hours=EDITORIAL_CLUSTERING_WINDOW_HOURS,
            fallback_hours=fallback_hours,
            before=len(contents),
            after=len(widened),
        )
        contents = widened

    if len(contents) >= EDITORIAL_CLUSTERING_MAX_ARTICLES:
        # Jamais atteint en régime normal (~2 400 art./24 h) : signale une
        # anomalie d'ingestion plutôt qu'un réglage à ajuster.
        logger.warning(
            "editorial_pool_truncated",
            mode=mode,
            cap=EDITORIAL_CLUSTERING_MAX_ARTICLES,
        )

    return contents


def drop_unclusterable(contents: list[Content]) -> list[Content]:
    """Retire les contenus qui ne portent pas de sujet regroupable.

    Aujourd'hui : les bulletins et chroniques régulières (cf. docstring du module).
    Le prédicat est partagé avec `pipeline._is_non_actu_cluster` et l'`actu_matcher`,
    donc un pattern ajouté à `NEWS_BULLETIN_PATTERNS` vaut pour les trois.

    Un titre absent ou non-textuel est conservé : ce filtre écarte ce qu'il
    reconnaît, il n'est pas une garde de validation.
    """
    from app.services.recommendation.filter_presets import is_news_bulletin_title

    def _keep(content: Content) -> bool:
        title = getattr(content, "title", None)
        return not isinstance(title, str) or not is_news_bulletin_title(title)

    return [c for c in contents if _keep(c)]
