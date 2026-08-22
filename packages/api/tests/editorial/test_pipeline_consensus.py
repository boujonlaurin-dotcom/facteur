"""Câblage et persistance de l'analyse des angles 6C (Story 35.1).

Deux niveaux :
- le **câblage** dans l'étape 3C (un seul appel, ce qui part en base, ce que
  voit le digest) — sur mocks ;
- la **persistance** (upsert idempotent, liens articles) — contre la DB de test,
  parce que l'`ON CONFLICT` est justement ce qu'un mock ne prouve pas.
"""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.models.content import Content
from app.models.coverage_analysis import CoverageAnalysis, CoverageAnalysisArticle
from app.models.enums import ContentType
from app.services.editorial.consensus import (
    ConsensusPayload,
    coerce_analysis_text,
    normalize_consensus,
)
from app.services.editorial.pipeline import (
    EditorialPipelineService,
    _collect_subject_content_ids,
)
from app.services.perspective_service import Perspective
from app.services.title_annotation_service import TitleAnnotationService
from tests.editorial.factories import _make_cluster_mock, _make_content_mock

# Le pipeline dérive `subject_key` de la signature de composition de cluster
# partagée ; les tests s'y réfèrent par le même chemin que le code.
_subject_key = TitleAnnotationService.compute_cluster_signature

LLM_RESULT = {
    "analysis": "Ce qui est établi.\n\n→ **L'origine** : A dit ceci ; B dit cela.",
    "divergence_level": "high",
    "agreements": [
        {
            "text": "Le budget 2026 prévoit 12 milliards d'économies.",
            "source_domains": ["cluster.fr", "left.fr", "right.fr"],
        }
    ],
    "disagreements": [
        {
            "text": "L'origine du déficit : dépenses sociales ou recettes.",
            "source_domains": ["left.fr", "right.fr"],
        }
    ],
    "cta_agreement": {"text": "12 milliards d'économies."},
    "cta_disagreement": {"text": "L'origine du déficit : dépenses ou recettes."},
}


def _perspective(bias, name, domain, content_id=None):
    """Perspective de couverture minimale (Google News = sans `content_id`)."""
    return Perspective(
        title=f"{name} title",
        url=f"https://{domain}/a",
        source_name=name,
        source_domain=domain,
        bias_stance=bias,
        language="fr",
        content_id=content_id,
    )


# --- Helpers purs ---------------------------------------------------------


class TestSubjectKey:
    """Les deux invariants dont dépend l'idempotence de `coverage_analyses`.

    La fonction est partagée avec l'annotation LLM des titres ; on les réaffirme
    ici parce que c'est ce lot qui en fait une **clé unique** en base.
    """

    def test_key_is_stable_whatever_the_order(self):
        a, b, c = uuid4(), uuid4(), uuid4()

        assert _subject_key([a, b, c]) == _subject_key([c, a, b])

    def test_key_changes_with_the_article_set(self):
        a, b = uuid4(), uuid4()

        assert _subject_key([a]) != _subject_key([a, b])


class TestCollectContentIds:
    def test_pivot_first_then_internal_articles_only(self):
        pivot = uuid4()
        internal = uuid4()
        perspectives = [
            _perspective("left", "L", "left.fr", content_id=str(internal)),
            # Google News : pas de ligne `contents`, donc pas de lien FK possible.
            _perspective("right", "R", "right.fr"),
        ]

        assert _collect_subject_content_ids(perspectives, pivot) == [pivot, internal]

    def test_pivot_is_not_duplicated_by_its_own_perspective(self):
        pivot = uuid4()
        perspectives = [
            _perspective("center", "C", "cluster.fr", content_id=str(pivot))
        ]

        assert _collect_subject_content_ids(perspectives, pivot) == [pivot]

    def test_unparseable_ids_are_skipped(self):
        pivot = uuid4()
        perspectives = [_perspective("left", "L", "left.fr", content_id="not-a-uuid")]

        assert _collect_subject_content_ids(perspectives, pivot) == [pivot]


class TestCoerceAnalysisText:
    def test_nested_dict_is_flattened(self):
        """Sentry PYTHON-R : un dict imbriqué ferait un 500 sur /digest/both."""
        result = coerce_analysis_text({"contexte": "x", "liens": [1]})

        assert isinstance(result, str)
        assert "contexte" in result

    def test_string_and_none_pass_through(self):
        assert coerce_analysis_text("texte") == "texte"
        assert coerce_analysis_text(None) is None


# --- Câblage étape 3C -----------------------------------------------------


class TestConsensusWiring:
    """Un sujet à 2 alternatives (le nouveau seuil) traversant le pipeline."""

    async def _run(
        self,
        mock_dependencies,
        *,
        svc=None,
        llm_result=LLM_RESULT,
        content=None,
        extra_contents=(),
    ):
        if content is None:
            content = _make_content_mock(title="article")
            content.published_at = datetime(2026, 4, 12, tzinfo=UTC)
            content.source.url = ""
            content.url = "https://www.cluster.fr/a"

        cluster_id_str = str(uuid4())
        cluster = _make_cluster_mock(
            cluster_id=cluster_id_str,
            label="Retraites",
            contents=[content, *extra_contents],
        )

        async def _resolve(domain: str, source_name: str | None = None) -> str:
            return {
                "cluster.fr": "center",
                "left.fr": "left",
                "right.fr": "right",
            }.get(domain, "unknown")

        mock_dependencies["perspective"].resolve_bias = AsyncMock(side_effect=_resolve)
        mock_dependencies["perspective"].get_perspectives_hybrid = AsyncMock(
            return_value=(
                [
                    _perspective("left", "L", "left.fr"),
                    _perspective("right", "R", "right.fr"),
                ],
                [],
            )
        )
        # On règle le retour sans remplacer le mock du fixture : `await_count`
        # doit survivre à deux passages (test de mutualisation).
        mock_dependencies["perspective"].analyze_consensus.return_value = llm_result

        if svc is None:
            session = AsyncMock()
            session.execute = AsyncMock(
                return_value=MagicMock(all=MagicMock(return_value=[]))
            )
            svc = EditorialPipelineService(session)

        from app.services.editorial.schemas import SelectedTopic

        with patch(
            "app.services.editorial.pipeline.ImportanceDetector"
        ) as mock_detector_cls:
            mock_detector = MagicMock()
            mock_detector.build_topic_clusters.return_value = [cluster]
            mock_detector_cls.return_value = mock_detector

            mock_dependencies["curation"].select_a_la_une.return_value = SelectedTopic(
                topic_id=cluster_id_str,
                label="Retraites",
                selection_reason="Traité par 1 sources",
                deep_angle="D",
                source_count=1,
            )
            mock_dependencies["curation"].select_topics.return_value = []

            def _populate_actus(subjects, clusters, **_kwargs):
                out = []
                for s in subjects:
                    actu = MagicMock()
                    actu.content_id = uuid4()
                    actu.source_id = uuid4()
                    out.append(s.model_copy(update={"actu_article": actu}))
                return out

            mock_dependencies["actu"].match_global.side_effect = _populate_actus

            result = await svc.compute_global_context([content])

        assert result is not None
        return svc, result.subjects[0], content

    @pytest.mark.asyncio
    async def test_digest_block_still_gets_its_markdown(self, mock_dependencies):
        """Le lot ne touche pas au bloc « Analyse Facteur » du digest."""
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", AsyncMock()
        ):
            _, subject, _ = await self._run(mock_dependencies)

        assert subject.divergence_analysis == LLM_RESULT["analysis"]
        assert subject.divergence_level == "high"

    @pytest.mark.asyncio
    async def test_single_llm_call_and_legacy_analyzer_untouched(
        self, mock_dependencies
    ):
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", AsyncMock()
        ):
            await self._run(mock_dependencies)

        assert mock_dependencies["perspective"].analyze_consensus.await_count == 1
        mock_dependencies["perspective"].analyze_divergences.assert_not_awaited()

    @pytest.mark.asyncio
    async def test_llm_receives_the_domains_it_must_attribute_with(
        self, mock_dependencies
    ):
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", AsyncMock()
        ):
            await self._run(mock_dependencies)

        kwargs = mock_dependencies["perspective"].analyze_consensus.await_args.kwargs
        assert kwargs["source_domain"] == "cluster.fr"
        assert {p["source_domain"] for p in kwargs["perspectives"]} == {
            "left.fr",
            "right.fr",
        }

    @pytest.mark.asyncio
    async def test_persisted_payload_is_the_normalized_contract(
        self, mock_dependencies
    ):
        persist = AsyncMock(return_value=uuid4())
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", persist
        ):
            _, subject, content = await self._run(mock_dependencies)

        kwargs = persist.await_args.kwargs
        payload: ConsensusPayload = kwargs["payload"]
        assert payload.state == "available"
        # 1 seul désaccord → varied, même porté par des biais opposés.
        assert payload.qualifier == "varied"
        assert payload.agreements[0].support_count == 3
        assert payload.disagreements[0].source_domains == ["left.fr", "right.fr"]
        assert payload.cta.agreement.text == "12 milliards d'économies."
        # Le CTA hérite de l'attribution du constat complet.
        assert payload.cta.agreement.support_count == 3

        assert kwargs["coverage_count"] == subject.coverage_count == 3
        assert set(kwargs["corpus_domains"]) == {"cluster.fr", "left.fr", "right.fr"}
        # Seul le pivot a une ligne `contents` : les perspectives GNews n'en ont pas.
        assert kwargs["content_ids"] == [content.id]
        assert kwargs["subject_key"] == _subject_key([content.id])

    @pytest.mark.asyncio
    async def test_unusable_llm_output_is_recorded_as_unavailable(
        self, mock_dependencies
    ):
        """Un échec définitif se persiste : sinon le Reader dirait « en cours » à vie."""
        persist = AsyncMock(return_value=uuid4())
        garbage = {"analysis": "texte", "agreements": [], "disagreements": []}
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", persist
        ):
            await self._run(mock_dependencies, llm_result=garbage)

        assert persist.await_args.kwargs["payload"].state == "unavailable"
        assert persist.await_args.kwargs["payload"].qualifier is None

    @pytest.mark.asyncio
    async def test_failed_call_writes_nothing(self, mock_dependencies):
        """Appel raté = transitoire : pas de ligne, le chemin paresseux réessaiera."""
        persist = AsyncMock()
        with patch.object(
            EditorialPipelineService, "_persist_coverage_analysis", persist
        ):
            _, subject, _ = await self._run(mock_dependencies, llm_result=None)

        persist.assert_not_awaited()
        assert subject.divergence_analysis is None
        # Fallback déterministe toujours en place.
        assert subject.divergence_level is not None

    @pytest.mark.asyncio
    async def test_persist_failure_does_not_break_the_digest(self, mock_dependencies):
        with patch.object(
            EditorialPipelineService,
            "_persist_coverage_analysis",
            AsyncMock(side_effect=RuntimeError("db down")),
        ):
            _, subject, _ = await self._run(mock_dependencies)

        assert subject.divergence_analysis == LLM_RESULT["analysis"]
        assert subject.coverage_count == 3

    @pytest.mark.asyncio
    async def test_second_mode_reuses_the_analysis_instead_of_paying_again(
        self, mock_dependencies
    ):
        """Mutualisation `pour_vous` / `serein` : même instance, sujet recoupé.

        Le pool `serein` est un sous-ensemble filtré du pool global : le même
        événement y reforme un cluster voisin, qui partage au moins le pivot.
        """
        analysis_id = uuid4()
        link = AsyncMock()
        with (
            patch.object(
                EditorialPipelineService,
                "_persist_coverage_analysis",
                AsyncMock(return_value=analysis_id),
            ),
            patch.object(
                EditorialPipelineService, "_link_coverage_analysis_articles", link
            ),
        ):
            svc, _, content = await self._run(mock_dependencies)
            _, second_subject, _ = await self._run(
                mock_dependencies, svc=svc, content=content
            )

        # Un seul appel LLM pour les deux passes.
        assert mock_dependencies["perspective"].analyze_consensus.await_count == 1
        # Même jeu d'articles au second passage : aucun lien à poser, donc pas
        # de session ouverte pour un INSERT qui n'insérerait rien.
        link.assert_not_awaited()
        # Le digest du second mode garde son analyse.
        assert second_subject.divergence_analysis == LLM_RESULT["analysis"]
        assert second_subject.divergence_level == "high"

    @pytest.mark.asyncio
    async def test_second_mode_links_only_the_articles_it_adds(self, mock_dependencies):
        """Cluster voisin : seuls les articles nouveaux sont rattachés."""
        analysis_id = uuid4()
        link = AsyncMock()
        with (
            patch.object(
                EditorialPipelineService,
                "_persist_coverage_analysis",
                AsyncMock(return_value=analysis_id),
            ),
            patch.object(
                EditorialPipelineService, "_link_coverage_analysis_articles", link
            ),
        ):
            svc, _, content = await self._run(mock_dependencies)
            # Le second cluster garde le pivot déjà analysé et amène un article
            # de plus — le cas du pool `serein` qui recoupe sans recouvrir.
            newcomer = _make_content_mock(title="autre")
            newcomer.published_at = datetime(2026, 4, 12, tzinfo=UTC)
            newcomer.source.url = ""
            newcomer.url = "https://www.autre.fr/b"
            await self._run(
                mock_dependencies, svc=svc, content=content, extra_contents=[newcomer]
            )

        assert mock_dependencies["perspective"].analyze_consensus.await_count == 1
        link.assert_awaited_once_with(analysis_id, [newcomer.id])


# --- Persistance (DB de test) ---------------------------------------------


async def _make_content_row(db_session, source, title="Article"):
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=f"guid-{uuid4()}",
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
    )
    db_session.add(content)
    await db_session.commit()
    return content


def _payload() -> ConsensusPayload:
    return normalize_consensus(
        {
            "agreements": [
                {"text": "Un accord tenu par deux médias.", "source_domains": ["a.fr"]}
            ]
        },
        ["a.fr"],
    )


class TestPersistence:
    @pytest.mark.asyncio
    async def test_row_and_links_are_written(
        self, db_session, fake_session_maker, test_source
    ):
        svc = EditorialPipelineService(db_session, session_maker=fake_session_maker)
        first = await _make_content_row(db_session, test_source, "A")
        second = await _make_content_row(db_session, test_source, "B")
        content_ids = [first.id, second.id]

        analysis_id = await svc._persist_coverage_analysis(
            subject_key=_subject_key(content_ids),
            payload=_payload(),
            corpus_domains=["a.fr", "b.fr"],
            coverage_count=2,
            content_ids=content_ids,
        )

        row = (
            await db_session.execute(
                select(CoverageAnalysis).where(CoverageAnalysis.id == analysis_id)
            )
        ).scalar_one()
        assert row.state == "available"
        assert row.corpus_domains == ["a.fr", "b.fr"]
        assert row.coverage_count == 2
        assert row.consensus["agreements"][0]["support_count"] == 1
        assert row.model_version.startswith("mistral-large")

        linked = (
            (
                await db_session.execute(
                    select(CoverageAnalysisArticle.content_id).where(
                        CoverageAnalysisArticle.coverage_analysis_id == analysis_id
                    )
                )
            )
            .scalars()
            .all()
        )
        assert set(linked) == set(content_ids)

    @pytest.mark.asyncio
    async def test_rerun_upserts_instead_of_stacking_rows(
        self, db_session, fake_session_maker, test_source
    ):
        """Un re-run du pipeline sur le même cluster réécrit la même ligne."""
        svc = EditorialPipelineService(db_session, session_maker=fake_session_maker)
        content = await _make_content_row(db_session, test_source)
        key = _subject_key([content.id])

        first_id = await svc._persist_coverage_analysis(
            subject_key=key,
            payload=_payload(),
            corpus_domains=["a.fr"],
            coverage_count=2,
            content_ids=[content.id],
        )
        second_id = await svc._persist_coverage_analysis(
            subject_key=key,
            payload=normalize_consensus({}, ["a.fr"]),
            corpus_domains=["a.fr", "c.fr"],
            coverage_count=5,
            content_ids=[content.id],
        )

        assert second_id == first_id
        rows = (
            await db_session.execute(
                select(func.count())
                .select_from(CoverageAnalysis)
                .where(CoverageAnalysis.subject_key == key)
            )
        ).scalar_one()
        assert rows == 1

        row = (
            await db_session.execute(
                select(CoverageAnalysis).where(CoverageAnalysis.id == first_id)
            )
        ).scalar_one()
        assert row.state == "unavailable"
        assert row.coverage_count == 5

        links = (
            await db_session.execute(
                select(func.count())
                .select_from(CoverageAnalysisArticle)
                .where(CoverageAnalysisArticle.coverage_analysis_id == first_id)
            )
        ).scalar_one()
        assert links == 1

    @pytest.mark.asyncio
    async def test_linking_the_second_mode_adds_only_missing_rows(
        self, db_session, fake_session_maker, test_source
    ):
        svc = EditorialPipelineService(db_session, session_maker=fake_session_maker)
        shared = await _make_content_row(db_session, test_source, "shared")
        serein_only = await _make_content_row(db_session, test_source, "serein")

        analysis_id = await svc._persist_coverage_analysis(
            subject_key=_subject_key([shared.id]),
            payload=_payload(),
            corpus_domains=["a.fr"],
            coverage_count=2,
            content_ids=[shared.id],
        )
        await svc._link_coverage_analysis_articles(
            analysis_id, [shared.id, serein_only.id]
        )

        linked = (
            (
                await db_session.execute(
                    select(CoverageAnalysisArticle.content_id).where(
                        CoverageAnalysisArticle.coverage_analysis_id == analysis_id
                    )
                )
            )
            .scalars()
            .all()
        )
        assert sorted(map(str, linked)) == sorted([str(shared.id), str(serein_only.id)])

    @pytest.mark.asyncio
    async def test_reader_resolves_content_to_analysis(
        self, db_session, fake_session_maker, test_source
    ):
        """Le sens de lecture de la PR 2 : `content_id` → analyse, par jointure."""
        svc = EditorialPipelineService(db_session, session_maker=fake_session_maker)
        content = await _make_content_row(db_session, test_source)

        analysis_id = await svc._persist_coverage_analysis(
            subject_key=_subject_key([content.id]),
            payload=_payload(),
            corpus_domains=["a.fr"],
            coverage_count=2,
            content_ids=[content.id],
        )

        found = (
            await db_session.execute(
                select(CoverageAnalysis)
                .join(
                    CoverageAnalysisArticle,
                    CoverageAnalysisArticle.coverage_analysis_id == CoverageAnalysis.id,
                )
                .where(CoverageAnalysisArticle.content_id == content.id)
            )
        ).scalar_one()

        assert found.id == analysis_id
