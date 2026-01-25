#!/usr/bin/env python3
"""
Profiling Script: Feed Latency Diagnosis
=========================================
Phase 1 (MEASURE) deliverable for BMAD analysis.

Usage:
    cd /Users/laurinboujon/Desktop/Projects/Work\ Projects/Facteur/packages/api
    source .venv/bin/activate
    python scripts/profile_feed_latency.py

This script measures latency at each layer of the feed endpoint:
1. Database Connection Acquisition
2. User Profile Fetch
3. Candidate Fetching (SQL)
4. Scoring Loop (CPU-bound)
5. Pydantic Serialization
6. Total Response Time

Results are printed as structured logs for analysis.
"""

import asyncio
import os
import sys
import time
from contextlib import asynccontextmanager
from dataclasses import dataclass
from uuid import UUID
from sqlalchemy import text

# Add parent to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Must be before app imports to set up env
from dotenv import load_dotenv
load_dotenv()


@dataclass
class TimingResult:
    """Single timing measurement."""
    label: str
    duration_ms: float
    detail: str = ""


class LatencyProfiler:
    """Collects and reports timing measurements."""
    
    def __init__(self):
        self.timings: list[TimingResult] = []
        self._start_time: float = 0
        
    def start(self):
        self._start_time = time.perf_counter()
        
    @asynccontextmanager
    async def measure(self, label: str, detail: str = ""):
        start = time.perf_counter()
        try:
            yield
        finally:
            duration_ms = (time.perf_counter() - start) * 1000
            self.timings.append(TimingResult(label, duration_ms, detail))
    
    def total_ms(self) -> float:
        return (time.perf_counter() - self._start_time) * 1000
    
    def report(self):
        print("\n" + "=" * 70)
        print("📊 FEED LATENCY PROFILE REPORT")
        print("=" * 70)
        
        total = self.total_ms()
        
        for t in self.timings:
            pct = (t.duration_ms / total * 100) if total > 0 else 0
            bar = "█" * int(pct / 2)
            detail_str = f" ({t.detail})" if t.detail else ""
            print(f"{t.label:35s} {t.duration_ms:8.2f}ms  {pct:5.1f}%  {bar}{detail_str}")
        
        print("-" * 70)
        print(f"{'TOTAL':35s} {total:8.2f}ms  100.0%")
        print("=" * 70)
        
        # Identify bottleneck
        if self.timings:
            bottleneck = max(self.timings, key=lambda t: t.duration_ms)
            print(f"\n🔴 BOTTLENECK: {bottleneck.label} ({bottleneck.duration_ms:.2f}ms)")
            
        # Recommendations
        print("\n📋 QUICK ANALYSIS:")
        for t in self.timings:
            if t.duration_ms > 500:
                print(f"  ⚠️  {t.label} is SLOW (>{500}ms threshold)")
            elif t.duration_ms > 100:
                print(f"  ⏳ {t.label} is moderate ({t.duration_ms:.0f}ms)")


async def profile_feed_endpoint(user_id: str, limit: int = 20):
    """Profile the feed endpoint with detailed timing breakdown."""
    
    profiler = LatencyProfiler()
    profiler.start()
    
    # ─────────────────────────────────────────────────────────────────────
    # 1. DATABASE CONNECTION ACQUISITION
    # ─────────────────────────────────────────────────────────────────────
    from app.database import async_session_maker
    
    async with profiler.measure("1. DB Session Acquisition"):
        session = async_session_maker()
    
    try:
        user_uuid = UUID(user_id)
        
        # ─────────────────────────────────────────────────────────────────
        # 2. USER PROFILE FETCH (with interests & preferences)
        # ─────────────────────────────────────────────────────────────────
        from sqlalchemy import select
        from sqlalchemy.orm import selectinload
        from app.models.user import UserProfile, UserSubtopic
        from app.models.source import UserSource
        
        async with profiler.measure("2. User Profile Query", "joinedload(interests, prefs)"):
            user_profile = await session.scalar(
                select(UserProfile)
                .options(
                    selectinload(UserProfile.interests),
                    selectinload(UserProfile.preferences)
                )
                .where(UserProfile.user_id == user_uuid)
            )
        
        async with profiler.measure("3. Followed Sources Query"):
            followed_sources_result = await session.scalars(
                select(UserSource.source_id).where(UserSource.user_id == user_uuid)
            )
            followed_source_ids = set(followed_sources_result.all())
        
        async with profiler.measure("4. User Subtopics Query"):
            subtopics_result = await session.scalars(
                select(UserSubtopic.topic_slug).where(UserSubtopic.user_id == user_uuid)
            )
            user_subtopics = set(subtopics_result.all())
        
        # ─────────────────────────────────────────────────────────────────
        # 3. CANDIDATE FETCHING (Main SQL Query)
        # ─────────────────────────────────────────────────────────────────
        from app.services.recommendation_service import RecommendationService
        
        service = RecommendationService(session)
        
        async with profiler.measure("5. Candidates Query", "Top 500 unseen contents"):
            candidates = await service._get_candidates(
                user_uuid, 
                limit_candidates=500,
                content_type=None,
                mode=None,
                followed_source_ids=followed_source_ids
            )
        
        num_candidates = len(candidates)
        
        # ─────────────────────────────────────────────────────────────────
        # 4. SCORING LOOP (CPU-Bound)
        # ─────────────────────────────────────────────────────────────────
        import datetime
        from app.services.recommendation.scoring_engine import ScoringContext
        
        # Build context
        user_interests = set()
        user_interest_weights = {}
        user_prefs = {}
        
        if user_profile:
            for i in user_profile.interests:
                user_interests.add(i.interest_slug)
                user_interest_weights[i.interest_slug] = i.weight
            for p in user_profile.preferences:
                user_prefs[p.preference_key] = p.preference_value
        
        context = ScoringContext(
            user_profile=user_profile,
            user_interests=user_interests,
            user_interest_weights=user_interest_weights,
            followed_source_ids=followed_source_ids,
            user_prefs=user_prefs,
            now=datetime.datetime.utcnow(),
            user_subtopics=user_subtopics
        )
        
        async with profiler.measure("6. Scoring Loop", f"{num_candidates} candidates"):
            scored_candidates = []
            for content in candidates:
                score = service.scoring_engine.compute_score(content, context)
                scored_candidates.append((content, score))
        
        async with profiler.measure("7. Sorting + Diversity"):
            scored_candidates.sort(key=lambda x: x[1], reverse=True)
            
            # Diversity re-ranking
            final_list = []
            source_counts = {}
            decay_factor = 0.85
            
            for content, base_score in scored_candidates:
                source_id = content.source_id
                count = source_counts.get(source_id, 0)
                final_score = base_score * (decay_factor ** count)
                final_list.append((content, final_score))
                source_counts[source_id] = count + 1
            
            final_list.sort(key=lambda x: x[1], reverse=True)
            result = [item[0] for item in final_list[:limit]]
        
        # ─────────────────────────────────────────────────────────────────
        # 5. PYDANTIC SERIALIZATION
        # ─────────────────────────────────────────────────────────────────
        from app.schemas.content import ContentResponse
        
        async with profiler.measure("8. Pydantic Serialization", f"{len(result)} items"):
            serialized = [ContentResponse.model_validate(c).model_dump() for c in result]
        
        # ─────────────────────────────────────────────────────────────────
        # 6. BRIEFING QUERY (if applicable)
        # ─────────────────────────────────────────────────────────────────
        from app.models.daily_top3 import DailyTop3
        from app.models.content import Content
        
        today_start = datetime.datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        
        async with profiler.measure("9. Briefing Query", "Today's Top3"):
            stmt = (
                select(DailyTop3)
                .options(
                    selectinload(DailyTop3.content)
                    .selectinload(Content.source)
                )
                .where(
                    DailyTop3.user_id == user_uuid,
                    DailyTop3.generated_at >= today_start
                )
                .order_by(DailyTop3.rank)
            )
            briefing_result = await session.execute(stmt)
            briefing_rows = briefing_result.scalars().all()
        
    finally:
        await session.close()
    
    # Print Report
    profiler.report()
    
    print(f"\n📈 DATA STATS:")
    print(f"  • Candidates fetched: {num_candidates}")
    print(f"  • Final items: {len(result)}")
    print(f"  • Followed sources: {len(followed_source_ids)}")
    print(f"  • User interests: {len(user_interests)}")
    print(f"  • User subtopics: {len(user_subtopics)}")
    print(f"  • Briefing items: {len(briefing_rows)}")


async def test_db_connection_cold():
    """Test raw DB connection time (simulates cold start)."""
    print("\n🧊 COLD DB CONNECTION TEST")
    print("-" * 40)
    
    from app.database import engine
    
    # Dispose any existing connections
    await engine.dispose()
    
    start = time.perf_counter()
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    cold_ms = (time.perf_counter() - start) * 1000
    
    # Warm connection
    start = time.perf_counter()
    async with engine.connect() as conn:
        await conn.execute(text("SELECT 1"))
    warm_ms = (time.perf_counter() - start) * 1000
    
    print(f"  Cold connection: {cold_ms:.2f}ms")
    print(f"  Warm connection: {warm_ms:.2f}ms")
    print(f"  Cold start penalty: {cold_ms - warm_ms:.2f}ms")
    
    if cold_ms > 1000:
        print("  ⚠️  HIGH: Cold start > 1s suggests Railway/PgBouncer latency")


async def main():
    from sqlalchemy import text
    
    print("🔬 FACTEUR FEED LATENCY PROFILER")
    print("=" * 70)
    print("Phase 1 (MEASURE) - BMAD Protocol")
    print()
    
    # Check for test user
    # You can override with: USER_ID=xxx python scripts/profile_feed_latency.py
    test_user_id = os.environ.get("TEST_USER_ID")
    
    if not test_user_id:
        # Fetch a random user from DB for testing
        print("ℹ️  No TEST_USER_ID provided, fetching a random user...")
        from app.database import async_session_maker
        
        async with async_session_maker() as session:
            result = await session.execute(
                text("SELECT user_id FROM user_profiles LIMIT 1")
            )
            row = result.fetchone()
            if row:
                test_user_id = str(row[0])
                print(f"   Using user: {test_user_id}")
            else:
                print("❌ No users found in database!")
                return
    
    # Test cold DB connection
    await test_db_connection_cold()
    
    # Profile feed endpoint
    print(f"\n🎯 PROFILING FEED FOR USER: {test_user_id}")
    await profile_feed_endpoint(test_user_id, limit=20)
    
    print("\n✅ Profiling complete. Use these results for Phase 2 (ANALYZE).")


if __name__ == "__main__":
    asyncio.run(main())
