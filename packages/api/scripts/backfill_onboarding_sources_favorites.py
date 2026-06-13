#!/usr/bin/env python3
"""Repair post-onboarding source states and default theme favorites.

Dry-run by default:
    cd packages/api
    python scripts/backfill_onboarding_sources_favorites.py

Apply:
    cd packages/api
    python scripts/backfill_onboarding_sources_favorites.py --apply
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from dataclasses import dataclass, field
from uuid import UUID

from dotenv import load_dotenv
from sqlalchemy import select

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
load_dotenv()

from app.database import safe_async_session  # noqa: E402
from app.models.enums import InterestState  # noqa: E402
from app.models.source import Source, UserSource  # noqa: E402
from app.models.user import UserInterest, UserProfile  # noqa: E402
from app.models.user_favorites import UserFavoriteInterest  # noqa: E402

FOLLOWED_SOURCE_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)


@dataclass
class UserRepair:
    user_id: UUID
    favorite_slugs: list[str] = field(default_factory=list)
    source_ids_followed: list[UUID] = field(default_factory=list)
    manual_reason: str | None = None

    @property
    def changed(self) -> bool:
        return bool(self.favorite_slugs or self.source_ids_followed)


async def repair_user(user_id: UUID, *, apply: bool) -> UserRepair:
    repair = UserRepair(user_id=user_id)

    async with safe_async_session() as session:
        interests = (
            (
                await session.execute(
                    select(UserInterest)
                    .where(UserInterest.user_id == user_id)
                    .order_by(UserInterest.created_at, UserInterest.interest_slug)
                )
            )
            .scalars()
            .all()
        )
        favorites = (
            (
                await session.execute(
                    select(UserFavoriteInterest).where(
                        UserFavoriteInterest.user_id == user_id
                    )
                )
            )
            .scalars()
            .all()
        )
        user_sources = (
            (
                await session.execute(
                    select(UserSource)
                    .join(Source, Source.id == UserSource.source_id)
                    .where(
                        UserSource.user_id == user_id,
                        UserSource.is_custom.is_(False),
                        Source.is_active.is_(True),
                    )
                    .order_by(UserSource.added_at, UserSource.source_id)
                )
            )
            .scalars()
            .all()
        )

        if not favorites and interests:
            for position, interest in enumerate(interests[:3]):
                repair.favorite_slugs.append(interest.interest_slug)
                if apply:
                    interest.state = InterestState.FAVORITE
                    session.add(
                        UserFavoriteInterest(
                            user_id=user_id,
                            position=position,
                            interest_slug=interest.interest_slug,
                        )
                    )

        for user_source in user_sources:
            if user_source.state not in FOLLOWED_SOURCE_STATES:
                repair.source_ids_followed.append(user_source.source_id)
                if apply:
                    user_source.state = InterestState.FOLLOWED

        if not interests and not user_sources:
            repair.manual_reason = "no user_interests or non-custom user_sources"

        if apply:
            await session.commit()
        else:
            await session.rollback()

    return repair


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write repairs")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    async with safe_async_session() as session:
        stmt = (
            select(UserProfile.user_id)
            .where(UserProfile.onboarding_completed.is_(True))
            .order_by(UserProfile.created_at, UserProfile.user_id)
        )
        if args.limit:
            stmt = stmt.limit(args.limit)
        user_ids = list((await session.execute(stmt)).scalars().all())
        await session.rollback()

    inspected = repaired = ignored = manual = 0
    manual_rows: list[UserRepair] = []

    for user_id in user_ids:
        inspected += 1
        repair = await repair_user(user_id, apply=args.apply)
        if repair.manual_reason:
            manual += 1
            manual_rows.append(repair)
        elif repair.changed:
            repaired += 1
        else:
            ignored += 1

        if repair.changed or repair.manual_reason:
            print(
                f"user={repair.user_id} "
                f"favorites_seeded={len(repair.favorite_slugs)} "
                f"sources_followed={len(repair.source_ids_followed)} "
                f"manual_reason={repair.manual_reason or '-'}"
            )

    mode = "APPLY" if args.apply else "DRY_RUN"
    print(
        f"{mode} inspected={inspected} repaired={repaired} "
        f"ignored={ignored} manual_review={manual}"
    )
    if manual_rows:
        print("manual_review_users=" + ",".join(str(r.user_id) for r in manual_rows))


if __name__ == "__main__":
    asyncio.run(main())
