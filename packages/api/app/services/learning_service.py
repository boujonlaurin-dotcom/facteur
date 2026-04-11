"""Service pour le Learning Checkpoint (Epic 13).

Calcul des signaux d'engagement, generation et application des propositions.
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import delete, func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.learning import UserEntityPreference, UserLearningProposal
from app.models.source import Source, UserSource

logger = structlog.get_logger()

# --- Constants ---
SIGNAL_WINDOW_DAYS = 7
SIGNAL_THRESHOLD_SOURCE = 0.15
SIGNAL_THRESHOLD_ENTITY_MUTE = 5
SIGNAL_THRESHOLD_ENTITY_FOLLOW = 5
CHECKPOINT_MIN_PROPOSALS = 2
CHECKPOINT_MAX_PROPOSALS = 4
CHECKPOINT_DISMISS_AFTER = 3


class LearningService:
    """Moteur d'apprentissage : signaux, propositions, application."""

    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------------
    # Signal Computation (Story 13.1)
    # ------------------------------------------------------------------

    async def _compute_source_signals(
        self, user_id: UUID, cutoff: datetime
    ) -> list[dict]:
        """Calcule les ratios d'engagement par source sur la fenetre glissante.

        Returns list of dicts with keys:
            source_id, source_name, impressions, interactions, ratio, current_multiplier
        """
        # Subquery: count impressions per source (articles shown to user)
        impressions_sq = (
            select(
                Content.source_id,
                func.count().label("impressions"),
            )
            .join(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == user_id),
            )
            .where(
                UserContentStatus.last_impressed_at >= cutoff,
            )
            .group_by(Content.source_id)
            .subquery()
        )

        # Subquery: count interactions per source (clicked, saved, or deep-read)
        interactions_sq = (
            select(
                Content.source_id,
                func.count().label("interactions"),
            )
            .join(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == user_id),
            )
            .where(
                UserContentStatus.last_impressed_at >= cutoff,
                (
                    (UserContentStatus.status.in_([ContentStatus.SEEN.value, ContentStatus.CONSUMED.value]))
                    | (UserContentStatus.is_saved.is_(True))
                    | (UserContentStatus.reading_progress > 80)
                ),
            )
            .group_by(Content.source_id)
            .subquery()
        )

        # Join with UserSource to get current multiplier + Source for name
        stmt = (
            select(
                impressions_sq.c.source_id,
                Source.name.label("source_name"),
                impressions_sq.c.impressions,
                func.coalesce(interactions_sq.c.interactions, 0).label("interactions"),
                UserSource.priority_multiplier,
            )
            .join(Source, Source.id == impressions_sq.c.source_id)
            .join(
                UserSource,
                (UserSource.source_id == impressions_sq.c.source_id)
                & (UserSource.user_id == user_id),
            )
            .outerjoin(
                interactions_sq,
                interactions_sq.c.source_id == impressions_sq.c.source_id,
            )
            .where(impressions_sq.c.impressions >= 3)  # Min 3 impressions for signal
        )

        result = await self.db.execute(stmt)
        rows = result.all()

        signals = []
        for row in rows:
            impressions = row.impressions
            interactions = row.interactions
            ratio = interactions / impressions if impressions > 0 else 0.0
            signals.append(
                {
                    "source_id": row.source_id,
                    "source_name": row.source_name,
                    "impressions": impressions,
                    "interactions": interactions,
                    "ratio": ratio,
                    "current_multiplier": row.priority_multiplier,
                }
            )

        return signals

    async def _compute_entity_signals(
        self, user_id: UUID, cutoff: datetime
    ) -> list[dict]:
        """Calcule les signaux d'engagement par entite nommee.

        Returns list of dicts with keys:
            entity_name, articles_shown, articles_clicked
        """
        # Get all content with entities that user has been impressed with
        stmt = (
            select(
                Content.id,
                Content.entities,
                UserContentStatus.status,
                UserContentStatus.is_saved,
                UserContentStatus.reading_progress,
            )
            .join(
                UserContentStatus,
                (UserContentStatus.content_id == Content.id)
                & (UserContentStatus.user_id == user_id),
            )
            .where(
                UserContentStatus.last_impressed_at >= cutoff,
                Content.entities.isnot(None),
            )
        )

        result = await self.db.execute(stmt)
        rows = result.all()

        # Aggregate per entity
        entity_stats: dict[str, dict] = {}
        for row in rows:
            if not row.entities:
                continue
            is_interaction = (
                row.status in (ContentStatus.SEEN.value, ContentStatus.CONSUMED.value)
                or row.is_saved
                or (row.reading_progress and row.reading_progress > 80)
            )
            for entity_name in row.entities:
                name = entity_name.strip()
                if not name or len(name) < 2:
                    continue
                if name not in entity_stats:
                    entity_stats[name] = {"articles_shown": 0, "articles_clicked": 0}
                entity_stats[name]["articles_shown"] += 1
                if is_interaction:
                    entity_stats[name]["articles_clicked"] += 1

        # Filter: only entities with >= 5 articles shown
        return [
            {"entity_name": name, **stats}
            for name, stats in entity_stats.items()
            if stats["articles_shown"] >= SIGNAL_THRESHOLD_ENTITY_MUTE
        ]

    # ------------------------------------------------------------------
    # Proposals Generation (Story 13.2)
    # ------------------------------------------------------------------

    async def generate_proposals(self, user_id: UUID) -> list[UserLearningProposal]:
        """Genere les propositions d'ajustement pour un utilisateur.

        - Expire les anciennes propositions pending (> window)
        - Calcule les signaux source + entite
        - Cree les nouvelles propositions (max CHECKPOINT_MAX_PROPOSALS)
        - Diversifie les types
        """
        cutoff = datetime.now(UTC) - timedelta(days=SIGNAL_WINDOW_DAYS)

        # 1. Expire old pending proposals
        await self.db.execute(
            update(UserLearningProposal)
            .where(
                UserLearningProposal.user_id == user_id,
                UserLearningProposal.status == "pending",
                UserLearningProposal.computed_at < cutoff,
            )
            .values(status="expired", resolved_at=datetime.now(UTC))
        )

        # 2. Dismiss over-shown proposals
        await self.db.execute(
            update(UserLearningProposal)
            .where(
                UserLearningProposal.user_id == user_id,
                UserLearningProposal.status == "pending",
                UserLearningProposal.shown_count >= CHECKPOINT_DISMISS_AFTER,
            )
            .values(status="expired", resolved_at=datetime.now(UTC))
        )

        # 3. Check if pending proposals already exist (don't regenerate)
        existing_pending = await self.db.scalar(
            select(func.count()).where(
                UserLearningProposal.user_id == user_id,
                UserLearningProposal.status == "pending",
            )
        )
        if existing_pending and existing_pending >= CHECKPOINT_MIN_PROPOSALS:
            # Return existing pending proposals
            result = await self.db.execute(
                select(UserLearningProposal)
                .where(
                    UserLearningProposal.user_id == user_id,
                    UserLearningProposal.status == "pending",
                )
                .order_by(UserLearningProposal.signal_strength.desc())
                .limit(CHECKPOINT_MAX_PROPOSALS)
            )
            return list(result.scalars().all())

        # 4. Compute signals
        source_signals = await self._compute_source_signals(user_id, cutoff)
        entity_signals = await self._compute_entity_signals(user_id, cutoff)

        # 5. Load existing entity preferences to avoid duplicate proposals
        existing_entity_prefs = await self.db.execute(
            select(UserEntityPreference.entity_canonical).where(
                UserEntityPreference.user_id == user_id
            )
        )
        already_preffed = {row[0] for row in existing_entity_prefs.all()}

        # 6. Build candidate proposals
        candidates: list[dict] = []

        # Source priority proposals
        for sig in source_signals:
            ratio = sig["ratio"]
            multiplier = sig["current_multiplier"]

            # Signal: user ignores source (low engagement, high multiplier)
            if ratio < 0.1 and multiplier >= 1.0:
                proposed = max(0.5, multiplier * 0.5)
                delta = abs(multiplier - proposed) / max(multiplier, 1.0)
                candidates.append(
                    {
                        "proposal_type": "source_priority",
                        "entity_type": "source",
                        "entity_id": str(sig["source_id"]),
                        "entity_label": sig["source_name"],
                        "current_value": str(multiplier),
                        "proposed_value": str(proposed),
                        "signal_strength": min(1.0, delta + (1.0 - ratio)),
                        "signal_context": {
                            "articles_shown": sig["impressions"],
                            "articles_clicked": sig["interactions"],
                            "period_days": SIGNAL_WINDOW_DAYS,
                        },
                    }
                )
            # Signal: user loves source (high engagement, low multiplier)
            elif ratio > 0.5 and multiplier <= 1.0:
                proposed = min(2.0, multiplier * 2.0)
                delta = abs(proposed - multiplier) / max(multiplier, 1.0)
                candidates.append(
                    {
                        "proposal_type": "source_priority",
                        "entity_type": "source",
                        "entity_id": str(sig["source_id"]),
                        "entity_label": sig["source_name"],
                        "current_value": str(multiplier),
                        "proposed_value": str(proposed),
                        "signal_strength": min(1.0, delta + ratio),
                        "signal_context": {
                            "articles_shown": sig["impressions"],
                            "articles_clicked": sig["interactions"],
                            "period_days": SIGNAL_WINDOW_DAYS,
                        },
                    }
                )

        # Entity proposals
        for sig in entity_signals:
            entity_name = sig["entity_name"]
            if entity_name in already_preffed:
                continue

            shown = sig["articles_shown"]
            clicked = sig["articles_clicked"]

            # Mute: many articles, zero interaction
            if clicked == 0 and shown >= SIGNAL_THRESHOLD_ENTITY_MUTE:
                candidates.append(
                    {
                        "proposal_type": "mute_entity",
                        "entity_type": "entity",
                        "entity_id": entity_name,
                        "entity_label": entity_name,
                        "current_value": "not_muted",
                        "proposed_value": "mute",
                        "signal_strength": min(1.0, shown / 10.0),
                        "signal_context": {
                            "articles_shown": shown,
                            "articles_clicked": clicked,
                            "period_days": SIGNAL_WINDOW_DAYS,
                        },
                    }
                )
            # Follow: many articles, strong interaction
            elif clicked >= 3 and shown >= SIGNAL_THRESHOLD_ENTITY_FOLLOW:
                ratio = clicked / shown
                candidates.append(
                    {
                        "proposal_type": "follow_entity",
                        "entity_type": "entity",
                        "entity_id": entity_name,
                        "entity_label": entity_name,
                        "current_value": "not_followed",
                        "proposed_value": "follow",
                        "signal_strength": min(1.0, ratio + clicked / 10.0),
                        "signal_context": {
                            "articles_shown": shown,
                            "articles_clicked": clicked,
                            "period_days": SIGNAL_WINDOW_DAYS,
                        },
                    }
                )

        # 7. Sort by signal strength, diversify types, take max
        candidates.sort(key=lambda c: c["signal_strength"], reverse=True)
        selected = _diversify_proposals(candidates, CHECKPOINT_MAX_PROPOSALS)

        if not selected:
            return []

        # 8. Persist proposals
        now = datetime.now(UTC)
        proposals = []
        for cand in selected:
            proposal = UserLearningProposal(
                user_id=user_id,
                proposal_type=cand["proposal_type"],
                entity_type=cand["entity_type"],
                entity_id=cand["entity_id"],
                entity_label=cand["entity_label"],
                current_value=cand["current_value"],
                proposed_value=cand["proposed_value"],
                signal_strength=cand["signal_strength"],
                signal_context=cand["signal_context"],
                computed_at=now,
                created_at=now,
                updated_at=now,
            )
            self.db.add(proposal)
            proposals.append(proposal)

        await self.db.flush()
        logger.info(
            "learning_proposals_generated",
            user_id=str(user_id),
            count=len(proposals),
            types=[p.proposal_type for p in proposals],
        )
        return proposals

    # ------------------------------------------------------------------
    # Get Pending Proposals (Story 13.3)
    # ------------------------------------------------------------------

    async def get_pending_proposals(
        self, user_id: UUID
    ) -> list[UserLearningProposal]:
        """Retourne les propositions pending pour un utilisateur."""
        result = await self.db.execute(
            select(UserLearningProposal)
            .where(
                UserLearningProposal.user_id == user_id,
                UserLearningProposal.status == "pending",
            )
            .order_by(UserLearningProposal.signal_strength.desc())
            .limit(CHECKPOINT_MAX_PROPOSALS)
        )
        proposals = list(result.scalars().all())

        # Increment shown_count
        if proposals:
            now = datetime.now(UTC)
            ids = [p.id for p in proposals]
            await self.db.execute(
                update(UserLearningProposal)
                .where(UserLearningProposal.id.in_(ids))
                .values(
                    shown_count=UserLearningProposal.shown_count + 1,
                    shown_at=now,
                    updated_at=now,
                )
            )
            await self.db.flush()

        return proposals

    # ------------------------------------------------------------------
    # Apply Proposals (Story 13.4)
    # ------------------------------------------------------------------

    async def apply_proposals(
        self, user_id: UUID, actions: list[dict]
    ) -> list[dict]:
        """Applique les actions sur les propositions.

        actions: list of {proposal_id, action, value?}
        Returns list of {proposal_id, action, success, detail}
        """
        now = datetime.now(UTC)
        results = []

        for act in actions:
            proposal_id = act["proposal_id"]
            action = act["action"]
            value = act.get("value")

            # Fetch proposal
            proposal = await self.db.scalar(
                select(UserLearningProposal).where(
                    UserLearningProposal.id == proposal_id,
                    UserLearningProposal.user_id == user_id,
                    UserLearningProposal.status == "pending",
                )
            )

            if not proposal:
                results.append(
                    {
                        "proposal_id": proposal_id,
                        "action": action,
                        "success": False,
                        "detail": "Proposal not found or already resolved",
                    }
                )
                continue

            if action == "dismiss":
                proposal.status = "dismissed"
                proposal.resolved_at = now
                proposal.updated_at = now
                results.append(
                    {
                        "proposal_id": proposal_id,
                        "action": action,
                        "success": True,
                        "detail": None,
                    }
                )
                continue

            # Accept or modify
            final_value = value if action == "modify" and value else proposal.proposed_value

            try:
                await self._apply_single_proposal(user_id, proposal, final_value)
                proposal.status = "accepted" if action == "accept" else "modified"
                proposal.user_chosen_value = final_value if action == "modify" else None
                proposal.resolved_at = now
                proposal.updated_at = now
                results.append(
                    {
                        "proposal_id": proposal_id,
                        "action": action,
                        "success": True,
                        "detail": None,
                    }
                )
            except Exception as e:
                logger.error(
                    "apply_proposal_error",
                    proposal_id=str(proposal_id),
                    error=str(e),
                )
                results.append(
                    {
                        "proposal_id": proposal_id,
                        "action": action,
                        "success": False,
                        "detail": str(e),
                    }
                )

        await self.db.flush()
        return results

    async def _apply_single_proposal(
        self, user_id: UUID, proposal: UserLearningProposal, value: str
    ) -> None:
        """Applique une proposition unique selon son type."""
        if proposal.proposal_type == "source_priority":
            source_id = UUID(proposal.entity_id)
            new_multiplier = float(value)
            # Clamp to [0.5, 2.0]
            new_multiplier = max(0.5, min(2.0, new_multiplier))
            await self.db.execute(
                update(UserSource)
                .where(
                    UserSource.user_id == user_id,
                    UserSource.source_id == source_id,
                )
                .values(priority_multiplier=new_multiplier)
            )
            logger.info(
                "learning_applied_source_priority",
                user_id=str(user_id),
                source_id=str(source_id),
                new_multiplier=new_multiplier,
            )

        elif proposal.proposal_type in ("mute_entity", "follow_entity"):
            preference = "mute" if proposal.proposal_type == "mute_entity" else "follow"
            if value in ("mute", "follow"):
                preference = value

            stmt = (
                pg_insert(UserEntityPreference)
                .values(
                    user_id=user_id,
                    entity_canonical=proposal.entity_id,
                    preference=preference,
                )
                .on_conflict_do_update(
                    constraint="uq_user_entity_pref_user_entity",
                    set_={"preference": preference},
                )
            )
            await self.db.execute(stmt)
            logger.info(
                "learning_applied_entity_preference",
                user_id=str(user_id),
                entity=proposal.entity_id,
                preference=preference,
            )

    # ------------------------------------------------------------------
    # Entity Preferences (Story 13.7)
    # ------------------------------------------------------------------

    async def set_entity_preference(
        self, user_id: UUID, entity_canonical: str, preference: str
    ) -> None:
        """Cree ou met a jour une preference entite."""
        stmt = (
            pg_insert(UserEntityPreference)
            .values(
                user_id=user_id,
                entity_canonical=entity_canonical,
                preference=preference,
            )
            .on_conflict_do_update(
                constraint="uq_user_entity_pref_user_entity",
                set_={"preference": preference},
            )
        )
        await self.db.execute(stmt)
        await self.db.flush()

    async def remove_entity_preference(
        self, user_id: UUID, entity_canonical: str
    ) -> bool:
        """Supprime une preference entite. Retourne True si supprimee."""
        result = await self.db.execute(
            delete(UserEntityPreference).where(
                UserEntityPreference.user_id == user_id,
                UserEntityPreference.entity_canonical == entity_canonical,
            )
        )
        await self.db.flush()
        return result.rowcount > 0

    async def get_entity_preferences(
        self, user_id: UUID
    ) -> list[UserEntityPreference]:
        """Retourne toutes les preferences entite d'un utilisateur."""
        result = await self.db.execute(
            select(UserEntityPreference).where(
                UserEntityPreference.user_id == user_id
            )
        )
        return list(result.scalars().all())

    async def get_muted_entities(self, user_id: UUID) -> list[str]:
        """Retourne les noms canoniques des entites mutees."""
        result = await self.db.execute(
            select(UserEntityPreference.entity_canonical).where(
                UserEntityPreference.user_id == user_id,
                UserEntityPreference.preference == "mute",
            )
        )
        return [row[0] for row in result.all()]


def _diversify_proposals(
    candidates: list[dict], max_count: int
) -> list[dict]:
    """Selectionne des propositions diversifiees par type.

    Garantit un mix de types differents plutot que N fois le meme type.
    """
    if len(candidates) <= max_count:
        return candidates

    selected: list[dict] = []
    type_counts: dict[str, int] = {}
    max_per_type = max(1, max_count // 2 + 1)  # Max 3 of same type for 4 total

    for cand in candidates:
        if len(selected) >= max_count:
            break
        ptype = cand["proposal_type"]
        if type_counts.get(ptype, 0) >= max_per_type:
            continue
        selected.append(cand)
        type_counts[ptype] = type_counts.get(ptype, 0) + 1

    # If we haven't filled up, add remaining by signal strength
    if len(selected) < max_count:
        remaining = [c for c in candidates if c not in selected]
        for cand in remaining:
            if len(selected) >= max_count:
                break
            selected.append(cand)

    return selected
