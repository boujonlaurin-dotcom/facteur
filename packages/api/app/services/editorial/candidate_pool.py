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

## Portée exacte — ce module ne couvre PAS tout le clustering

Le filtre s'applique au pool **éditorial**, donc au digest. `build_topic_clusters`
a d'autres appelants qui construisent leur propre pool et gardent le défaut décrit
ci-dessus (un cluster de bulletins lu comme un sujet « trending ») :

- `digest_selector._build_global_trending_context` — requête brute, alimente `is_trending` ;
- `routers/feed.py` — endpoint `/feed/trending` ;
- `article_clustering_service.find_hot_cluster` — carrousel « actu chaude ».

Les traiter revient à pousser l'exclusion dans `ImportanceDetector` lui-même, ce qui
change le comportement de trois surfaces vivantes non mesurées — chantier distinct,
tracé au §6.4 de `docs/maintenance/maintenance-clustering-corpus-complet.md`.
"""

import datetime

import structlog
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content
from app.models.source import Source
from app.services.editorial.config import load_editorial_config
from app.services.recommendation.filter_presets import (
    apply_ad_filter,
    apply_good_news_filter,
    is_news_bulletin_title,
)

logger = structlog.get_logger()

# --- Bornes de sécurité (code, pas configuration) ---------------------------
#
# Ces deux-là ne sont pas des réglages produit : ce sont des garde-fous. Les
# fenêtres, elles, sont dans `editorial_config.yaml` avec les autres réglages du
# pipeline — voir `clustering_window_hours` / `clustering_fallback_hours`.

# Plancher de pool. En dessous, la fenêtre est ré-élargie plutôt que de produire
# un digest maigre. Valeur = l'ancien plafond `LIMIT 200`, qui devient donc son
# exact contraire.
EDITORIAL_CLUSTERING_MIN_POOL = 200

# Borne mémoire : ~2 400 articles/24 h en régime normal, marge ×2,5 avant de
# tronquer. Une troncature signale une anomalie d'ingestion, pas un réglage à
# ajuster — d'où le `logger.warning`.
EDITORIAL_CLUSTERING_MAX_ARTICLES = 6000


def clustering_window_ladder() -> tuple[int, ...]:
    """Fenêtres candidates, de la plus étroite à la plus large.

    On garde la première qui atteint `EDITORIAL_CLUSTERING_MIN_POOL`, sinon la
    dernière. Une échelle plutôt qu'une fenêtre unique parce que les deux modes
    n'ont pas du tout la même densité :

    - `pour_vous` : ~2 000 articles/24 h ⇒ la fenêtre nominale suffit toujours.
      « Actus du jour » est un produit quotidien, et au-delà de 24 h les articles
      de la veille se raccrochent à ceux du jour (observé sur les bulletins radio,
      clusters à cheval sur 3 jours).
    - `serein` : hard-filtré sur `is_good_news`, soit **13 articles/24 h, 33 sur
      48 h, 145 sur 168 h** (mesuré en production). S'arrêter à 48 h amputerait
      « Bonnes Nouvelles » de 77 % de sa matière — l'échelle le fait descendre
      jusqu'à 168 h, ce qui était exactement son comportement historique.

    **La fenêtre appartient au module, pas aux appelants.** Elle a d'abord été
    câblée sur leur `hours_lookback` — mais ce paramètre veut dire « jusqu'où
    remonter pour les candidats personnalisés » et vaut 48 h côté batch, 168 h
    côté on-demand : les deux chemins se seraient élargis différemment dans le
    seul cas où ce module existe pour garantir qu'ils voient le même corpus.
    """
    ladder = tuple(load_editorial_config().pipeline.clustering_window_ladder_hours)
    # Une échelle décroissante ferait « ré-élargir » vers un pool plus petit.
    return tuple(sorted(ladder)) if ladder else (24,)


def clustering_window_hours() -> int:
    """Fenêtre nominale — le premier barreau de l'échelle."""
    return clustering_window_ladder()[0]


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
        now: borne haute, injectable pour les tests. Défaut : maintenant, UTC.

    Returns:
        Les contenus de la fenêtre retenue, déjà passés par `drop_unclusterable` —
        le plancher doit se mesurer sur ce qui ira réellement au clustering, pas
        sur le brut. Les appelants qui unionnent d'autres tranches refiltrent le
        tout via `finalize_pool` (le filtre est idempotent).
    """
    now = now or datetime.datetime.now(datetime.UTC)
    ladder = clustering_window_ladder()

    async def _fetch(hours: int) -> list[Content]:
        stmt = (
            build_editorial_pool_stmt(mode, now - datetime.timedelta(hours=hours), now)
            .order_by(Content.published_at.desc())
            .limit(EDITORIAL_CLUSTERING_MAX_ARTICLES)
        )
        return drop_unclusterable(list((await session.execute(stmt)).scalars().all()))

    # On descend l'échelle jusqu'à atteindre le plancher. Une seule requête dans
    # le cas nominal ; les barreaux suivants ne servent qu'aux modes clairsemés
    # (`serein`) et aux creux d'ingestion. Re-requêter la fenêtre entière plutôt
    # que le seul delta garde la boucle lisible pour un coût qui ne se paie que
    # sur ces cas-là.
    contents: list[Content] = []
    for hours in ladder:
        contents = await _fetch(hours)
        if len(contents) >= EDITORIAL_CLUSTERING_MIN_POOL:
            break
    else:
        logger.info(
            "editorial_pool_ladder_exhausted",
            mode=mode,
            widest_window_hours=ladder[-1],
            pool_size=len(contents),
            floor=EDITORIAL_CLUSTERING_MIN_POOL,
        )

    if len(contents) >= EDITORIAL_CLUSTERING_MAX_ARTICLES:
        # Jamais atteint en régime normal (~2 400 art./24 h) : signale une
        # anomalie d'ingestion plutôt qu'un réglage à ajuster.
        logger.warning(
            "editorial_pool_truncated",
            mode=mode,
            cap=EDITORIAL_CLUSTERING_MAX_ARTICLES,
        )

    return contents


def finalize_pool(contents: list[Content], mode: str, event: str) -> list[Content]:
    """Applique `drop_unclusterable` et loge le pool servi au clustering.

    Dernière étape commune aux deux chemins, après que chacun a unioné ses
    éventuelles tranches supplémentaires. Vit ici pour la même raison que le
    reste : la duplication de cette séquence est ce qui avait laissé les deux
    appelants diverger.
    """
    pool = drop_unclusterable(contents)
    logger.info(
        event,
        mode=mode,
        window_hours=clustering_window_hours(),
        pool_size=len(pool),
        source_count=len({c.source_id for c in pool}),
        dropped_unclusterable=len(contents) - len(pool),
    )
    return pool


def drop_unclusterable(contents: list[Content]) -> list[Content]:
    """Retire les contenus qui ne portent pas de sujet regroupable.

    Aujourd'hui : les bulletins et chroniques régulières (cf. docstring du module).
    Le prédicat est partagé avec `pipeline._is_non_actu_cluster` et l'`actu_matcher`,
    donc un pattern ajouté à `NEWS_BULLETIN_PATTERNS` vaut pour les trois.

    Un titre absent ou non-textuel est conservé : ce filtre écarte ce qu'il
    reconnaît, il n'est pas une garde de validation.
    """

    def _keep(content: Content) -> bool:
        title = getattr(content, "title", None)
        return not isinstance(title, str) or not is_news_bulletin_title(title)

    return [c for c in contents if _keep(c)]
