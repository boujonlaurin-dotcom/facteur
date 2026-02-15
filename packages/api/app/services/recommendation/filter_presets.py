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

    Match sur 3 couches :
    1. Source.theme (thème principal de la source)
    2. Source.secondary_themes (thèmes secondaires des sources généralistes)
    3. Content.theme (thème ML inféré par article, fallback)

    Utilisé par le mode THEME_FOCUS (digest) et le filtre thème (feed).
    """
    return query.where(
        or_(
            Source.theme == theme_slug,
            Source.secondary_themes.any(theme_slug),
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
