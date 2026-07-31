"""Tests unitaires de la règle de fraîcheur cadence-aware (source_freshness)."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

from app.models.enums import SourceType
from app.services.source_freshness import classify


def _src(source_type=SourceType.ARTICLE):
    return SimpleNamespace(type=source_type)


def _days_ago(n):
    return datetime.now(UTC) - timedelta(days=n)


class TestClassifyArticle:
    def test_fresh_article_kept(self):
        v = classify(_src(SourceType.ARTICLE), _days_ago(3))
        assert not v.excluded and not v.downgraded

    def test_dead_article_excluded(self):
        v = classify(_src(SourceType.ARTICLE), _days_ago(60))
        assert v.excluded

    def test_article_no_publication_excluded(self):
        v = classify(_src(SourceType.ARTICLE), None)
        assert v.excluded


class TestClassifySlowCadence:
    def test_fresh_podcast_kept(self):
        v = classify(_src(SourceType.PODCAST), _days_ago(10))
        assert not v.excluded and not v.downgraded

    def test_silent_30d_but_alive_90d_downgraded(self):
        v = classify(_src(SourceType.YOUTUBE), _days_ago(45))
        assert not v.excluded and v.downgraded

    def test_truly_dead_slow_source_excluded(self):
        v = classify(_src(SourceType.PODCAST), _days_ago(120))
        assert v.excluded

    def test_slow_no_publication_excluded(self):
        v = classify(_src(SourceType.YOUTUBE), None)
        assert v.excluded


def test_naive_datetime_is_handled():
    # published_at sans tzinfo ne doit pas lever (comparaison aware/naive).
    naive = datetime.utcnow() - timedelta(days=2)
    v = classify(_src(SourceType.ARTICLE), naive)
    assert not v.excluded
