"""Rejoue la règle implicite `digest_completion ≥ 80% consumed` sur les
`daily_digest` des N derniers jours.

Plan engagement & PMF — Sprint 1.3. Avant le déploiement, la table
`digest_completions` est vide pour la majorité des users actifs parce que le
path explicite (closure_screen POST /digest/{id}/complete) n'a jamais été
atteint (app backgroundée, network drop, etc.). Ce script backfille en
INSERT idempotent (ON CONFLICT DO NOTHING) pour que la métrique "digest
completions per user-day" reflète la réalité.

Idempotent : relançable sans effet de bord grâce à l'UNIQUE (user_id,
target_date).

Usage:
    cd packages/api && source venv/bin/activate
    python scripts/backfill_digest_completions.py --days 30 [--threshold 0.8] [--dry-run]
"""

from dotenv import load_dotenv
from pathlib import Path

# Load .env BEFORE any app imports
load_dotenv(Path(__file__).parent.parent / ".env", override=True)

import argparse
import asyncio
import os
import sys
from datetime import datetime, timedelta
from uuid import UUID

from sqlalchemy import and_, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert

# Add parent directory for app imports
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.models.content import UserContentStatus
from app.models.daily_digest import DailyDigest
from app.models.digest_completion import DigestCompletion
from app.models.enums import ContentStatus
from app.services.digest_service import DigestService
from app.utils.time import today_paris


async def backfill(days: int, threshold: float, dry_run: bool) -> None:
    from app.database import async_session_maker, init_db

    print(f"Initializing database connection... (days={days}, threshold={threshold}, dry_run={dry_run})")
    await init_db()

    cutoff = today_paris() - timedelta(days=days)

    async with async_session_maker() as session:
        stmt = (
            select(DailyDigest)
            .where(DailyDigest.target_date >= cutoff)
            .order_by(DailyDigest.target_date.desc())
        )
        result = await session.execute(stmt)
        digests = list(result.scalars().all())
        print(f"Found {len(digests)} daily_digest rows in the window.")

        inserted = 0
        skipped_threshold = 0
        skipped_existing = 0
        errors = 0

        for digest in digests:
            try:
                content_ids = DigestService._extract_digest_content_ids(digest)
                if not content_ids:
                    continue

                count_stmt = (
                    select(func.count())
                    .select_from(UserContentStatus)
                    .where(
                        and_(
                            UserContentStatus.user_id == digest.user_id,
                            UserContentStatus.content_id.in_(content_ids),
                            UserContentStatus.status == ContentStatus.CONSUMED,
                        )
                    )
                )
                consumed_count = (await session.execute(count_stmt)).scalar_one()

                if consumed_count / len(content_ids) < threshold:
                    skipped_threshold += 1
                    continue

                # Check for existing row (for stats only — INSERT is idempotent)
                existing_stmt = select(DigestCompletion).where(
                    and_(
                        DigestCompletion.user_id == digest.user_id,
                        DigestCompletion.target_date == digest.target_date,
                    )
                )
                existing = (await session.execute(existing_stmt)).scalar_one_or_none()
                if existing is not None:
                    skipped_existing += 1
                    continue

                if dry_run:
                    inserted += 1
                    continue

                insert_stmt = (
                    pg_insert(DigestCompletion)
                    .values(
                        user_id=digest.user_id,
                        target_date=digest.target_date,
                        completed_at=datetime.utcnow(),
                        articles_read=consumed_count,
                    )
                    .on_conflict_do_nothing(
                        index_elements=["user_id", "target_date"],
                    )
                )
                await session.execute(insert_stmt)
                inserted += 1
            except Exception as exc:  # noqa: BLE001
                errors += 1
                print(
                    f"[error] user={digest.user_id} date={digest.target_date}: {exc}"
                )

        if not dry_run:
            await session.commit()

        print(
            f"Done. inserted={inserted} "
            f"skipped_threshold={skipped_threshold} "
            f"skipped_existing={skipped_existing} "
            f"errors={errors} "
            f"dry_run={dry_run}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="How many days back to replay (default: 30).",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.8,
        help="Fraction of consumed items that triggers a completion (default: 0.8).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Compute stats without writing any row.",
    )
    args = parser.parse_args()

    asyncio.run(backfill(args.days, args.threshold, args.dry_run))


if __name__ == "__main__":
    main()
