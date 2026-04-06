"""ÉTAPE 4-5-6 — Editorial writing, pépite selection, coup de coeur.

Story 10.24: Fills all null editorial text fields via LLM + DB query.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.services.editorial.config import EditorialConfig
from app.services.editorial.llm_client import EditorialLLMClient
from app.services.editorial.schemas import (
    CoupDeCoeurArticle,
    EditorialSubject,
    PepiteArticle,
    SubjectWriting,
    WritingOutput,
)

logger = structlog.get_logger()


class EditorialWriterService:
    """ÉTAPE 4-5-6 — LLM editorial writing + pépite + coup de coeur."""

    def __init__(
        self,
        session: AsyncSession,
        llm: EditorialLLMClient,
        config: EditorialConfig,
    ) -> None:
        self._session = session
        self._llm = llm
        self._config = config

    # ------------------------------------------------------------------
    # ÉTAPE 4: Editorial writing (1 LLM call)
    # ------------------------------------------------------------------

    async def write_editorial(
        self,
        subjects: list[EditorialSubject],
        mode: str = "pour_vous",
    ) -> WritingOutput | None:
        """Generate all editorial texts via 1 LLM call.

        Returns WritingOutput with header, 3 intros, 2 transitions, closure, cta.
        Returns None on failure (graceful degradation).
        """
        prompt_cfg = (
            self._config.writing_serene_prompt
            if mode == "serein"
            else self._config.writing_prompt
        )

        if not prompt_cfg.system:
            logger.warning("editorial_writer.no_prompt", mode=mode)
            return None

        # Build user message with subject data for the LLM
        subjects_data = []
        for s in subjects:
            actu = None
            if s.actu_article:
                actu = {
                    "title": s.actu_article.title,
                    "source_name": s.actu_article.source_name,
                }
            deep = None
            if s.deep_article:
                deep = {
                    "title": s.deep_article.title,
                    "source_name": s.deep_article.source_name,
                    "description": (s.deep_article.description or "")[:300],
                }
            subjects_data.append(
                {
                    "topic_id": s.topic_id,
                    "rank": s.rank,
                    "label": s.label,
                    "deep_angle": s.deep_angle,
                    "actu_article": actu,
                    "deep_article": deep,
                }
            )

        # Pass the day name so the LLM can write "Votre essentiel du mardi"
        _JOURS_FR = {
            0: "lundi",
            1: "mardi",
            2: "mercredi",
            3: "jeudi",
            4: "vendredi",
            5: "samedi",
            6: "dimanche",
        }
        day_name = _JOURS_FR[datetime.now(UTC).weekday()]

        user_message = (
            f"Jour : {day_name}\n\n"
            "Voici les 5 sujets du jour avec leurs articles :\n\n"
            f"{json.dumps(subjects_data, ensure_ascii=False, indent=2)}\n\n"
            "Génère le texte éditorial au format JSON."
        )

        raw = await self._llm.chat_json(
            system=prompt_cfg.system,
            user_message=user_message,
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
        )

        if not raw or not isinstance(raw, dict):
            logger.warning("editorial_writer.writing_failed", mode=mode)
            return None

        try:
            raw_subjects = raw.get("subjects", [])
            subject_writings = [
                SubjectWriting(
                    topic_id=s.get("topic_id", ""),
                    intro_text=s.get("intro_text", ""),
                    transition_text=s.get("transition_text"),
                )
                for s in raw_subjects
                if s.get("topic_id") and s.get("intro_text")
            ]

            if not subject_writings:
                logger.warning("editorial_writer.no_subjects_in_output")
                return None

            return WritingOutput(
                header_text=raw.get("header_text", ""),
                subjects=subject_writings,
                closure_text=raw.get("closure_text", "Bonne lecture !"),
                cta_text=raw.get("cta_text"),
            )
        except Exception:
            logger.exception("editorial_writer.parse_failed")
            return None

    # ------------------------------------------------------------------
    # ÉTAPE 5: Pépite selection (1 LLM call)
    # ------------------------------------------------------------------

    async def select_pepite(
        self,
        candidates: list[Content],
        excluded_topic_ids: set[str],
        cluster_data: list[dict],
    ) -> PepiteArticle | None:
        """Select a pépite article via LLM.

        Filters out articles belonging to the 3 selected topic clusters.
        Returns PepiteArticle or None on failure.
        """
        prompt_cfg = self._config.pepite_prompt
        if not prompt_cfg.system:
            logger.warning("editorial_writer.no_pepite_prompt")
            return None

        # Collect content_ids belonging to selected topics
        topic_content_ids: set[str] = set()
        for cluster in cluster_data:
            if cluster.get("cluster_id") in excluded_topic_ids:
                topic_content_ids.update(cluster.get("content_ids", []))

        # Filter eligible candidates
        eligible = [
            c
            for c in candidates
            if str(c.id) not in topic_content_ids and c.published_at is not None
        ]

        # Sort by recency, take top 15
        eligible.sort(key=lambda c: c.published_at, reverse=True)
        eligible = eligible[:15]

        if not eligible:
            logger.info("editorial_writer.no_pepite_candidates")
            return None

        # Build user message
        # Include topic labels so LLM can avoid overlap
        topic_labels = [
            cluster.get("label", "")
            for cluster in cluster_data
            if cluster.get("cluster_id") in excluded_topic_ids
        ]

        candidates_data = [
            {
                "content_id": str(c.id),
                "title": c.title,
                "source_name": c.source.name
                if hasattr(c, "source") and c.source
                else "Source inconnue",
                "description": (c.description or "")[:200],
            }
            for c in eligible
        ]

        user_message = (
            f"Sujets du jour (à éviter) : {json.dumps(topic_labels, ensure_ascii=False)}\n\n"
            "Articles candidats pour la pépite :\n\n"
            f"{json.dumps(candidates_data, ensure_ascii=False, indent=2)}"
        )

        raw = await self._llm.chat_json(
            system=prompt_cfg.system,
            user_message=user_message,
            model=prompt_cfg.model,
            temperature=prompt_cfg.temperature,
            max_tokens=prompt_cfg.max_tokens,
        )

        if not raw or not isinstance(raw, dict):
            logger.warning("editorial_writer.pepite_llm_failed")
            return None

        content_id_str = raw.get("selected_content_id")
        mini_editorial = raw.get("mini_editorial")

        if not content_id_str or not mini_editorial:
            logger.info("editorial_writer.no_pepite_selected")
            return None

        # Validate content_id exists in candidates
        try:
            content_id = UUID(content_id_str)
        except (ValueError, TypeError):
            logger.warning(
                "editorial_writer.pepite_invalid_id", content_id=content_id_str
            )
            return None

        if not any(c.id == content_id for c in eligible):
            # Fallback: try prefix match (LLM may have truncated UUID)
            prefix = content_id_str[:8]
            match = next((c for c in eligible if str(c.id).startswith(prefix)), None)
            if match:
                content_id = match.id
                logger.warning(
                    "editorial_writer.pepite_prefix_match",
                    original=content_id_str,
                    matched=str(content_id),
                )
            else:
                # Last resort: pick most recent eligible article
                content_id = eligible[0].id
                logger.warning(
                    "editorial_writer.pepite_fallback_first",
                    original=content_id_str,
                    fallback=str(content_id),
                )

        return PepiteArticle(content_id=content_id, mini_editorial=mini_editorial)

    # ------------------------------------------------------------------
    # ÉTAPE 6: Coup de coeur (DB query, no LLM)
    # ------------------------------------------------------------------

    async def get_coup_de_coeur(
        self,
        excluded_content_ids: set[UUID],
    ) -> CoupDeCoeurArticle | None:
        """Get most-saved article by community in last 7 days.

        No LLM — pure DB query on UserContentStatus.is_saved.
        Minimum 2 saves required to surface.
        """
        fourteen_days_ago = datetime.now(UTC) - timedelta(days=14)

        # Build exclusion filter
        exclusion_filter = (
            Content.id.notin_(excluded_content_ids) if excluded_content_ids else True
        )

        stmt = (
            select(
                Content.id,
                Content.title,
                func.count(UserContentStatus.id).label("save_count"),
            )
            .join(UserContentStatus, UserContentStatus.content_id == Content.id)
            .where(
                UserContentStatus.is_saved.is_(True),
                UserContentStatus.saved_at >= fourteen_days_ago,
                exclusion_filter,
            )
            .group_by(Content.id, Content.title)
            .order_by(func.count(UserContentStatus.id).desc())
            .limit(1)
        )

        result = await self._session.execute(stmt)
        row = result.first()

        if not row or row.save_count < 1:
            logger.info(
                "editorial_writer.no_coup_de_coeur",
                save_count=row.save_count if row else 0,
            )
            return None

        # Get source name via relationship
        content_stmt = (
            select(Content)
            .where(Content.id == row.id)
            .options(selectinload(Content.source))
        )
        content_result = await self._session.execute(content_stmt)
        content = content_result.scalar_one_or_none()

        source_name = (
            content.source.name if content and content.source else "Source inconnue"
        )

        return CoupDeCoeurArticle(
            content_id=row.id,
            title=row.title,
            source_name=source_name,
            save_count=row.save_count,
        )
