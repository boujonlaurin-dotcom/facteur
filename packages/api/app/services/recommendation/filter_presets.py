"""Presets de filtrage partagés entre Feed et Digest.

Centralise la logique de filtrage par mode (Serein, Perspective, Focus)
pour éviter la duplication entre RecommendationService (feed) et
DigestSelector (digest).
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import and_, exists, func, literal_column, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import BiasStance
from app.models.source import Source, UserSource

if TYPE_CHECKING:
    from app.services.briefing.importance_detector import TopicCluster

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


def apply_serein_filter(query, sensitive_themes: list[str] | None = None):
    """Exclut les articles anxiogènes via is_serene (LLM) + fallback mots-clés.

    Stratégie :
    1. is_serene=True  → article passe (classification LLM, plus précis)
    2. is_serene=False → article exclu
    3. is_serene=NULL  → fallback sur filtre mots-clés/thèmes legacy

    Args:
        query: SQLAlchemy query to filter
        sensitive_themes: thèmes sensibles de l'utilisateur (union avec les défauts)

    Utilisé par le mode INSPIRATION (feed) et le toggle serein (digest).
    """
    effective_themes = list(set(SEREIN_EXCLUDED_THEMES) | set(sensitive_themes or []))
    serene_condition = or_(
        Content.is_serene == True,  # noqa: E712 — SQLAlchemy needs == True
        and_(
            Content.is_serene.is_(None),
            _legacy_serein_keyword_filter(excluded_themes=effective_themes),
        ),
    )
    return query.where(serene_condition)


def _legacy_serein_keyword_filter(excluded_themes: list[str] | None = None):
    """Filtre legacy par mots-clés et thèmes (pour articles non taggés par LLM).

    Retourne une condition SQLAlchemy combinant :
    - Exclusion de thèmes anxiogènes (via Source.theme)
    - Exclusion de mots-clés anxiogènes dans titre et description

    Args:
        excluded_themes: liste de thèmes à exclure (défaut: SEREIN_EXCLUDED_THEMES)
    """
    themes = excluded_themes or SEREIN_EXCLUDED_THEMES
    keywords_pattern = "|".join(SEREIN_KEYWORDS)
    theme_ok = Source.theme.notin_(themes)
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


def is_cluster_serein_compatible(
    cluster: TopicCluster, sensitive_themes: list[str] | None = None
) -> bool:
    """Vérifie si un topic cluster est compatible avec le mode Serein.

    Un cluster est EXCLU si :
    - Son thème dominant ∈ thèmes exclus (défauts + sensibles utilisateur), OU
    - >50% de ses articles matchent au moins un SEREIN_KEYWORD dans titre/description

    Args:
        cluster: TopicCluster à évaluer (from importance_detector)
        sensitive_themes: thèmes sensibles de l'utilisateur (union avec les défauts)

    Returns:
        True si le cluster est serein-compatible (peut être inclus)
    """
    effective_themes = list(set(SEREIN_EXCLUDED_THEMES) | set(sensitive_themes or []))
    # Check 1: thème dominant
    if cluster.theme and cluster.theme.lower() in effective_themes:
        return False

    # Check 2: mots-clés anxiogènes dans titre/description
    import re as _re

    pattern = _re.compile("|".join(SEREIN_KEYWORDS), _re.IGNORECASE)
    match_count = 0
    for content in cluster.contents:
        text = (content.title or "") + " " + (content.description or "")
        if pattern.search(text):
            match_count += 1

    return not (len(cluster.contents) > 0 and match_count / len(cluster.contents) > 0.5)


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
