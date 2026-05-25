"""Tests pour `app/services/language_user_filter.py`.

Couvre :

- `is_foreign_source` : règles FR/None/EN/autres.
- `get_hide_non_fr_pref` : default (no row), lecture.
- `apply_language_filter` : toggle ON/OFF, source suivie protégée, None
  traité comme FR.
- `recompute_auto_pref` : mode auto bascule, mode manuel gelé, no-op si
  pas de personalization row.
"""

from uuid import uuid4

import pytest

from app.models.enums import SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_personalization import UserPersonalization
from app.services.language_user_filter import (
    apply_language_filter,
    get_hide_non_fr_pref,
    is_foreign_source,
    recompute_auto_pref,
)

# ---- is_foreign_source --------------------------------------------------------


def test_is_foreign_source_none_is_native():
    """`None` = inconnu → traité comme FR (rétro-compat)."""
    assert is_foreign_source(None) is False


def test_is_foreign_source_fr_is_native():
    assert is_foreign_source("fr") is False


def test_is_foreign_source_en_is_foreign():
    assert is_foreign_source("en") is True


def test_is_foreign_source_other_is_foreign():
    assert is_foreign_source("de") is True
    assert is_foreign_source("es") is True


# ---- apply_language_filter ----------------------------------------------------


class _FakeSource:
    def __init__(self, id, language):
        self.id = id
        self.language = language


class _FakeArticle:
    def __init__(self, source):
        self.source = source


def _lang_of(article):
    return article.source.language


def test_apply_filter_off_returns_articles_unchanged():
    src1 = _FakeSource(uuid4(), "en")
    src2 = _FakeSource(uuid4(), "fr")
    articles = [_FakeArticle(src1), _FakeArticle(src2)]

    out = apply_language_filter(
        articles,
        hide_non_fr_sources=False,
        followed_source_ids=set(),
        source_language_of=_lang_of,
    )

    assert len(out) == 2


def test_apply_filter_on_removes_foreign_non_followed():
    src_en = _FakeSource(uuid4(), "en")
    src_fr = _FakeSource(uuid4(), "fr")
    articles = [_FakeArticle(src_en), _FakeArticle(src_fr)]

    out = apply_language_filter(
        articles,
        hide_non_fr_sources=True,
        followed_source_ids=set(),
        source_language_of=_lang_of,
    )

    assert len(out) == 1
    assert out[0].source.language == "fr"


def test_apply_filter_on_preserves_foreign_followed():
    src_en = _FakeSource(uuid4(), "en")
    articles = [_FakeArticle(src_en)]

    out = apply_language_filter(
        articles,
        hide_non_fr_sources=True,
        followed_source_ids={src_en.id},
        source_language_of=_lang_of,
    )

    assert len(out) == 1
    assert out[0].source.language == "en"


def test_apply_filter_on_keeps_unknown_language():
    """language=None doit être traité comme FR (rétro-compat)."""
    src_unknown = _FakeSource(uuid4(), None)
    articles = [_FakeArticle(src_unknown)]

    out = apply_language_filter(
        articles,
        hide_non_fr_sources=True,
        followed_source_ids=set(),
        source_language_of=_lang_of,
    )

    assert len(out) == 1


# ---- get_hide_non_fr_pref -----------------------------------------------------


@pytest.mark.asyncio
async def test_get_hide_non_fr_pref_default_true_when_no_row(db_session):
    """Aucune row personalization → default `True` (cohérent avec server_default)."""
    user_id = uuid4()
    assert await get_hide_non_fr_pref(db_session, user_id) is True


@pytest.mark.asyncio
async def test_get_hide_non_fr_pref_reads_stored_value(db_session):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    db_session.add(
        UserPersonalization(
            user_id=user_id,
            hide_non_fr_sources=False,
            language_filter_user_set=True,
        )
    )
    await db_session.commit()

    assert await get_hide_non_fr_pref(db_session, user_id) is False


# ---- recompute_auto_pref ------------------------------------------------------


async def _make_user_with_pref(db_session, user_set: bool, current: bool = True):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    db_session.add(
        UserPersonalization(
            user_id=user_id,
            hide_non_fr_sources=current,
            language_filter_user_set=user_set,
        )
    )
    await db_session.commit()
    return user_id


async def _make_source(db_session, language: str | None):
    src = Source(
        id=uuid4(),
        name=f"Test {language}",
        url="https://example.test",
        feed_url=f"https://example.test/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        language=language,
    )
    db_session.add(src)
    await db_session.commit()
    return src


@pytest.mark.asyncio
async def test_recompute_noop_in_manual_mode(db_session):
    """Si l'utilisateur a touché le toggle, le recalcul ne change rien."""
    user_id = await _make_user_with_pref(db_session, user_set=True, current=False)
    en_source = await _make_source(db_session, language="en")
    db_session.add(UserSource(user_id=user_id, source_id=en_source.id))
    await db_session.commit()

    await recompute_auto_pref(db_session, user_id)
    await db_session.commit()

    pref = await db_session.get(UserPersonalization, user_id)
    assert pref.hide_non_fr_sources is False  # gelé


@pytest.mark.asyncio
async def test_recompute_auto_off_when_user_follows_foreign(db_session):
    user_id = await _make_user_with_pref(db_session, user_set=False, current=True)
    en_source = await _make_source(db_session, language="en")
    db_session.add(UserSource(user_id=user_id, source_id=en_source.id))
    await db_session.commit()

    await recompute_auto_pref(db_session, user_id)
    await db_session.commit()

    pref = await db_session.get(UserPersonalization, user_id)
    assert pref.hide_non_fr_sources is False


@pytest.mark.asyncio
async def test_recompute_auto_on_when_only_fr_sources(db_session):
    """User suit seulement des sources FR (et unknown) → toggle = True."""
    user_id = await _make_user_with_pref(db_session, user_set=False, current=False)
    fr_source = await _make_source(db_session, language="fr")
    unknown_source = await _make_source(db_session, language=None)
    db_session.add(UserSource(user_id=user_id, source_id=fr_source.id))
    db_session.add(UserSource(user_id=user_id, source_id=unknown_source.id))
    await db_session.commit()

    await recompute_auto_pref(db_session, user_id)
    await db_session.commit()

    pref = await db_session.get(UserPersonalization, user_id)
    assert pref.hide_non_fr_sources is True


@pytest.mark.asyncio
async def test_recompute_noop_when_no_personalization_row(db_session):
    """Pas de row personalization (user nouveau) → no-op, pas d'exception."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    # Doit juste ne pas planter.
    await recompute_auto_pref(db_session, user_id)
    await db_session.commit()
