"""Title annotation service (Story 7.4 — diff highlighting backend).

Computes spaCy "strong tokens" per article title and diffs them against a
reference title to surface divergent wording on the /perspectives panel.
Persists results in `cluster_title_annotations` keyed by
(cluster_id, content_id) so subsequent panel opens read from cache.

Sprint 1 — phase déterministe uniquement (POS + lemmatisation, zéro LLM).
Phase 2 (Mistral-small raffinement) will populate `semantic_equiv` later
without touching existing rows (gated by `model_version`).
"""

import asyncio
import unicodedata
from dataclasses import dataclass, field
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cluster_title_annotation import ClusterTitleAnnotation
from app.models.content import Content
from app.services.ml.ner_service import get_ner_service
from app.services.text_similarity import FRENCH_STOP_WORDS

logger = structlog.get_logger(__name__)

# Sentinel POS value used to mark NER-tagged tokens in the PRIORITY table.
_ENTITY_KEY = "entity"


def _strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn"
    )


@dataclass
class ClusterAnnotations:
    """Container holding both the cached tokens and the URL→content_id map.

    The URL map lets the router resolve a perspective dict (which carries
    `url` but not `content_id`) back to its cluster row, so we can read
    cached tokens instead of recomputing.
    """

    tokens_by_id: dict[UUID, list[dict]] = field(default_factory=dict)
    id_by_url: dict[str, UUID] = field(default_factory=dict)


class TitleAnnotationService:
    MODEL_VERSION = "v1-spacy-fr_md"
    KEEP_POS = frozenset({"NOUN", "PROPN", "ADJ", "VERB"})
    MAX_HIGHLIGHTED_PER_TITLE = 4
    # Lower number = higher priority when capping at MAX_HIGHLIGHTED_PER_TITLE.
    PRIORITY: dict[str, int] = {
        _ENTITY_KEY: 0,
        "ADJ": 1,
        "PROPN": 2,
        "NOUN": 2,
        "VERB": 3,
    }

    def __init__(self):
        self._nlp = get_ner_service().get_nlp()
        if self._nlp is None:
            logger.warning("title_annotation.nlp_unavailable")

    @property
    def is_nlp_available(self) -> bool:
        return self._nlp is not None

    def _doc_to_tokens(self, doc) -> list[dict]:
        """Convert a spaCy Doc into our strong-token shape."""
        if doc is None:
            return []

        ent_at: dict[int, str] = {}
        for ent in doc.ents:
            for char_idx in range(ent.start_char, ent.end_char):
                ent_at[char_idx] = ent.label_

        out: list[dict] = []
        for tok in doc:
            if tok.pos_ not in self.KEEP_POS:
                continue
            if tok.is_stop:
                continue
            text = tok.text
            lemma = (tok.lemma_ or text).lower()
            # FRENCH_STOP_WORDS is accent-stripped, so we must strip too
            # before lookup — otherwise "présente" / "société" slip through.
            if (
                _strip_accents(text.lower()) in FRENCH_STOP_WORDS
                or _strip_accents(lemma) in FRENCH_STOP_WORDS
            ):
                continue
            token: dict = {
                "start": tok.idx,
                "end": tok.idx + len(tok.text),
                "text": text,
                "lemma": lemma,
                "pos": tok.pos_,
            }
            entity_kind = ent_at.get(tok.idx)
            if entity_kind:
                token["entity_kind"] = entity_kind
            out.append(token)
        return out

    def compute_strong_tokens(self, title: str) -> list[dict]:
        """Extract POS-filtered, stop-word-stripped tokens with NER overlay.

        Returns `[{start, end, text, lemma, pos, entity_kind?}]`, where
        `entity_kind` is the spaCy entity label (e.g. "PER", "ORG", "LOC")
        when the token belongs to a NER span, else absent.
        """
        if not self._nlp or not title:
            return []
        try:
            return self._doc_to_tokens(self._nlp(title))
        except Exception:
            logger.exception("title_annotation.spacy_error", title=title[:80])
            return []

    async def compute_strong_tokens_batch(self, titles: list[str]) -> list[list[dict]]:
        """Batch-compute tokens for many titles in a single executor hop.

        spaCy is sync/CPU-bound — running 8 separate `nlp()` calls on the
        event loop blocks it for ~40-120 ms. `nlp.pipe()` processes them
        together in a single thread submission, ~2-3× faster.
        """
        if not titles:
            return []
        if not self._nlp:
            return [[] for _ in titles]
        loop = asyncio.get_event_loop()
        docs = await loop.run_in_executor(None, lambda: list(self._nlp.pipe(titles)))
        return [self._doc_to_tokens(doc) for doc in docs]

    def diff_spans(
        self, ref_tokens: list[dict], alt_tokens: list[dict], alt_bias: str
    ) -> list[dict]:
        """Return spans of `alt_tokens` whose lemma is absent from `ref_tokens`.

        Capped at `MAX_HIGHLIGHTED_PER_TITLE`, ordered by PRIORITY (entities
        first, then ADJ, then NOUN/PROPN, then VERB). `alt_bias` is passed
        through unchanged to each span as `bias` — the Dart side maps it to
        a color via `getBiasColor`.
        """
        ref_lemmas = {t["lemma"] for t in ref_tokens}
        divergent = [t for t in alt_tokens if t["lemma"] not in ref_lemmas]
        ranked = sorted(
            divergent,
            key=lambda t: self.PRIORITY.get(
                _ENTITY_KEY if t.get("entity_kind") else t["pos"], 99
            ),
        )
        return [
            {
                "start": t["start"],
                "end": t["end"],
                "text": t["text"],
                "bias": alt_bias,
            }
            for t in ranked[: self.MAX_HIGHLIGHTED_PER_TITLE]
        ]

    def compute_shared_tokens(
        self, ref_tokens: list[dict], alt_tokens: list[dict]
    ) -> list[dict]:
        """Return spans of `alt_tokens` whose lemma IS present in `ref_tokens`.

        Symmetric to `diff_spans`: same lemma comparison, opposite filter,
        no cap (the front wants every shared token rendered in tertiary so
        the diff visualisation stays coherent). Preserves the alt token
        ordering. Each span is `{start, end, text}` — no bias, no pos.
        """
        ref_lemmas = {t["lemma"] for t in ref_tokens}
        return [
            {"start": t["start"], "end": t["end"], "text": t["text"]}
            for t in alt_tokens
            if t["lemma"] in ref_lemmas
        ]

    def compute_reference_pivot(self, ref_tokens: list[dict]) -> dict | None:
        """Return the first VERB span in `ref_tokens` as `{start, end, text}`.

        Used by the hi-fi `cm-ref-inline` block to render the reference
        title's pivot verb with a grey wash. Falls back to `None` when no
        verb is found — the front then renders the title without wash.
        """
        for t in ref_tokens:
            if t.get("pos") == "VERB":
                return {"start": t["start"], "end": t["end"], "text": t["text"]}
        return None

    async def get_or_compute_cluster_annotations(
        self, db: AsyncSession, cluster_id: UUID
    ) -> ClusterAnnotations:
        """Return tokens for every content in `cluster_id`, computing missing ones.

        Flow:
          1. Fetch the cluster's contents (id, title, url).
          2. Read existing rows for (cluster_id, MODEL_VERSION).
          3. For missing content_ids, compute strong_tokens (batched via
             `nlp.pipe()`) and INSERT … ON CONFLICT DO NOTHING.
          4. Return the merged map + URL→id lookup.
        """
        out = ClusterAnnotations()

        cluster_stmt = select(Content.id, Content.title, Content.url).where(
            Content.cluster_id == cluster_id
        )
        cluster_rows = (await db.execute(cluster_stmt)).all()
        if not cluster_rows:
            return out

        titles_by_id: dict[UUID, str] = {}
        for row in cluster_rows:
            titles_by_id[row.id] = row.title or ""
            if row.url:
                out.id_by_url[row.url] = row.id

        cache_stmt = select(
            ClusterTitleAnnotation.content_id,
            ClusterTitleAnnotation.strong_tokens,
        ).where(
            ClusterTitleAnnotation.cluster_id == cluster_id,
            ClusterTitleAnnotation.model_version == self.MODEL_VERSION,
        )
        for row in (await db.execute(cache_stmt)).all():
            out.tokens_by_id[row.content_id] = list(row.strong_tokens or [])

        missing_ids = [cid for cid in titles_by_id if cid not in out.tokens_by_id]
        if not missing_ids:
            return out

        logger.info(
            "diff_highlighting.cache_miss",
            cluster_id=str(cluster_id),
            missing=len(missing_ids),
            total=len(titles_by_id),
        )

        if self._nlp is None:
            return out

        missing_titles = [titles_by_id[cid] for cid in missing_ids]
        tokens_per_title = await self.compute_strong_tokens_batch(missing_titles)

        rows_to_insert: list[dict] = []
        for cid, tokens in zip(missing_ids, tokens_per_title, strict=True):
            out.tokens_by_id[cid] = tokens
            rows_to_insert.append(
                {
                    "cluster_id": cluster_id,
                    "content_id": cid,
                    "strong_tokens": tokens,
                    "semantic_equiv": None,
                    "model_version": self.MODEL_VERSION,
                }
            )

        # ON CONFLICT DO NOTHING: two concurrent panel opens on the same
        # cluster both compute, one wins the INSERT, the other's rows are
        # silently dropped from DB but still returned in-memory — both
        # tabs see a self-consistent result.
        try:
            stmt = pg_insert(ClusterTitleAnnotation).values(rows_to_insert)
            stmt = stmt.on_conflict_do_nothing(
                index_elements=["cluster_id", "content_id"]
            )
            await db.execute(stmt)
            await db.commit()
        except Exception:
            await db.rollback()
            logger.exception(
                "title_annotation.cache_insert_failed",
                cluster_id=str(cluster_id),
            )

        return out


_title_annotation_service: TitleAnnotationService | None = None


def get_title_annotation_service() -> TitleAnnotationService:
    """Return the process-wide singleton (lazy-initialized)."""
    global _title_annotation_service
    if _title_annotation_service is None:
        _title_annotation_service = TitleAnnotationService()
    return _title_annotation_service


def reset_title_annotation_service() -> None:
    """Drop the cached singleton — for tests that swap the NER model."""
    global _title_annotation_service
    _title_annotation_service = None
