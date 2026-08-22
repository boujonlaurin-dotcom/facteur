"""Factories de mocks partagées par les tests du pipeline éditorial.

Elles vivaient dans `test_pipeline.py` ; les importer depuis un autre module de
test **exécuterait** ce module, d'où ce module neutre — le pendant de
`conftest.py`, qui ne sait partager que des fixtures.
"""

from datetime import UTC, datetime
from unittest.mock import MagicMock
from uuid import uuid4


def _make_content_mock(title="Test article", bias_stance="center"):
    c = MagicMock()
    c.id = uuid4()
    c.title = title
    c.source_id = uuid4()
    c.source = MagicMock()
    c.source.name = "Test Source"
    c.source.bias_stance = bias_stance
    c.source.url = "https://test-source.example/"
    c.source.type = None
    c.source.reliability_score = None
    c.url = "https://test-source.example/article"
    c.description = None
    c.topics = ["politique"]
    c.entities = []
    c.language = "fr"
    c.published_at = datetime.now(UTC)
    c.is_paid = False
    return c


def _make_cluster_mock(
    cluster_id="c1",
    label="Test cluster",
    contents=None,
    source_ids=None,
    theme="politique",
):
    cluster = MagicMock()
    cluster.cluster_id = cluster_id
    cluster.label = label
    cluster.contents = contents or [_make_content_mock()]
    cluster.source_ids = source_ids or {uuid4()}
    cluster.theme = theme
    cluster.is_trending = True
    cluster.is_multi_source = True
    return cluster
