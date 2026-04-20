"""Presets de filtrage partagés entre Feed et Digest.

Centralise la logique de filtrage par mode (Serein, Perspective, Focus)
pour éviter la duplication entre RecommendationService (feed) et
DigestSelector (digest).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import and_, exists, func, literal_column, not_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import BiasStance
from app.models.source import Source, UserSource
from app.models.user import UserPreference
from app.models.user_topic_profile import UserTopicProfile

if TYPE_CHECKING:
    from app.services.briefing.importance_detector import TopicCluster


@dataclass
class ExcludedTopic:
    """Topic exclu du mode serein, pré-résolu pour matching."""

    entity_name: str | None
    keywords: list[str] = field(default_factory=list)


@dataclass
class SereinPreferences:
    """Préférences serein résolues pour un utilisateur."""

    sensitive_themes: list[str]
    excluded_topics: list[ExcludedTopic]
    personalized: bool


async def load_serein_preferences(
    session: AsyncSession, user_id: UUID
) -> SereinPreferences:
    """Charge toutes les préférences serein pour un utilisateur.

    - `sensitive_themes` : list[str] des thèmes masqués. Si `serein_personalized`
      n'est pas posé, les défauts `SEREIN_EXCLUDED_THEMES` sont retournés.
    - `excluded_topics` : topics marqués `excluded_from_serein=True`,
      pré-résolus en ExcludedTopic(entity_name, keywords).
    - `personalized` : True si l'utilisateur a posé `serein_personalized=true`.
    """
    prefs_rows = (
        await session.execute(
            select(UserPreference.preference_key, UserPreference.preference_value).where(
                UserPreference.user_id == user_id,
                UserPreference.preference_key.in_(
                    ("sensitive_themes", "serein_personalized")
                ),
            )
        )
    ).all()
    prefs = dict(prefs_rows)
    personalized = prefs.get("serein_personalized") == "true"

    if personalized:
        raw = prefs.get("sensitive_themes")
        try:
            sensitive_themes: list[str] = json.loads(raw) if raw else []
        except (ValueError, TypeError):
            sensitive_themes = []
    else:
        sensitive_themes = list(SEREIN_EXCLUDED_THEMES)

    topic_rows = (
        await session.execute(
            select(
                UserTopicProfile.canonical_name, UserTopicProfile.keywords
            ).where(
                UserTopicProfile.user_id == user_id,
                UserTopicProfile.excluded_from_serein == True,  # noqa: E712
            )
        )
    ).all()
    excluded_topics = [
        ExcludedTopic(entity_name=canonical, keywords=list(keywords or []))
        for canonical, keywords in topic_rows
    ]

    return SereinPreferences(
        sensitive_themes=sensitive_themes,
        excluded_topics=excluded_topics,
        personalized=personalized,
    )

# --- Constantes Serein ---

SEREIN_EXCLUDED_THEMES = ["society", "international", "economy", "politics"]

SEREIN_KEYWORDS = [
    "politique",
    "guerre",
    "conflit",
    "élections",
    "inflation",
    "grève",
    "drame",
    "fait divers",
    "faits divers",
    "crise",
    "scandale",
    "terrorisme",
    "corruption",
    "procès",
    "violence",
    "catastrophe",
    "manifestation",
    "géopolitique",
    "trump",
    "musk",
    "poutine",
    "macron",
    "netanyahou",
    "zelensky",
    "ukraine",
    "gaza",
    # Extended: catégories manquantes identifiées via faux positifs
    "trafic",
    "esclavage",
    "extrémisme",
    "extrême droite",
    "extrême gauche",
    "radicalisation",
    "fascisme",
    "racisme",
    "discrimination",
    "pandémie",
    "épidémie",
    "effondrement",
    "maltraitance",
    "harcèlement",
    "attentat",
    "meurtre",
    "agression",
    "féminicide",
    "pédocriminalité",
]


def apply_serein_filter(
    query,
    sensitive_themes: list[str] | None = None,
    excluded_topics: list[ExcludedTopic] | None = None,
):
    """Exclut les articles anxiogènes via is_serene (LLM) + fallback mots-clés,
    puis retire tout contenu matchant un topic exclu (granularité par sujet).

    Stratégie :
    1. is_serene=True  → article passe (classification LLM, plus précis)
    2. is_serene=False → article exclu
    3. is_serene=NULL  → fallback sur filtre mots-clés/thèmes legacy
    4. Pour TOUS les chemins, exclusion supplémentaire des contenus matchant
       les topics `excluded_topics` (entity_name ou keywords).
    5. Si l'utilisateur a personnalisé (`sensitive_themes is not None`), ses
       thèmes exclus sont appliqués au niveau TOP-LEVEL — un choix explicite
       l'emporte sur `is_serene=True`. En mode défaut (None), on conserve le
       comportement legacy (LLM autorité).

    Args:
        query: SQLAlchemy query to filter
        sensitive_themes: thèmes sensibles à exclure.
            - None : pas de personnalisation, applique les défauts.
            - [] : personnalisé à vide, aucune exclusion thématique (seul
              le path `is_serene` filtre).
            - [...] : utilise la liste verbatim.
        excluded_topics: topics individuels à exclure (pré-résolus).

    Utilisé par le mode INSPIRATION (feed) et le toggle serein (digest).
    """
    effective_themes = (
        list(SEREIN_EXCLUDED_THEMES) if sensitive_themes is None else sensitive_themes
    )
    serene_condition = or_(
        Content.is_serene == True,  # noqa: E712 — SQLAlchemy needs == True
        and_(
            Content.is_serene.is_(None),
            _legacy_serein_keyword_filter(excluded_themes=effective_themes),
        ),
    )
    query = query.where(serene_condition)

    # User-personalized theme exclusions override LLM is_serene=True: if the
    # user explicitly said "no tech", hide every tech article regardless of
    # classification. The default-themes case keeps the LLM allowance.
    if sensitive_themes is not None and effective_themes:
        query = query.where(Source.theme.notin_(effective_themes))

    if excluded_topics:
        topic_exclusion = _topic_exclusion_condition(excluded_topics)
        if topic_exclusion is not None:
            query = query.where(topic_exclusion)
    return query


def _topic_exclusion_condition(excluded_topics: list[ExcludedTopic]):
    """Construit une clause NOT(match any excluded topic).

    Pour chaque topic exclu :
    - Si `entity_name` : exclut les contenus dont `entities` contient ce nom.
    - Sinon (ou en complément) : exclut les contenus dont titre/description
      match un des keywords (regex OR).

    Retourne None si aucun topic n'a de critère exploitable.
    """
    clauses = []
    for topic in excluded_topics:
        topic_clauses = []
        if topic.entity_name:
            entity_element = func.unnest(Content.entities).column_valued()
            pattern = f'%"name": "{topic.entity_name}"%'
            topic_clauses.append(
                exists(select(literal_column("1")).where(entity_element.ilike(pattern)))
            )
        if topic.keywords:
            kw_pattern = "|".join(re.escape(k) for k in topic.keywords)
            topic_clauses.append(
                or_(
                    Content.title.op("~*")(kw_pattern),
                    and_(
                        Content.description.isnot(None),
                        Content.description.op("~*")(kw_pattern),
                    ),
                )
            )
        if topic_clauses:
            clauses.append(or_(*topic_clauses))
    if not clauses:
        return None
    return not_(or_(*clauses))


def _legacy_serein_keyword_filter(excluded_themes: list[str] | None = None):
    """Filtre legacy par mots-clés et thèmes (pour articles non taggés par LLM).

    Retourne une condition SQLAlchemy combinant :
    - Exclusion de thèmes anxiogènes (via Source.theme)
    - Exclusion de mots-clés anxiogènes dans titre et description

    Args:
        excluded_themes: liste de thèmes à exclure.
            - None : applique les défauts (SEREIN_EXCLUDED_THEMES).
            - [] : personnalisé à vide, aucune exclusion thématique.
            - [...] : utilise la liste verbatim.
    """
    themes = (
        list(SEREIN_EXCLUDED_THEMES) if excluded_themes is None else excluded_themes
    )
    keywords_pattern = "|".join(SEREIN_KEYWORDS)
    theme_ok = Source.theme.notin_(themes) if themes else literal_column("TRUE")
    # Handle NULL title/description: NULL ~* 'pattern' → NULL → NOT NULL → NULL
    # which silently excludes rows. Use OR IS NULL to keep them.
    title_ok = or_(Content.title.is_(None), ~Content.title.op("~*")(keywords_pattern))
    desc_ok = or_(
        Content.description.is_(None),
        ~Content.description.op("~*")(keywords_pattern),
    )
    return and_(theme_ok, title_ok, desc_ok)


def apply_theme_focus_filter(query, theme_slug: str):
    """Filtre hybride pour un thème spécifique.

    Optimisé : résout le matching source-level via subquery sur la petite
    table sources (~100 rows), puis utilise deux chemins indexés sur contents
    via BitmapOr :
      1. Content.source_id IN (source IDs matchant le thème) → ix_contents_source_id
      2. Content.theme = theme_slug → ix_contents_theme_published

    Utilisé par le mode THEME_FOCUS (digest) et le filtre thème (feed).
    """
    # Subquery : source IDs dont le thème principal ou secondaire matche
    theme_source_ids_subq = select(Source.id).where(
        or_(
            Source.theme == theme_slug,
            Source.secondary_themes.any(theme_slug),
        )
    )
    # Deux chemins indexés sur la même table (contents) :
    # 1. Articles classifiés ML dans ce thème → toujours inclus
    # 2. Articles de sources matchant le thème MAIS pas encore classifiés
    #    (Content.theme IS NULL) → bénéfice du doute
    # Exclut: articles de sources matchantes mais classifiés dans un AUTRE thème
    return query.where(
        or_(
            Content.theme == theme_slug,
            and_(
                Content.source_id.in_(theme_source_ids_subq),
                Content.theme.is_(None),
            ),
        )
    )


def apply_topic_filter(query, topic_slug: str):
    """Filtre les contenus par topic ML granulaire (e.g. 'ai', 'startups').

    Utilise Content.topics (ARRAY) avec l'index GIN ix_contents_topics.
    """
    return query.where(Content.topics.any(topic_slug))


def apply_entity_filter(query, entity_name: str):
    """Filter content whose entities array contains a JSON string matching the entity name.

    Content.entities is ARRAY(Text) with GIN index ix_contents_entities.
    Each element is a JSON string like '{"name": "Macron", "type": "PERSON"}'.
    Uses unnest + LIKE for safe parameterized matching.
    """
    entity_element = func.unnest(Content.entities).column_valued()
    pattern = f'%"name": "{entity_name}"%'
    return query.where(
        exists(select(literal_column("1")).where(entity_element.ilike(pattern)))
    )


def apply_keyword_filter(query, keyword: str):
    """Filter content whose title contains the keyword (case-insensitive)."""
    return query.where(Content.title.ilike(f"%{keyword}%"))


def get_opposing_biases(user_stance: BiasStance) -> list[BiasStance]:
    """Retourne la liste des biais à montrer pour un changement de perspective.

    Logique :
    - Gauche → montrer Droite
    - Droite → montrer Gauche
    - Centre → montrer les extrêmes et alternatifs
    """
    if user_stance == BiasStance.LEFT:
        return [BiasStance.RIGHT, BiasStance.CENTER_RIGHT]
    elif user_stance == BiasStance.RIGHT:
        return [BiasStance.LEFT, BiasStance.CENTER_LEFT]
    else:
        return [
            BiasStance.ALTERNATIVE,
            BiasStance.SPECIALIZED,
            BiasStance.LEFT,
            BiasStance.RIGHT,
        ]


# --- Constantes "low-priority" (faits divers + sport) ---
#
# Utilisé pour déprioritiser ces catégories dans le digest (les deux modes —
# pour_vous ET serein). Contrairement à SEREIN_KEYWORDS, ces patterns ne
# servent PAS à exclure les articles : ils servent à limiter le nombre de
# sujets de chaque catégorie dans le digest (cap à 1 sport + 1 faits divers).

LOW_PRIORITY_FAITS_DIVERS_KEYWORDS = [
    "fait divers",
    "faits divers",
    "fait-divers",
    "faits-divers",
    "accident",
    "incendie",
    "noyade",
    "collision",
    "braquage",
    "cambriolage",
]

LOW_PRIORITY_SPORT_KEYWORDS = [
    "football",
    "rugby",
    "tennis",
    "basket",
    "handball",
    "ligue 1",
    "ligue 2",
    "champions league",
    "ligue des champions",
    "europa league",
    "coupe du monde",
    "coupe de france",
    "roland-garros",
    "roland garros",
    "wimbledon",
    "tour de france",
    "formule 1",
    " f1 ",
    "moto gp",
    "motogp",
    "jeux olympiques",
    "psg",
    " om ",
    " ol ",
    " asse ",
    " asm ",
    "mbappé",
    "mbappe",
]

LOW_PRIORITY_SPORT_THEMES = {"sport", "sports"}


def _match_ratio(cluster: TopicCluster, keywords: list[str]) -> float:
    """Retourne la part d'articles du cluster matchant au moins un keyword."""
    if not cluster.contents:
        return 0.0
    import re as _re

    pattern = _re.compile("|".join(_re.escape(k) for k in keywords), _re.IGNORECASE)

    def _s(v: object) -> str:
        # Defensive: Content fields are Optional[str], but MagicMocks in tests
        # (and SQLAlchemy sentinel values) can slip in. Only use real strings.
        return v if isinstance(v, str) else ""

    match_count = 0
    for content in cluster.contents:
        text = (
            _s(getattr(content, "title", None))
            + " "
            + _s(getattr(content, "description", None))
        )
        if pattern.search(text):
            match_count += 1
    return match_count / len(cluster.contents)


def is_sport_cluster(cluster: TopicCluster) -> bool:
    """Cluster dominé par le sport (thème OU >50% titres matchent)."""
    if cluster.theme and cluster.theme.lower() in LOW_PRIORITY_SPORT_THEMES:
        return True
    return _match_ratio(cluster, LOW_PRIORITY_SPORT_KEYWORDS) > 0.5


def is_faits_divers_cluster(cluster: TopicCluster) -> bool:
    """Cluster dominé par les faits divers (>50% titres matchent)."""
    return _match_ratio(cluster, LOW_PRIORITY_FAITS_DIVERS_KEYWORDS) > 0.5


def cap_low_priority_clusters(
    clusters: list[TopicCluster],
    max_sport: int = 1,
    max_faits_divers: int = 1,
) -> list[TopicCluster]:
    """Limite le nombre de clusters sport + faits divers.

    Conserve l'ordre d'entrée (supposé trié par pertinence/taille) et ne
    garde que les `max_sport` premiers sport + `max_faits_divers` premiers
    faits divers. Les autres sont filtrés. Les clusters non low-priority
    passent tous.

    Utilisé AVANT la sélection LLM pour éviter que 3 matchs de foot + 2
    faits divers saturent le digest.
    """
    kept: list[TopicCluster] = []
    sport_count = 0
    fd_count = 0
    for c in clusters:
        if is_sport_cluster(c):
            if sport_count >= max_sport:
                continue
            sport_count += 1
        elif is_faits_divers_cluster(c):
            if fd_count >= max_faits_divers:
                continue
            fd_count += 1
        kept.append(c)
    return kept


def is_cluster_serein_compatible(
    cluster: TopicCluster,
    sensitive_themes: list[str] | None = None,
    excluded_topics: list[ExcludedTopic] | None = None,
) -> bool:
    """Vérifie si un topic cluster est compatible avec le mode Serein.

    Un cluster est EXCLU si :
    - Son thème dominant ∈ thèmes exclus utilisateur (ou défauts si non-personnalisé), OU
    - >50% de ses articles matchent au moins un SEREIN_KEYWORD global, OU
    - Au moins un de ses articles match un topic exclu (entity ou keyword).

    Args:
        cluster: TopicCluster à évaluer (from importance_detector)
        sensitive_themes: thèmes à exclure.
            - None : pas de personnalisation, applique les défauts.
            - [] : personnalisé à vide, aucune exclusion thématique.
            - [...] : utilise la liste verbatim.
        excluded_topics: topics individuels à exclure.

    Returns:
        True si le cluster est serein-compatible (peut être inclus)
    """
    effective_themes = (
        list(SEREIN_EXCLUDED_THEMES) if sensitive_themes is None else sensitive_themes
    )
    # Check 1: thème dominant
    if cluster.theme and cluster.theme.lower() in effective_themes:
        return False

    # Check 2: mots-clés anxiogènes dans titre/description
    pattern = re.compile("|".join(SEREIN_KEYWORDS), re.IGNORECASE)
    match_count = 0
    for content in cluster.contents:
        text = (content.title or "") + " " + (content.description or "")
        if pattern.search(text):
            match_count += 1

    if len(cluster.contents) > 0 and match_count / len(cluster.contents) > 0.5:
        return False

    # Check 3: topic-level exclusions (any article matches → exclude cluster)
    if excluded_topics:
        for topic in excluded_topics:
            topic_patterns: list[re.Pattern] = []
            if topic.keywords:
                topic_patterns.append(
                    re.compile(
                        "|".join(re.escape(k) for k in topic.keywords), re.IGNORECASE
                    )
                )
            for content in cluster.contents:
                text = (content.title or "") + " " + (content.description or "")
                if topic.entity_name and topic.entity_name.lower() in text.lower():
                    return False
                if any(p.search(text) for p in topic_patterns):
                    return False

    return True


async def calculate_user_bias(session: AsyncSession, user_id: UUID) -> BiasStance:
    """Détermine le biais dominant de l'utilisateur via ses sources suivies.

    Heuristique : score -1 pour gauche, +1 pour droite, retourne la tendance.
    Fallback CENTER si aucune source suivie.
    """
    result = await session.execute(
        select(Source.bias_stance).join(UserSource).where(UserSource.user_id == user_id)
    )
    biases = result.scalars().all()

    if not biases:
        return BiasStance.CENTER

    score = 0
    for b in biases:
        if b in [BiasStance.LEFT, BiasStance.CENTER_LEFT]:
            score -= 1
        elif b in [BiasStance.RIGHT, BiasStance.CENTER_RIGHT]:
            score += 1

    if score < 0:
        return BiasStance.LEFT
    elif score > 0:
        return BiasStance.RIGHT
    else:
        return BiasStance.CENTER
