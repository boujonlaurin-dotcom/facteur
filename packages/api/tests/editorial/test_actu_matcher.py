"""Tests for ActuMatcher (ÉTAPE 3A — per-user actu article matching)."""

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock
from uuid import uuid4

from app.services.editorial.actu_matcher import ActuMatcher
from app.services.editorial.schemas import EditorialSubject


def _make_content(
    source_id=None,
    is_paid=False,
    published_at=None,
    title="Test article",
    content_id=None,
    source_name="Le Monde",
):
    """Create a mock Content object."""
    c = MagicMock()
    c.id = content_id or uuid4()
    c.title = title
    c.source_id = source_id or uuid4()
    c.is_paid = is_paid
    c.published_at = published_at or datetime.now(UTC)
    c.source = MagicMock()
    c.source.name = source_name
    return c


def _make_cluster(cluster_id: str, contents: list):
    cluster = MagicMock()
    cluster.cluster_id = cluster_id
    cluster.contents = contents
    return cluster


def _make_subject(topic_id: str, rank: int = 1) -> EditorialSubject:
    return EditorialSubject(
        rank=rank,
        topic_id=topic_id,
        label="Test",
        selection_reason="Test",
        deep_angle="Test",
    )


class TestMatchForUser:
    def test_prefers_user_source(self):
        user_source_id = uuid4()
        other_source_id = uuid4()

        user_content = _make_content(source_id=user_source_id, title="User article")
        other_content = _make_content(source_id=other_source_id, title="Other article")

        cluster = _make_cluster("c1", [other_content, user_content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[cluster],
            user_source_ids={user_source_id},
            excluded_content_ids=set(),
        )

        assert result[0].actu_article is not None
        assert result[0].actu_article.is_user_source is True
        assert result[0].actu_article.title == "User article"

    def test_excludes_old_articles(self):
        old_content = _make_content(
            published_at=datetime.now(UTC) - timedelta(hours=48)
        )
        cluster = _make_cluster("c1", [old_content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[cluster],
            user_source_ids=set(),
            excluded_content_ids=set(),
        )

        assert result[0].actu_article is None

    def test_excludes_paid_articles(self):
        paid_content = _make_content(is_paid=True)
        cluster = _make_cluster("c1", [paid_content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[cluster],
            user_source_ids=set(),
            excluded_content_ids=set(),
        )

        assert result[0].actu_article is None

    def test_excludes_dismissed_content(self):
        content = _make_content()
        excluded_id = content.id
        cluster = _make_cluster("c1", [content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[cluster],
            user_source_ids=set(),
            excluded_content_ids={excluded_id},
        )

        assert result[0].actu_article is None

    def test_source_diversity_across_subjects(self):
        shared_source = uuid4()
        other_source = uuid4()

        c1_article = _make_content(source_id=shared_source, title="Article 1")
        c2_article_same = _make_content(source_id=shared_source, title="Article 2 same source")
        c2_article_diff = _make_content(source_id=other_source, title="Article 2 diff source")

        cluster1 = _make_cluster("c1", [c1_article])
        cluster2 = _make_cluster("c2", [c2_article_same, c2_article_diff])

        subjects = [_make_subject("c1", rank=1), _make_subject("c2", rank=2)]

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=subjects,
            clusters=[cluster1, cluster2],
            user_source_ids=set(),
            excluded_content_ids=set(),
        )

        # First subject gets shared_source article
        assert result[0].actu_article.source_id == shared_source
        # Second subject should pick different source (diversity constraint)
        assert result[1].actu_article.source_id == other_source

    def test_cluster_not_found(self):
        subject = _make_subject("nonexistent")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[],  # No clusters
            user_source_ids=set(),
            excluded_content_ids=set(),
        )

        assert result[0].actu_article is None
        assert result[0].topic_id == "nonexistent"

    def test_fallback_to_mainstream(self):
        user_source_id = uuid4()
        mainstream_source = uuid4()

        mainstream_content = _make_content(
            source_id=mainstream_source, title="Mainstream article"
        )
        cluster = _make_cluster("c1", [mainstream_content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_for_user(
            subjects=[subject],
            clusters=[cluster],
            user_source_ids={user_source_id},  # User follows different source
            excluded_content_ids=set(),
        )

        assert result[0].actu_article is not None
        assert result[0].actu_article.is_user_source is False
