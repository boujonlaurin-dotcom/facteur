"""Regression tests for excluding the reference article from its own
perspectives list (PO refinement R3, post PR #619).

Covers three layers:
- ``normalize_domain`` — canonicalisation du domaine, désormais la clé
  d'égalité qui retire le média courant du snapshot de couverture.
- ``_recompute_bias_distribution`` — keeps the bias counters in sync with
  the filtered list returned to the front.
- ``_load_cluster_articles_for_representative`` — loads the complete coverage
  pool; the endpoint subsequently removes the whole domain currently open.
"""

from datetime import UTC, date, datetime
from uuid import uuid4

import pytest
import pytest_asyncio

from app.models.content import Content
from app.models.daily_digest import DailyDigest
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.routers.contents import (
    _load_cluster_articles_for_representative,
    _recompute_bias_distribution,
)
from app.services.perspective_service import normalize_domain

# --- Helper unit tests ------------------------------------------------------


def test_normalize_domain_strips_scheme_www_and_path():
    """Deux URL du même média collapsent sur une seule clé de couverture."""
    assert normalize_domain("https://www.lemonde.fr/article/abc/") == "lemonde.fr"
    assert normalize_domain("http://lemonde.fr/autre-article") == "lemonde.fr"
    assert normalize_domain("https://LEMONDE.fr") == "lemonde.fr"
    # Domaine nu (tel que persisté dans le snapshot) accepté sans schéma.
    assert normalize_domain("www.lemonde.fr") == "lemonde.fr"


def test_normalize_domain_empty_inputs():
    assert normalize_domain(None) == ""
    assert normalize_domain("") == ""


def test_recompute_bias_distribution_tallies_known_stances_only():
    perspectives = [
        {"bias_stance": "left"},
        {"bias_stance": "left"},
        {"bias_stance": "center"},
        {"bias_stance": "right"},
        {"bias_stance": "unknown"},  # ignored
        {"bias_stance": None},  # ignored
        {"no_stance_field": True},  # ignored
    ]
    assert _recompute_bias_distribution(perspectives) == {
        "left": 2,
        "center-left": 0,
        "center": 1,
        "center-right": 0,
        "right": 1,
    }


# --- Integration test for the cluster loader --------------------------------


@pytest_asyncio.fixture
async def digest_with_subject(db_session, request):
    """Build a Source + 3 Content rows + 1 editorial DailyDigest snapshot.

    The subject references the same 3 content_ids in both ``actu_article``
    and ``extra_actu_articles`` so the cluster loader treats them as
    carousel siblings. The loader returns the complete pool so coverage can be
    reconstructed once, before the endpoint excludes the current domain.

    Paramétrable (indirect) sur le ``format_version`` du digest — le filtre du
    loader matche par préfixe ``editorial_``, pas une liste figée.
    """
    format_version = getattr(request, "param", "editorial_v1")
    user_id = uuid4()

    source = Source(
        id=uuid4(),
        name="Le Monde",
        url="https://lemonde.fr",
        feed_url=f"https://lemonde.fr/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()

    ref = Content(
        id=uuid4(),
        source_id=source.id,
        title="Article courant",
        url="https://lemonde.fr/ref",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"ref-{uuid4()}",
    )
    sib_a = Content(
        id=uuid4(),
        source_id=source.id,
        title="Sibling A",
        url="https://lemonde.fr/sib-a",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"sib-a-{uuid4()}",
    )
    sib_b = Content(
        id=uuid4(),
        source_id=source.id,
        title="Sibling B",
        url="https://lemonde.fr/sib-b",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        guid=f"sib-b-{uuid4()}",
    )
    db_session.add_all([ref, sib_a, sib_b])
    await db_session.commit()

    digest = DailyDigest(
        id=uuid4(),
        user_id=user_id,
        target_date=date.today(),
        format_version=format_version,
        is_serene=False,
        items={
            "subjects": [
                {
                    "representative_content_id": str(ref.id),
                    "actu_article": {"content_id": str(ref.id)},
                    "extra_actu_articles": [
                        {"content_id": str(sib_a.id)},
                        {"content_id": str(sib_b.id)},
                    ],
                }
            ]
        },
    )
    db_session.add(digest)
    await db_session.commit()
    return {
        "user_id": user_id,
        "ref": ref,
        "sib_a": sib_a,
        "sib_b": sib_b,
    }


@pytest.mark.asyncio
async def test_load_cluster_articles_returns_complete_coverage_pool(
    db_session, digest_with_subject
):
    cluster = await _load_cluster_articles_for_representative(
        db=db_session,
        content_id=digest_with_subject["ref"].id,
        user_id=digest_with_subject["user_id"],
    )
    returned_ids = {c.id for c in cluster}
    assert returned_ids == {
        digest_with_subject["ref"].id,
        digest_with_subject["sib_a"].id,
        digest_with_subject["sib_b"].id,
    }


@pytest.mark.parametrize("digest_with_subject", ["editorial_v4"], indirect=True)
@pytest.mark.asyncio
async def test_load_cluster_articles_matches_editorial_v4(
    db_session, digest_with_subject
):
    """Régression du filtre figé : `.in_(("editorial_v1", "editorial_v2"))`
    omettait déjà v3 (fallback live silencieux) — un digest v4 DOIT matcher
    via le préfixe, sur le modèle de `test_digest_content_refs`."""
    cluster = await _load_cluster_articles_for_representative(
        db=db_session,
        content_id=digest_with_subject["ref"].id,
        user_id=digest_with_subject["user_id"],
    )
    assert {c.id for c in cluster} == {
        digest_with_subject["ref"].id,
        digest_with_subject["sib_a"].id,
        digest_with_subject["sib_b"].id,
    }


@pytest.mark.asyncio
async def test_load_stored_perspectives_matches_editorial_v4(db_session):
    """Même régression côté snapshot : le loader `perspective_articles` doit
    lire un digest `editorial_v4` (préfixe) au lieu de retomber en live path."""
    from app.routers.contents import _load_stored_perspectives_for_representative

    user_id = uuid4()
    ref_id = uuid4()
    digest = DailyDigest(
        id=uuid4(),
        user_id=user_id,
        target_date=date.today(),
        format_version="editorial_v4",
        is_serene=False,
        items={
            "subjects": [
                {
                    "representative_content_id": str(ref_id),
                    "actu_article": {"content_id": str(ref_id)},
                    "perspective_articles": [
                        {"title": "Angle B", "source_domain": "figaro.fr"}
                    ],
                    "bias_distribution": {"left": 1},
                    "divergence_level": "medium",
                    "perspective_count": 1,
                }
            ]
        },
    )
    db_session.add(digest)
    await db_session.commit()

    snapshot = await _load_stored_perspectives_for_representative(
        db=db_session, content_id=ref_id, user_id=user_id
    )

    assert snapshot is not None
    assert snapshot.articles == [{"title": "Angle B", "source_domain": "figaro.fr"}]
    assert snapshot.divergence_level == "medium"
