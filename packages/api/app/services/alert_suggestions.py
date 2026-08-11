"""Suggestions de cibles d'alerte, fondées sur l'usage réel (story 30.6).

Le reproche PO : « on n'a aucune proposition d'ajout de sources ni de thème
(alors qu'on a bien des stats sur ce qui est le + utilisé) ». Les signaux
existaient, personne ne les lisait pour cet usage.

**Aucun nouveau scoring n'est fabriqué ici.** Le classement est un *ordre de
preuve* en quatre rangs : la consommation réelle (un article ouvert) passe
toujours devant le déclaratif (une case cochée). À l'intérieur d'un rang, on
trie par la valeur brute du signal, puis par nom — deux appels successifs
rendent la même liste.

| rang | signal                                              | cible  |
|------|-----------------------------------------------------|--------|
| 1    | `consumed` >= 3 sur 30 j                            | source |
| 2    | `user_entity_affinity.affinity > 1.0`               | sujet  |
| 3    | `consumed` in (1, 2) sur 30 j                       | source |
| 4    | `composite_score > 0` ou `priority_multiplier > 1`  | sujet  |

Une source suivie mais **jamais ouverte** n'entre dans aucun rang : elle est
exclue, pas classée dernière. Une suggestion sans raison vraie apprend à
l'utilisateur à ignorer le bloc.

La cadence vient de `alert_cadence.py` — le module qui gouverne déjà les envois
et qui est le miroir exact du mobile. Aucun second calcul de fréquence.
"""

import re
import unicodedata
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.constants import CANONICAL_THEME_SLUGS
from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.learning import UserEntityAffinity
from app.models.source import Source, UserSource
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.schemas.alert import AlertSuggestion, AlertSuggestionsResponse
from app.services.alert_cadence import (
    ALERT_CAP,
    FREQUENCY_WINDOW_DAYS,
    cadence_per_week,
    cadence_phrase,
    is_noisy,
)
from app.services.source_alert_producer import (
    FOLLOWED_SOURCE_STATES,
    count_active_alerts,
)
from app.services.topic_alert_producer import (
    FOLLOWED_TOPIC_STATES,
    build_topic_predicate,
    topic_frequency_stats,
)

logger = structlog.get_logger()

#: Nombre maximum de suggestions rendues. Trois à cinq : au-delà, le bloc
#: redevient un inventaire, ce que le PO reproche déjà à cette zone.
MAX_SUGGESTIONS = 5

#: Fenêtre de mesure de la consommation, alignée sur celle de la cadence pour
#: que la raison (« ce mois-ci ») et le devis parlent de la même période.
READ_WINDOW_DAYS = FREQUENCY_WINDOW_DAYS

#: Seuil du rang 1 : au-dessous, une ouverture ou deux ne font pas une habitude.
STRONG_READ_COUNT = 3
#: Nombre d'articles vus à partir duquel la raison peut afficher un ratio
#: (« N sur M ») sans être ridicule.
MIN_SEEN_FOR_RATIO = 4
#: Affinité entité : 1.0 est le neutre, au-dessus l'entité est lue plus souvent.
MIN_AFFINITY = 1.0
#: Deux interactions au minimum : une seule lecture est du bruit statistique.
MIN_AFFINITY_INTERACTIONS = 2

#: `limit` explicites — cet endpoint est appelé à chaque ouverture de l'écran.
SOURCE_CANDIDATE_LIMIT = 300
TOPIC_CANDIDATE_LIMIT = 300
AFFINITY_LIMIT = 500

#: Budget dur de requêtes de cadence sujet. Un sujet n'a pas de `source_id` à
#: grouper (cf. lot B) : sa cadence coûte une requête. On ne la paie donc que
#: pour les cibles qui vont réellement sortir, et jamais plus de 8 fois — la
#: marge au-dessus de MAX_SUGGESTIONS absorbe les sujets écartés en route
#: (prédicat vide, zéro article sur 30 j).
TOPIC_CADENCE_QUERY_BUDGET = 8

#: Identifiants de rang, renvoyés au client pour que l'analytique sache **quel
#: rang** convertit, donc quoi couper.
SIGNAL_SOURCE_READ = "source_read"
SIGNAL_TOPIC_AFFINITY = "topic_affinity"
SIGNAL_SOURCE_READ_LIGHT = "source_read_light"
SIGNAL_TOPIC_WEIGHT = "topic_weight"

#: L'ordre de preuve lui-même : consommation réelle d'abord, déclaratif ensuite.
#: Le rang se déduit de la position, pour qu'insérer un signal n'oblige pas à
#: renuméroter la moitié du module.
_SIGNAL_ORDER = (
    SIGNAL_SOURCE_READ,
    SIGNAL_TOPIC_AFFINITY,
    SIGNAL_SOURCE_READ_LIGHT,
    SIGNAL_TOPIC_WEIGHT,
)
_RANK = {signal: rank for rank, signal in enumerate(_SIGNAL_ORDER)}


def _normalize(value: str | None) -> str:
    """Minuscule, sans accents, sans ponctuation de bord.

    Sert à comparer un nom de sujet saisi à la main (« Politique », « sport »)
    aux slugs de thème, et à comparer une entité canonique à `entity_canonical`
    (stocké lower-strip par `content_service`).
    """
    if not value:
        return ""
    folded = unicodedata.normalize("NFKD", value.strip().lower())
    folded = "".join(c for c in folded if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", "-", folded).strip("-")


#: Les 9 macro-thèmes, slugs **et** libellés FR. La story 30.3 a écarté le thème
#: parent comme axe d'alerte : « politique » ou « sport » ramènerait des
#: centaines d'articles par jour et transformerait la cloche en robinet. Un
#: sujet personnalisé qui porte simplement le nom d'un macro-thème retombe dans
#: le même piège, donc il n'est jamais proposé.
_PARENT_THEME_NAMES: frozenset[str] = frozenset(
    CANONICAL_THEME_SLUGS
    + [
        "technologie",
        "technologies",
        "sciences",
        "societe",
        "politique",
        "economie",
        "environnement",
        "ecologie",
        "culture",
        "international",
        "geopolitique",
        "monde",
        "sports",
        "actualite",
        "actualites",
    ]
)


@dataclass(frozen=True)
class _Candidate:
    """Une cible retenue avant résolution de sa cadence."""

    kind: str
    target_id: UUID
    name: str
    logo_url: str | None
    signal: str
    #: Valeur brute du signal, pour le tri à l'intérieur du rang.
    strength: float
    reason: str
    #: Renseignés d'emblée pour une source (stats déjà agrégées), résolus après
    #: le classement pour un sujet (une requête par cible).
    articles_30d: int = 0
    oldest_content_at: datetime | None = None
    profile: UserTopicProfile | None = None

    @property
    def sort_key(self) -> tuple[int, float, str]:
        return (_RANK[self.signal], -self.strength, self.name.lower())


def _source_reason(read_count: int, seen_count: int) -> str:
    """Ce que le signal prouve, et rien de plus.

    Le ratio n'apparaît qu'à partir de `MIN_SEEN_FOR_RATIO` articles vus :
    « 1 sur 1 » ne dit rien, « 8 sur 10 » dit tout.
    """
    if seen_count >= MIN_SEEN_FOR_RATIO and seen_count > read_count:
        return (
            f"Tu as ouvert {read_count} articles sur {seen_count} "
            "de cette source ce mois-ci."
        )
    if read_count <= 1:
        return "Tu as ouvert 1 article de cette source ce mois-ci."
    return f"Tu as ouvert {read_count} articles de cette source ce mois-ci."


async def _source_candidates(
    db: AsyncSession,
    uid: UUID,
    now: datetime,
    *,
    muted_sources: set[UUID],
    muted_themes: set[str],
    dismissed: set[UUID],
) -> list[_Candidate]:
    """Sources suivies éligibles pour une nouvelle cloche.

    Trois requêtes constantes, quel que soit le nombre de sources suivies :
    les lignes suivies, les stats de publication, les lectures. Aucune boucle.
    """
    rows = (
        await db.execute(
            select(Source, UserSource.notify)
            .join(UserSource, UserSource.source_id == Source.id)
            .where(
                UserSource.user_id == uid,
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
            )
            .order_by(Source.name)
            .limit(SOURCE_CANDIDATE_LIMIT)
        )
    ).all()
    if not rows:
        return []

    eligible = [
        source
        for source, notify in rows
        if notify is not True
        and source.is_active is not False
        and source.id not in muted_sources
        and _normalize(source.theme) not in muted_themes
        and source.id not in dismissed
    ]
    if not eligible:
        return []

    ids = [s.id for s in eligible]
    window_start = now - timedelta(days=READ_WINDOW_DAYS)

    # Volume 30 j + plus ancienne parution : entrées de `cadence_per_week`, et
    # détection de la source morte (`articles_30d == 0`).
    #
    # ⚠️ Forme **strictement identique** à celle de l'inventaire
    # (`_source_items`, `routers/alerts.py`) : le `count` est filtré sur la
    # fenêtre, le `min` ne l'est **pas**. C'est structurant, pas cosmétique —
    # `_per_day` clampe la fenêtre sur l'âge de la cible, donc un `min` restreint
    # à 30 j ferait passer une source ancienne à 2 parutions récentes pour une
    # source qui publie 5 fois par semaine. On annoncerait « bruyante, mode
    # filtré » dans la suggestion et « une fois par mois » sur sa fiche, pour la
    # même source le même jour.
    stats_rows = (
        await db.execute(
            select(
                Content.source_id,
                func.count()
                .filter(Content.published_at >= window_start)
                .label("articles_30d"),
                func.min(Content.published_at).label("oldest_at"),
            )
            .where(Content.source_id.in_(ids))
            .group_by(Content.source_id)
            .limit(SOURCE_CANDIDATE_LIMIT)
        )
    ).all()
    stats = {r.source_id: (r.articles_30d, r.oldest_at) for r in stats_rows}

    # Consommation réelle : `consumed` seul compte comme « ouvert ». `seen`
    # signifie « passé dans le flux », il sert de dénominateur au ratio, jamais
    # de preuve de lecture. Même convention que `_unread_clause` du lot B.
    read_rows = (
        await db.execute(
            select(
                Content.source_id,
                func.count()
                .filter(UserContentStatus.status == ContentStatus.CONSUMED)
                .label("read_count"),
                func.count().label("seen_count"),
            )
            .join(UserContentStatus, UserContentStatus.content_id == Content.id)
            .where(
                UserContentStatus.user_id == uid,
                Content.source_id.in_(ids),
                Content.published_at >= window_start,
                Content.published_at <= now,
            )
            .group_by(Content.source_id)
            .limit(SOURCE_CANDIDATE_LIMIT)
        )
    ).all()
    reads = {r.source_id: (r.read_count, r.seen_count) for r in read_rows}

    candidates: list[_Candidate] = []
    for source in eligible:
        articles_30d, oldest_at = stats.get(source.id, (0, None))
        # Source morte : il en existe dans le catalogue. Une cloche posée
        # dessus ne sonnera jamais, et l'utilisateur en conclura que la
        # fonctionnalité est cassée.
        if articles_30d <= 0:
            continue
        read_count, seen_count = reads.get(source.id, (0, 0))
        # Suivie mais jamais ouverte : pas de rang, pas de suggestion.
        if read_count <= 0:
            continue
        signal = (
            SIGNAL_SOURCE_READ
            if read_count >= STRONG_READ_COUNT
            else SIGNAL_SOURCE_READ_LIGHT
        )
        candidates.append(
            _Candidate(
                kind="source",
                target_id=source.id,
                name=source.name,
                logo_url=source.logo_url,
                signal=signal,
                strength=float(read_count),
                reason=_source_reason(read_count, seen_count),
                articles_30d=articles_30d,
                oldest_content_at=oldest_at,
            )
        )
    return candidates


async def _topic_candidates(
    db: AsyncSession,
    uid: UUID,
    *,
    muted_themes: set[str],
    muted_topics: set[str],
    dismissed: set[UUID],
) -> list[_Candidate]:
    """Sujets suivis éligibles pour une nouvelle cloche.

    Deux requêtes constantes : les profils, les affinités. La cadence n'est
    **pas** résolue ici (une requête par sujet) : elle attend le classement.
    """
    profiles = (
        (
            await db.execute(
                select(UserTopicProfile)
                .where(
                    UserTopicProfile.user_id == uid,
                    UserTopicProfile.state.in_(FOLLOWED_TOPIC_STATES),
                )
                .order_by(UserTopicProfile.topic_name)
                .limit(TOPIC_CANDIDATE_LIMIT)
            )
        )
        .scalars()
        .all()
    )
    if not profiles:
        return []

    eligible = [
        p
        for p in profiles
        if p.notify is not True
        and _normalize(p.topic_name) not in _PARENT_THEME_NAMES
        and _normalize(p.canonical_name) not in _PARENT_THEME_NAMES
        and _normalize(p.slug_parent) not in muted_themes
        and _normalize(p.topic_name) not in muted_topics
        and _normalize(p.canonical_name) not in muted_topics
        and p.id not in dismissed
        # Une cloche sans prédicat ne peut pas sonner : ne pas la proposer.
        and build_topic_predicate(p) is not None
    ]
    if not eligible:
        return []

    affinity_rows = (
        await db.execute(
            select(
                UserEntityAffinity.entity_canonical,
                UserEntityAffinity.affinity,
            )
            .where(
                UserEntityAffinity.user_id == uid,
                UserEntityAffinity.affinity > MIN_AFFINITY,
                UserEntityAffinity.interaction_count >= MIN_AFFINITY_INTERACTIONS,
            )
            .order_by(UserEntityAffinity.affinity.desc())
            .limit(AFFINITY_LIMIT)
        )
    ).all()
    # `entity_canonical` est stocké lower-strip par `content_service` ; on
    # normalise des deux côtés pour que « Ligue 1 » retrouve « ligue 1 ».
    affinities = {_normalize(r[0]): float(r[1]) for r in affinity_rows}

    candidates: list[_Candidate] = []
    for profile in eligible:
        affinity = affinities.get(_normalize(profile.canonical_name)) or affinities.get(
            _normalize(profile.topic_name)
        )
        if affinity is not None:
            candidates.append(
                _Candidate(
                    kind="topic",
                    target_id=profile.id,
                    name=profile.topic_name,
                    logo_url=None,
                    signal=SIGNAL_TOPIC_AFFINITY,
                    strength=affinity,
                    reason="Tu ouvres régulièrement les articles sur ce sujet.",
                    profile=profile,
                )
            )
            continue
        weight = max(profile.composite_score or 0.0, 0.0)
        multiplier = profile.priority_multiplier or 1.0
        if weight <= 0 and multiplier <= 1.0:
            # Suivi, mais aucun poids et aucune lecture : rien à dire d'honnête.
            continue
        candidates.append(
            _Candidate(
                kind="topic",
                target_id=profile.id,
                name=profile.topic_name,
                logo_url=None,
                signal=SIGNAL_TOPIC_WEIGHT,
                strength=weight if weight > 0 else multiplier,
                reason="Tu as mis ce sujet en avant dans tes centres d'intérêt.",
                profile=profile,
            )
        )
    return _deduplicate_by_name(candidates)


def _deduplicate_by_name(candidates: list[_Candidate]) -> list[_Candidate]:
    """Un même nom ne sort qu'une fois, le mieux classé gagnant.

    Constaté sur des données réelles : un compte peut porter **deux** profils
    de sujet homonymes (deux lignes « NBA »). Sans ce filtre, l'écran
    proposerait deux fois la même cible, ce qui se lit comme un bug.
    """
    best: dict[str, _Candidate] = {}
    for candidate in sorted(candidates, key=lambda c: c.sort_key):
        best.setdefault(_normalize(candidate.name), candidate)
    return list(best.values())


def _to_suggestion(
    candidate: _Candidate, articles_30d: int, oldest_at: datetime | None, now: datetime
) -> AlertSuggestion:
    per_week = cadence_per_week(articles_30d, oldest_at, now)
    noisy = is_noisy(articles_30d, oldest_at, now)
    return AlertSuggestion(
        kind=candidate.kind,
        target_id=candidate.target_id,
        target_name=candidate.name,
        target_logo_url=candidate.logo_url,
        reason=candidate.reason,
        signal=candidate.signal,
        articles_30d=articles_30d,
        cadence_per_week=per_week,
        cadence_phrase=cadence_phrase(articles_30d, oldest_at, now),
        noisy=noisy,
        # Règle 30.3 : une cible bruyante n'est jamais proposée « nue ». Le mode
        # filtré arrive pré-coché, sinon la cloche devient un robinet.
        prefill_filtered=noisy,
    )


async def build_alert_suggestions(
    db: AsyncSession, uid: UUID, now: datetime | None = None
) -> AlertSuggestionsResponse:
    """Jusqu'à `MAX_SUGGESTIONS` cibles à mettre sous cloche, raisons comprises."""
    now = now or datetime.now(UTC)

    # Le plafond se tranche **en premier**, et avec le compteur canonique
    # (`count_active_alerts`, celui qui rend le 409 sur `PUT .../alert`). Deux
    # raisons : au plafond on n'interroge aucun signal (1 requête au lieu de 6),
    # et surtout `active_count` ne peut pas diverger de celui que le reste de
    # l'app affiche — le dériver ici des lignes chargées aurait introduit une
    # quatrième définition de « combien de cloches actives », bornée qui plus
    # est par les `limit` de chargement.
    active_count = await count_active_alerts(db, user_id=uid)
    if active_count >= ALERT_CAP:
        return AlertSuggestionsResponse(
            cap=ALERT_CAP, active_count=active_count, at_cap=True, suggestions=[]
        )

    perso = await db.get(UserPersonalization, uid)
    muted_sources = set(perso.muted_sources or []) if perso else set()
    muted_themes = (
        {_normalize(t) for t in (perso.muted_themes or [])} if perso else set()
    )
    muted_topics = (
        {_normalize(t) for t in (perso.muted_topics or [])} if perso else set()
    )
    dismissed_sources = set(perso.dismissed_alert_sources or []) if perso else set()
    dismissed_topics = set(perso.dismissed_alert_topics or []) if perso else set()

    source_candidates = await _source_candidates(
        db,
        uid,
        now,
        muted_sources=muted_sources,
        muted_themes=muted_themes,
        dismissed=dismissed_sources,
    )
    topic_candidates = await _topic_candidates(
        db,
        uid,
        muted_themes=muted_themes,
        muted_topics=muted_topics,
        dismissed=dismissed_topics,
    )

    ranked = sorted(source_candidates + topic_candidates, key=lambda c: c.sort_key)

    suggestions: list[AlertSuggestion] = []
    cadence_queries = 0
    for candidate in ranked:
        if len(suggestions) >= MAX_SUGGESTIONS:
            break
        if candidate.kind == "source":
            suggestions.append(
                _to_suggestion(
                    candidate,
                    candidate.articles_30d,
                    candidate.oldest_content_at,
                    now,
                )
            )
            continue
        # Sujet : la cadence coûte une requête, on ne la paie qu'ici, et pas
        # plus de TOPIC_CADENCE_QUERY_BUDGET fois.
        if cadence_queries >= TOPIC_CADENCE_QUERY_BUDGET:
            # Le budget épuisé laisse des sources moins bien classées prendre
            # la place de sujets mieux classés : c'est un trou dans l'ordre de
            # preuve, pas une simple troncature. Invisible de l'extérieur, donc
            # journalisé — sinon la dégradation commencera à mordre le jour où
            # les sujets deviendront proposables, sans que personne le voie.
            logger.info(
                "alert_suggestions_topic_budget_exhausted",
                user_id=str(uid),
                budget=TOPIC_CADENCE_QUERY_BUDGET,
                suggestions_so_far=len(suggestions),
            )
            continue
        cadence_queries += 1
        articles_30d, oldest_at = await topic_frequency_stats(
            db, profile=candidate.profile, now=now
        )
        # Sujet mort : même raisonnement que la source morte.
        if articles_30d <= 0:
            continue
        suggestions.append(_to_suggestion(candidate, articles_30d, oldest_at, now))

    return AlertSuggestionsResponse(
        cap=ALERT_CAP,
        active_count=active_count,
        at_cap=False,
        suggestions=suggestions,
    )


async def dismiss_alert_suggestion(
    db: AsyncSession, uid: UUID, *, kind: str, target_id: UUID
) -> None:
    """Mémorise un refus. Idempotent : un second appel ne duplique rien.

    Persisté sur `user_personalization`, qui porte déjà les mutes : une table
    neuve pour deux listes d'IDs serait du poids de schéma pour rien.
    """
    column = "dismissed_alert_topics" if kind == "topic" else "dismissed_alert_sources"
    perso = await db.get(UserPersonalization, uid)
    if perso is None:
        perso = UserPersonalization(user_id=uid, **{column: [target_id]})
        db.add(perso)
        await db.commit()
        return
    current = list(getattr(perso, column) or [])
    if target_id in current:
        return
    # Réassignation (pas `.append`) : SQLAlchemy ne détecte pas la mutation
    # in-place d'une colonne ARRAY sans `MutableList`.
    setattr(perso, column, current + [target_id])
    await db.commit()
