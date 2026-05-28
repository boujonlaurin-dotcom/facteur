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
    is_denylisted_editorial_source,
    is_faits_divers_cluster,
    is_news_bulletin_title,
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


class TestIsNewsBulletinTitle:
    """Story 9.4 — exclusion des bulletins radio / chroniques régulières."""

    def test_journal_de_8h_uppercase(self):
        assert is_news_bulletin_title("JOURNAL DE 8H du lundi 25 mai 2026")

    def test_journal_de_8h_lowercase(self):
        assert is_news_bulletin_title("Journal de 8h du lundi 25 mai 2026")

    def test_journal_de_13h(self):
        assert is_news_bulletin_title("Journal de 13h - édition du 24/05")

    def test_le_7_9_tranche(self):
        assert is_news_bulletin_title("Le 7/9 du 25 mai : invités politiques")

    def test_le_18_20(self):
        assert is_news_bulletin_title("Le 18/20 — points clés")

    def test_chronique_du_at_start(self):
        assert is_news_bulletin_title("Avec Sciences, chronique du lundi 25 mai 2026")

    def test_jt_de_20h(self):
        assert is_news_bulletin_title("JT de 20h du 24 mai")

    def test_revue_de_presse(self):
        assert is_news_bulletin_title("Revue de presse internationale")

    def test_chronique_in_middle_not_bulletin(self):
        """Faux-positif à éviter : « chronique du conflit » en milieu de phrase
        n'est PAS un bulletin (le pattern est ancré début/30 premiers chars)."""
        assert not is_news_bulletin_title(
            "Une chronique du conflit israélo-palestinien après deux ans de guerre"
        )

    def test_regular_article_not_bulletin(self):
        assert not is_news_bulletin_title(
            "Macron annonce une réforme des retraites lundi"
        )

    def test_empty_or_none(self):
        assert not is_news_bulletin_title(None)
        assert not is_news_bulletin_title("")

    # --- Patterns ajoutés pour bug-pipeline-non-editorial-articles ---

    def test_journal_rtl_without_le(self):
        assert is_news_bulletin_title("Journal RTL du 25 mai 2026")

    def test_journal_rfi(self):
        assert is_news_bulletin_title("Journal RFI - édition de 12h")

    def test_journal_bfm(self):
        assert is_news_bulletin_title("Journal BFM : les titres du jour")

    def test_l_emission_apostrophe(self):
        assert is_news_bulletin_title("L'émission politique de France 2")

    def test_l_emission_typographic_apostrophe(self):
        assert is_news_bulletin_title("L’Émission du soir")

    def test_ma_chronique(self):
        assert is_news_bulletin_title("Ma chronique du lundi")

    def test_la_chronique_de(self):
        assert is_news_bulletin_title("La chronique de Nicolas Demorand")

    def test_notre_chronique(self):
        assert is_news_bulletin_title("Notre chronique éco du matin")

    def test_chronique_colon(self):
        assert is_news_bulletin_title("Chronique: l'économie de la semaine")

    def test_chronique_em_dash(self):
        assert is_news_bulletin_title("Chronique – bilan de semaine")

    def test_une_chronique_du_conflit_not_matched(self):
        """« Une » n'est pas un possessif → ne doit pas matcher le pattern."""
        assert not is_news_bulletin_title(
            "Une chronique du conflit israélo-palestinien après deux ans de guerre"
        )

    def test_emission_in_middle_not_matched(self):
        """« émission » en milieu de phrase n'est pas un bulletin."""
        assert not is_news_bulletin_title(
            "Une nouvelle émission de Radio France pour les jeunes"
        )

    # --- Repasse Essentiel 2026-05-27 : chroniques France Culture ---

    def test_humeur_du_jour_emission_du_mercredi(self):
        """« L'humeur du jour, émission du mercredi 27 mai 2026 » — chronique
        quotidienne France Culture passée à travers le filtre avant repasse."""
        assert is_news_bulletin_title(
            "L'humeur du jour, émission du mercredi 27 mai 2026"
        )

    def test_revue_de_presse_internationale_emission_du_lundi(self):
        """« La revue de presse internationale, émission du lundi 25 mai 2026 »
        — chronique France Culture, non matchée par `^revue de presse` à cause
        du préfixe « La ». Doit l'être désormais."""
        assert is_news_bulletin_title(
            "La revue de presse internationale, émission du lundi 25 mai 2026"
        )

    def test_humeur_du_jour_short(self):
        """Forme courte sans suffixe d'édition — chronique matinale."""
        assert is_news_bulletin_title("L'humeur du jour")

    def test_idee_du_jour(self):
        """Variante France Inter / France Culture."""
        assert is_news_bulletin_title("L'idée du jour")

    def test_la_matinale(self):
        """« La matinale du 27 mai » — chronique régulière."""
        assert is_news_bulletin_title("La matinale du 27 mai")

    def test_revue_d_un_livre_not_matched(self):
        """Régression : « La revue d'un livre… » n'est pas dans la liste
        fermée (revue de presse / matinale / humeur du jour / invité) et
        ne doit donc pas matcher."""
        assert not is_news_bulletin_title("La revue d'un livre de Camus")

    def test_l_emission_du_president(self):
        """Régression : la forme « L'émission du <x> » reste matchée par le
        pattern historique `^l['émission`."""
        assert is_news_bulletin_title(
            "L'émission du président qu'il faut écouter"
        )


class TestIsDenylistedEditorialSource:
    """Sources bloquées du top 10 éditorial."""

    @dataclass
    class _FakeSource:
        name: str | None = None

    @dataclass
    class _FakeContentWithSource:
        title: str | None = None
        source: object | None = None

    def test_frandroid_source_denylisted(self):
        content = self._FakeContentWithSource(
            title="Bouygues fête ses 30 ans",
            source=self._FakeSource(name="Frandroid"),
        )
        assert is_denylisted_editorial_source(content)

    def test_frandroid_casing_variations(self):
        for name in ("FRANDROID", "frandroid", "Frandroid.com"):
            content = self._FakeContentWithSource(
                title="x", source=self._FakeSource(name=name)
            )
            assert is_denylisted_editorial_source(content), f"failed for {name}"

    def test_le_monde_not_denylisted(self):
        content = self._FakeContentWithSource(
            title="x", source=self._FakeSource(name="Le Monde")
        )
        assert not is_denylisted_editorial_source(content)

    def test_no_source_returns_false(self):
        content = self._FakeContentWithSource(title="x", source=None)
        assert not is_denylisted_editorial_source(content)

    def test_source_with_none_name(self):
        content = self._FakeContentWithSource(
            title="x", source=self._FakeSource(name=None)
        )
        assert not is_denylisted_editorial_source(content)
