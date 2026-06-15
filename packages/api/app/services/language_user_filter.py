"""Filtre langue user-aware appliqué à l'Essentiel, au feed et au digest.

Le user a une préférence `hide_non_fr_sources` (UserPersonalization) qui,
quand elle est activée, masque les cartes issues de sources non-FR — sauf
quand la source est explicitement suivie par l'utilisateur.

Le toggle a deux modes :

- **Auto** (`language_filter_user_set = false`) : on recalcule la valeur
  au follow/unfollow d'une source. Si l'utilisateur ne suit aucune source
  étrangère → toggle ON ; sinon → OFF.
- **Manuel** (`language_filter_user_set = true`) : on respecte le choix
  user, le recalcul auto ne touche plus le toggle.

Conventions :

- `Source.language = None` est traité **comme `'fr'`** (rétro-compat) :
  c'est l'alignement avec le client mobile et avec
  `editorial/writer.py:_looks_french` qui ne rejettent pas les sources
  dont la langue n'a pas pu être déterminée.
- Le filtre est **binaire** : FR (ou unknown) vs. autres. Pas de
  granularité par langue cible.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import ColumnElement

from app.models.source import Source, UserSource
from app.models.user_personalization import UserPersonalization

# Langues considérées comme FR pour le filtre. `None` est ajouté
# dynamiquement dans `is_foreign_source` — on ne peut pas le mettre dans
# un set typé `str`.
_NATIVE_LANGUAGES: frozenset[str] = frozenset({"fr"})


def is_foreign_source(language: str | None) -> bool:
    """True si la source doit être considérée comme étrangère.

    `None` → False (rétro-compat : on ne masque pas les sources dont la
    langue n'a pas pu être déterminée).
    """
    if language is None:
        return False
    return language not in _NATIVE_LANGUAGES


def language_filter_clause(
    followed_source_ids: set[UUID] | frozenset[UUID] | None = None,
) -> ColumnElement[bool]:
    """Clause SQL "garder cette source" pour le filtre langue.

    `Source.language IS NULL` reste FR par défaut (rétro-compat). Les
    sources explicitement suivies bypassent le filtre.
    """
    keep = or_(Source.language.is_(None), Source.language == "fr")
    if followed_source_ids:
        keep = or_(keep, Source.id.in_(list(followed_source_ids)))
    return keep


async def get_hide_non_fr_pref(db: AsyncSession, user_id: UUID) -> bool:
    """Lit la préférence `hide_non_fr_sources` du user.

    Si aucune row `UserPersonalization` n'existe encore → True (default
    server_default cohérent avec la migration lg02).
    """
    row = await db.scalar(
        select(UserPersonalization.hide_non_fr_sources).where(
            UserPersonalization.user_id == user_id
        )
    )
    if row is None:
        return True
    return bool(row)


def apply_language_filter(
    articles: list,
    *,
    hide_non_fr_sources: bool,
    followed_source_ids: set[UUID] | frozenset[UUID],
    source_language_of: callable,
) -> list:
    """Filtre une liste d'articles selon la préférence langue.

    Polymorphe : `articles` peut contenir n'importe quel objet — on
    s'appuie sur `source_language_of(article)` pour récupérer la langue
    et sur `article.source.id` pour la comparaison avec
    `followed_source_ids`. Cette approche permet de réutiliser le même
    helper pour `DigestTopicArticle`, `EssentielArticle`, `Content`, etc.

    Si `hide_non_fr_sources` est False → retourne `articles` sans toucher.
    """
    if not hide_non_fr_sources:
        return list(articles)

    kept = []
    for article in articles:
        source_id = article.source.id
        if source_id in followed_source_ids:
            kept.append(article)
            continue
        language = source_language_of(article)
        if is_foreign_source(language):
            continue
        kept.append(article)
    return kept


async def recompute_auto_pref(db: AsyncSession, user_id: UUID) -> None:
    """Recalcule `hide_non_fr_sources` en mode auto, no-op en mode manuel.

    Appelée après tout follow/unfollow de source. Si l'utilisateur a déjà
    touché manuellement au toggle (`language_filter_user_set = true`), on
    ne fait rien — son choix est respecté.

    Sinon, règle :

    - true si l'utilisateur ne suit aucune source étrangère ;
    - false sinon.

    Ne commit pas : le caller orchestre la transaction.
    """
    pref = await db.scalar(
        select(UserPersonalization).where(UserPersonalization.user_id == user_id)
    )
    if pref is None:
        # Pas de personalization row → on n'en crée pas ici (la valeur par
        # défaut côté ORM/DB est déjà `true`, donc cohérente avec la règle
        # quand l'utilisateur n'a aucune source suivie).
        return
    if pref.language_filter_user_set:
        return

    follows_foreign = await db.scalar(
        select(UserSource.source_id)
        .join(Source, Source.id == UserSource.source_id)
        .where(
            UserSource.user_id == user_id,
            Source.language.is_not(None),
            Source.language != "fr",
        )
        .limit(1)
    )

    pref.hide_non_fr_sources = follows_foreign is None
