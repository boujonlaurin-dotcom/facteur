"""Presets de filtrage partagés entre Feed et Digest.

Centralise la logique de filtrage par mode (Serein, Perspective, Focus)
pour éviter la duplication entre RecommendationService (feed) et
DigestSelector (digest).
"""

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.source import Source, UserSource
from app.models.enums import BiasStance


# --- Constantes Serein ---

SEREIN_EXCLUDED_THEMES = ["society", "international", "economy", "politics"]

SEREIN_KEYWORDS = [
    "politique", "guerre", "conflit", "élections", "inflation", "grève",
    "drame", "fait divers", "faits divers", "crise", "scandale",
    "terrorisme", "corruption", "procès", "violence", "catastrophe",
    "manifestation", "géopolitique",
    "trump", "musk", "poutine", "macron", "netanyahou", "zelensky",
    "ukraine", "gaza",
]


def apply_serein_filter(query):
    """Exclut les thèmes anxiogènes et les mots-clés négatifs.

    Utilisé par le mode INSPIRATION (feed) et le mode SEREIN (digest).
    Filtre au niveau SQL pour performance.
    """
    query = query.where(Source.theme.notin_(SEREIN_EXCLUDED_THEMES))
    keywords_pattern = "|".join(SEREIN_KEYWORDS)
    # Handle NULL title/description: NULL ~* 'pattern' → NULL → NOT NULL → NULL
    # which silently excludes rows. Use OR IS NULL to keep them.
    query = query.where(
        or_(Content.title.is_(None), ~Content.title.op("~*")(keywords_pattern))
    )
    query = query.where(
        or_(Content.description.is_(None), ~Content.description.op("~*")(keywords_pattern))
    )
    return query


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
    # 1. Articles de sources matchant le thème (via ix_contents_source_id)
    # 2. Articles classifiés ML dans ce thème (via ix_contents_theme_published)
    return query.where(
        or_(
            Content.source_id.in_(theme_source_ids_subq),
            Content.theme == theme_slug,
        )
    )


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


def is_cluster_serein_compatible(cluster: "TopicCluster") -> bool:
    """Vérifie si un topic cluster est compatible avec le mode Serein.

    Un cluster est EXCLU si :
    - Son thème dominant ∈ SEREIN_EXCLUDED_THEMES, OU
    - >50% de ses articles matchent au moins un SEREIN_KEYWORD dans titre/description

    Args:
        cluster: TopicCluster à évaluer (from importance_detector)

    Returns:
        True si le cluster est serein-compatible (peut être inclus)
    """
    # Check 1: thème dominant
    if cluster.theme and cluster.theme.lower() in SEREIN_EXCLUDED_THEMES:
        return False

    # Check 2: mots-clés anxiogènes dans titre/description
    import re as _re
    pattern = _re.compile("|".join(SEREIN_KEYWORDS), _re.IGNORECASE)
    match_count = 0
    for content in cluster.contents:
        text = (content.title or "") + " " + (content.description or "")
        if pattern.search(text):
            match_count += 1

    if len(cluster.contents) > 0 and match_count / len(cluster.contents) > 0.5:
        return False

    return True


def find_perspective_article(
    candidates: list["Content"],
    topic_source_ids: set[UUID],
    user_bias: "BiasStance",
) -> "Content | None":
    """Trouve 1 article de biais opposé à l'utilisateur, hors des sources du topic.

    Utilisé par TopicSelector pour enrichir un topic en mode Perspective.

    Args:
        candidates: Pool global de candidats
        topic_source_ids: Source IDs déjà dans le topic (à exclure)
        user_bias: Biais dominant de l'utilisateur

    Returns:
        Content de biais opposé, ou None si aucun trouvé
    """
    opposing = get_opposing_biases(user_bias)

    for content in candidates:
        if content.source_id in topic_source_ids:
            continue
        if content.source and content.source.bias_stance in opposing:
            return content

    return None


async def calculate_user_bias(session: AsyncSession, user_id: UUID) -> BiasStance:
    """Détermine le biais dominant de l'utilisateur via ses sources suivies.

    Heuristique : score -1 pour gauche, +1 pour droite, retourne la tendance.
    Fallback CENTER si aucune source suivie.
    """
    result = await session.execute(
        select(Source.bias_stance)
        .join(UserSource)
        .where(UserSource.user_id == user_id)
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
