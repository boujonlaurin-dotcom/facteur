"""Tests DB de `apply_keyword_filter` (recherche universelle, story 30.1).

Le filtre mot-clé du feed matche désormais en **début de mot** (regex POSIX
Postgres `~*` avec `\\m`) sur le titre **et** la description, au lieu de
`ILIKE '%kw%'`. Objectif : « belle » ne doit plus remonter « poubelle » ou
« Isabelle » (sous-chaîne en milieu de mot), et l'entrée utilisateur doit être
échappée (les `%`, `_`, `(`… ne sont plus des jokers).

Ces tests tournent contre Postgres (le `~*` n'existe pas en SQLite) — cf. la
DB de test `facteur_test`.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.services.recommendation.filter_presets import apply_keyword_filter


async def _insert_source(db_session) -> Source:
    src = Source(
        id=uuid4(),
        name="Keyword Source",
        url=f"https://{uuid4().hex}.com",
        feed_url=f"https://{uuid4().hex}.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
    )
    db_session.add(src)
    await db_session.commit()
    return src


async def _insert_content(
    db_session, source_id, *, title: str, description: str | None = None
) -> UUID:
    cid = uuid4()
    db_session.add(
        Content(
            id=cid,
            source_id=source_id,
            title=title,
            description=description,
            url=f"https://example.com/{cid}",
            guid=f"guid-{cid}",
            published_at=datetime.now(UTC) - timedelta(hours=2),
            content_type=ContentType.ARTICLE,
            theme="tech",
        )
    )
    await db_session.commit()
    return cid


async def _titles(db_session, source_id, keyword: str) -> set[str]:
    query = select(Content).where(Content.source_id == source_id)
    query = apply_keyword_filter(query, keyword)
    rows = (await db_session.execute(query)).scalars().all()
    return {r.title for r in rows}


@pytest.mark.asyncio
async def test_keyword_matches_word_boundary_not_substring(db_session):
    src = await _insert_source(db_session)
    await _insert_content(db_session, src.id, title="Isabelle Adjani au festival")
    await _insert_content(db_session, src.id, title="Le tri de la poubelle jaune")
    await _insert_content(db_session, src.id, title="Les belles promesses du candidat")
    await _insert_content(db_session, src.id, title="Retour a la belle epoque")

    titles = await _titles(db_session, src.id, "belle")

    # « belles » et « belle » (début de mot) → oui ; « Isabelle »/« poubelle »
    # (milieu de mot) → non.
    assert titles == {
        "Les belles promesses du candidat",
        "Retour a la belle epoque",
    }


@pytest.mark.asyncio
async def test_keyword_matches_description_too(db_session):
    src = await _insert_source(db_session)
    await _insert_content(
        db_session,
        src.id,
        title="Actualite generale du jour",
        description="une tres belle initiative locale",
    )

    titles = await _titles(db_session, src.id, "belle")

    # Le titre ne contient pas « belle » : c'est la description qui qualifie.
    assert titles == {"Actualite generale du jour"}


@pytest.mark.asyncio
async def test_keyword_exact_form_is_word_start_not_whole_word(db_session):
    src = await _insert_source(db_session)
    await _insert_content(db_session, src.id, title="Les belles promesses")
    await _insert_content(db_session, src.id, title="Une belle histoire")

    # « belles » ne matche que le pluriel (début de mot « belles »), pas
    # « belle » seul — pas de `\\M` final, donc les flexions passent, mais un
    # préfixe plus long ne rétro-matche pas un mot plus court.
    assert await _titles(db_session, src.id, "belles") == {"Les belles promesses"}


@pytest.mark.asyncio
async def test_multiword_query_is_conjunctive(db_session):
    src = await _insert_source(db_session)
    await _insert_content(db_session, src.id, title="Les belles promesses du candidat")
    await _insert_content(db_session, src.id, title="Retour a la belle epoque")

    # Tous les tokens doivent matcher (AND) : « belle promesses » ne garde que
    # l'article qui porte les deux mots.
    titles = await _titles(db_session, src.id, "belle promesses")

    assert titles == {"Les belles promesses du candidat"}


@pytest.mark.asyncio
async def test_special_chars_are_escaped_not_wildcards(db_session):
    src = await _insert_source(db_session)
    await _insert_content(db_session, src.id, title="Remise de 50% (offre limitee)")
    await _insert_content(db_session, src.id, title="Les belles promesses")

    # `%` littéral : matche le titre qui le contient, sans lever d'erreur regex.
    assert await _titles(db_session, src.id, "50%") == {"Remise de 50% (offre limitee)"}
    # `%` n'est PAS un joker : « belle% » (chaîne littérale) n'existe nulle part.
    assert await _titles(db_session, src.id, "belle%") == set()
    # `_` n'est PAS un joker mono-caractère non plus.
    assert await _titles(db_session, src.id, "belle_") == set()
    # Parenthèse échappée : pas de crash « invalid regular expression ».
    assert await _titles(db_session, src.id, "(offre") == set()


@pytest.mark.asyncio
async def test_blank_keyword_is_noop(db_session):
    src = await _insert_source(db_session)
    await _insert_content(db_session, src.id, title="Article un")
    await _insert_content(db_session, src.id, title="Article deux")

    # Une requête vide / blanche ne filtre rien (aucun token) → tous les contenus.
    assert await _titles(db_session, src.id, "   ") == {"Article un", "Article deux"}
