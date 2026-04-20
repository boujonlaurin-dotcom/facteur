"""Tests for low-priority cluster cap (faits divers + sport) and serein
cluster filter integration at the editorial pipeline level.

Unit tests for the new helpers in
`app.services.recommendation.filter_presets`:
- ``is_sport_cluster``
- ``is_faits_divers_cluster``
- ``cap_low_priority_clusters``

The pipeline-level integration (serein filter + cap inside
``EditorialPipelineService.compute_global_context``) is exercised via the
behavioural assertions on the helpers — the pipeline simply calls them.
"""

from dataclasses import dataclass, field
from uuid import UUID, uuid4

from app.services.recommendation.filter_presets import (
    cap_low_priority_clusters,
    is_faits_divers_cluster,
    is_sport_cluster,
    is_sport_content,
)


@dataclass
class _FakeContent:
    title: str | None = None
    description: str | None = None
    theme: str | None = None
    topics: list[str] | None = None


@dataclass
class _FakeCluster:
    cluster_id: str = "c"
    label: str = ""
    tokens: set = field(default_factory=set)
    contents: list = field(default_factory=list)
    source_ids: set[UUID] = field(default_factory=set)
    theme: str | None = None


def _make(theme=None, titles=None, source_count=1):
    contents = [_FakeContent(title=t) for t in (titles or ["x"])]
    return _FakeCluster(
        cluster_id=str(uuid4()),
        contents=contents,
        theme=theme,
        source_ids={uuid4() for _ in range(source_count)},
    )


class TestIsSportCluster:
    def test_theme_sport_is_sport(self):
        assert is_sport_cluster(_make(theme="sport", titles=["Actu diverse"]))

    def test_keywords_majority_is_sport(self):
        cluster = _make(
            theme="society",
            titles=[
                "PSG bat l'OM en Ligue 1",
                "Mbappé marque un doublé",
                "Tennis Roland-Garros début",
                "Analyse économique",  # 1/4 non-sport
            ],
        )
        assert is_sport_cluster(cluster)

    def test_non_sport_not_flagged(self):
        cluster = _make(
            theme="economy",
            titles=["Inflation en hausse", "Rapport BCE", "Chômage"],
        )
        assert not is_sport_cluster(cluster)

    def test_minority_sport_mentions_not_flagged(self):
        cluster = _make(
            theme="politics",
            titles=[
                "Macron à l'Élysée",
                "Débat parlementaire",
                "Réforme retraites",
                "Le PSG visite la mairie",  # 1/4
            ],
        )
        assert not is_sport_cluster(cluster)


class TestIsSportContent:
    def test_theme_sport_is_sport(self):
        c = _FakeContent(theme="sport", title="Actu diverse")
        assert is_sport_content(c)

    def test_theme_sports_plural_is_sport(self):
        c = _FakeContent(theme="sports", title="x")
        assert is_sport_content(c)

    def test_topic_sport_in_array_is_sport(self):
        c = _FakeContent(theme="tech", topics=["ai", "sport"], title="x")
        assert is_sport_content(c)

    def test_keyword_in_title_is_sport(self):
        c = _FakeContent(theme="tech", title="PSG bat l'OM 3-1 en Ligue 1")
        assert is_sport_content(c)

    def test_neutral_content_is_not_sport(self):
        c = _FakeContent(
            theme="tech",
            topics=["ai", "startups"],
            title="IA générative en entreprise",
            description="Analyse des tendances",
        )
        assert not is_sport_content(c)

    def test_none_fields_not_sport(self):
        c = _FakeContent(theme=None, topics=None, title=None, description=None)
        assert not is_sport_content(c)


class TestIsFaitsDiversCluster:
    def test_majority_faits_divers(self):
        cluster = _make(
            titles=[
                "Accident mortel sur l'A7",
                "Incendie dans un immeuble",
                "Braquage à main armée",
                "Actu culturelle",
            ],
        )
        assert is_faits_divers_cluster(cluster)

    def test_non_faits_divers(self):
        cluster = _make(titles=["Climat G20", "Accord Paris", "Émissions CO2"])
        assert not is_faits_divers_cluster(cluster)


class TestCapLowPriorityClusters:
    def test_multiple_sport_capped_to_one(self):
        sport_a = _make(theme="sport", titles=["PSG OM"], source_count=5)
        sport_b = _make(theme="sport", titles=["Tennis"], source_count=4)
        sport_c = _make(theme="sport", titles=["Rugby"], source_count=3)
        politics = _make(theme="politics", titles=["Élections"], source_count=6)
        economy = _make(theme="economy", titles=["Inflation"], source_count=5)

        kept = cap_low_priority_clusters([sport_a, sport_b, sport_c, politics, economy])

        ids = [c.cluster_id for c in kept]
        assert sport_a.cluster_id in ids  # first sport kept
        assert sport_b.cluster_id not in ids  # second sport dropped
        assert sport_c.cluster_id not in ids  # third sport dropped
        assert politics.cluster_id in ids
        assert economy.cluster_id in ids

    def test_multiple_faits_divers_capped_to_one(self):
        fd_a = _make(
            titles=["Accident mortel", "Incendie", "Braquage"], source_count=5
        )
        fd_b = _make(titles=["Accident", "Incendie", "Collision"], source_count=4)
        politics = _make(theme="politics", titles=["Réforme"], source_count=3)

        kept = cap_low_priority_clusters([fd_a, fd_b, politics])
        ids = [c.cluster_id for c in kept]
        assert fd_a.cluster_id in ids
        assert fd_b.cluster_id not in ids
        assert politics.cluster_id in ids

    def test_non_low_priority_all_kept(self):
        clusters = [
            _make(theme="politics", titles=["a"]),
            _make(theme="economy", titles=["b"]),
            _make(theme="tech", titles=["c"]),
            _make(theme="science", titles=["d"]),
        ]
        kept = cap_low_priority_clusters(clusters)
        assert len(kept) == 4

    def test_one_sport_one_faits_divers_both_pass(self):
        sport = _make(theme="sport", titles=["PSG"], source_count=3)
        fd = _make(titles=["Accident mortel", "Incendie"], source_count=2)
        politics = _make(theme="politics", titles=["x"])
        kept = cap_low_priority_clusters([sport, fd, politics])
        assert len(kept) == 3

    def test_order_preserved(self):
        a = _make(theme="politics", titles=["a"])
        b = _make(theme="sport", titles=["b"])
        c = _make(theme="economy", titles=["c"])
        kept = cap_low_priority_clusters([a, b, c])
        assert [k.cluster_id for k in kept] == [a.cluster_id, b.cluster_id, c.cluster_id]

    def test_custom_caps(self):
        sport_a = _make(theme="sport", titles=["a"])
        sport_b = _make(theme="sport", titles=["b"])
        kept = cap_low_priority_clusters([sport_a, sport_b], max_sport=2)
        assert len(kept) == 2
