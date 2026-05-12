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
    content_type=None,
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
    # content_type=None : laisser MagicMock auto-générer (texte par défaut).
    if content_type is not None:
        c.content_type = content_type
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
        c2_article_same = _make_content(
            source_id=shared_source, title="Article 2 same source"
        )
        c2_article_diff = _make_content(
            source_id=other_source, title="Article 2 diff source"
        )

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


class TestMatchGlobal:
    def test_picks_most_recent(self):
        source1 = uuid4()
        source2 = uuid4()

        old = _make_content(
            source_id=source1,
            title="Older",
            published_at=datetime.now(UTC) - timedelta(hours=2),
        )
        new = _make_content(
            source_id=source2,
            title="Newer",
            published_at=datetime.now(UTC),
        )

        cluster = _make_cluster("c1", [old, new])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        assert result[0].actu_article is not None
        assert result[0].actu_article.title == "Newer"

    def test_excludes_paid(self):
        paid = _make_content(is_paid=True)
        cluster = _make_cluster("c1", [paid])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        assert result[0].actu_article is None

    def test_excludes_old(self):
        old = _make_content(published_at=datetime.now(UTC) - timedelta(hours=48))
        cluster = _make_cluster("c1", [old])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        assert result[0].actu_article is None

    def test_source_diversity(self):
        shared_source = uuid4()
        other_source = uuid4()

        c1_article = _make_content(source_id=shared_source, title="A1")
        c2_same = _make_content(source_id=shared_source, title="A2 same")
        c2_diff = _make_content(source_id=other_source, title="A2 diff")

        cluster1 = _make_cluster("c1", [c1_article])
        cluster2 = _make_cluster("c2", [c2_same, c2_diff])

        subjects = [_make_subject("c1", rank=1), _make_subject("c2", rank=2)]

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=subjects, clusters=[cluster1, cluster2])

        assert result[0].actu_article.source_id == shared_source
        assert result[1].actu_article.source_id == other_source

    def test_cluster_not_found(self):
        subject = _make_subject("nonexistent")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[])

        assert result[0].actu_article is None
        assert result[0].topic_id == "nonexistent"

    def test_is_user_source_always_false(self):
        content = _make_content(title="Any article")
        cluster = _make_cluster("c1", [content])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        assert result[0].actu_article is not None
        assert result[0].actu_article.is_user_source is False


class TestNonTextFiltering:
    """Pass 1 actu matching exclut les vidéos/YouTube (revue de presse texte).

    Cf. bug-digest-pipeline-fallbacks.md C3 : sans filtre, BLAST YouTube
    passait au-dessus du miroir Reddit en Article 4. Le pass 3 relaxé
    autorise la vidéo en dernier recours.
    """

    def test_pass1_excludes_youtube_when_text_available(self):
        text_source = uuid4()
        video_source = uuid4()

        video = _make_content(
            source_id=video_source,
            content_type="youtube",
            title="Vidéo BLAST",
        )
        text = _make_content(
            source_id=text_source,
            content_type="article",
            title="Article texte",
        )
        cluster = _make_cluster("c1", [video, text])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        assert result[0].actu_article is not None
        assert result[0].actu_article.title == "Article texte"

    def test_youtube_only_cluster_falls_back_to_video_in_pass3(self):
        """Si TOUT le cluster est en vidéo (cas extrême), pass 3 (relaxed)
        autorise la vidéo plutôt que de laisser le sujet sans actu."""
        video = _make_content(content_type="youtube", title="Vidéo unique")
        cluster = _make_cluster("c1", [video])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        # Pass 1 et 2 (texte-only) échouent, pass 3 (relaxed + vidéo OK) passe.
        assert result[0].actu_article is not None
        assert result[0].actu_article.title == "Vidéo unique"

    def test_extra_articles_exclude_videos(self):
        """Les actus annexes affichées sous la carte excluent aussi les vidéos."""
        # Timestamps explicites : primary plus récent que text2 pour qu'il
        # soit choisi comme principal (sort par recency).
        now = datetime.now(UTC)
        primary = _make_content(
            content_type="article",
            title="Principal",
            published_at=now,
        )
        video = _make_content(
            content_type="youtube",
            title="Vidéo",
            published_at=now - timedelta(minutes=30),
        )
        text2 = _make_content(
            content_type="article",
            title="Article 2",
            published_at=now - timedelta(hours=1),
        )
        cluster = _make_cluster("c1", [primary, video, text2])
        subject = _make_subject("c1")

        matcher = ActuMatcher(actu_max_age_hours=24)
        result = matcher.match_global(subjects=[subject], clusters=[cluster])

        # Le principal est texte (le plus récent), et les extras ne contiennent
        # pas la vidéo.
        assert result[0].actu_article.title == "Principal"
        extra_titles = [e.title for e in result[0].extra_actu_articles]
        assert "Vidéo" not in extra_titles
        assert "Article 2" in extra_titles
