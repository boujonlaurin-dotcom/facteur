---
phase: 01-production-fixes
plan: 03
type: execute
wave: 2
depends_on:
  - 01-production-fixes-01
  - 01-production-fixes-02
files_modified:
  - packages/api/app/workers/scheduler.py
  - packages/api/app/services/digest_selector.py
  - packages/api/tests/services/test_digest_selector.py (verify or create)
autonomous: false

must_haves:
  truths:
    - "Scheduler contains daily_digest job that triggers at 8am"
    - "Digest diversity test passes with decay factor verification"
    - "Le Monde only user test case shows 3+ sources in digest"
    - "No single source exceeds 2 articles in test digest"
  artifacts:
    - path: "packages/api/tests/services/test_digest_selector.py"
      provides: "Test coverage for diversity algorithm"
      contains:
        - "test_diversity_decay_factor"
        - "test_minimum_three_sources"
        - "test_le_monde_only_user"
  key_links:
    - from: "tests"
      to: "_select_with_diversity()"
      via: "test functions calling selector"
      pattern: "selector._select_with_diversity"
---

<objective>
Verify both bug fixes work correctly through automated tests.

Purpose: Ensure FIX-01 (scheduler) and FIX-02 (diversity) are working as expected before production deployment.
Output: Passing tests that verify scheduler job exists and diversity algorithm works correctly.
</objective>

<execution_context>
@/Users/laurinboujon/.config/opencode/get-shit-done/workflows/execute-plan.md
@/Users/laurinboujon/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-production-fixes/01-production-fixes-01-SUMMARY.md
@.planning/phases/01-production-fixes/01-production-fixes-02-SUMMARY.md

Test requirements from REQUIREMENTS.md:
- TEST-01: Verify job triggers at 8am daily
- TEST-02: Verify diversity with "Le Monde only" user test case

Existing test file: packages/api/app/services/digest_selector_test.py (note: this is in services folder, not tests/)

Key things to verify:
1. Scheduler has the daily_digest job configured
2. Diversity algorithm applies decay factor correctly
3. Le Monde-only user still gets 3+ sources (via fallback)
4. No source has more than 2 articles
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create/Update scheduler verification test</name>
  <files>packages/api/tests/workers/test_scheduler.py (create if missing)</files>
  <action>
Create or update test file to verify the scheduler has the digest generation job.

File: packages/api/tests/workers/test_scheduler.py (create if doesn't exist)

Test to add:
```python
import pytest
from unittest.mock import Mock, patch
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.workers.scheduler import start_scheduler, stop_scheduler


class TestScheduler:
    """Tests for the background job scheduler."""
    
    def test_scheduler_has_daily_digest_job(self):
        """TEST-01: Verify daily digest job is scheduled at 8am Paris time."""
        # Start scheduler
        start_scheduler()
        scheduler = get_scheduler()  # Need to expose this or check internals
        
        # Find the daily_digest job
        job = scheduler.get_job("daily_digest")
        assert job is not None, "daily_digest job not found in scheduler"
        
        # Verify it's a CronTrigger at 8:00
        assert isinstance(job.trigger, CronTrigger)
        assert job.trigger.fields[0] == 0  # minute = 0
        assert job.trigger.fields[1] == 8  # hour = 8
        
        # Verify timezone is Europe/Paris
        assert str(job.trigger.timezone) == "Europe/Paris"
        
        stop_scheduler()
    
    def test_digest_job_uses_run_digest_generation(self):
        """Verify the digest job calls run_digest_generation function."""
        start_scheduler()
        scheduler = get_scheduler()
        
        job = scheduler.get_job("daily_digest")
        assert job.func.__name__ == "run_digest_generation"
        
        stop_scheduler()
```

Note: You may need to expose the scheduler instance for testing, or use mocking to verify the add_job calls.

Alternative approach without exposing scheduler:
```python
@patch('app.workers.scheduler.AsyncIOScheduler')
def test_scheduler_adds_digest_job(self, mock_scheduler_class):
    """Verify scheduler adds daily_digest job with correct parameters."""
    mock_scheduler = Mock()
    mock_scheduler_class.return_value = mock_scheduler
    
    start_scheduler()
    
    # Check that add_job was called for daily_digest
    calls = mock_scheduler.add_job.call_args_list
    digest_calls = [c for c in calls if c.kwargs.get('id') == 'daily_digest']
    
    assert len(digest_calls) == 1, "daily_digest job not added"
    
    call = digest_calls[0]
    assert call.args[0].__name__ == 'run_digest_generation'
    assert isinstance(call.kwargs['trigger'], CronTrigger)
```
  </action>
  <verify>
Run the test:
- cd packages/api && python -m pytest tests/workers/test_scheduler.py::TestScheduler::test_scheduler_has_daily_digest_job -v
  </verify>
  <done>
- Test file exists with scheduler verification tests
- Test passes confirming daily_digest job is scheduled
- Test confirms 8am Europe/Paris timezone
  </done>
</task>

<task type="auto">
  <name>Task 2: Add diversity verification tests</name>
  <files>packages/api/app/services/digest_selector_test.py</files>
  <action>
Add tests to the existing digest_selector_test.py file to verify the decay-based diversity algorithm.

Add these test methods to the existing test class:

```python
    def test_diversity_decay_factor_applied(self):
        """TEST-02: Verify decay factor reduces scores for same-source articles."""
        # Create 3 articles from same source with equal base scores
        source = self.sources[0]
        articles = []
        for i in range(3):
            content = Content(
                id=uuid4(),
                title=f"Article {i}",
                source_id=source.id,
                source=source,
                published_at=datetime.now(timezone.utc) - timedelta(hours=i),
                content_type="article"
            )
            articles.append(content)
        
        # Score them equally (simulate scoring)
        scored = [(article, 100.0, []) for article in articles]
        
        # Select with diversity
        selector = MockDigestSelector(None)
        selected = selector._select_with_diversity(scored, target_count=3)
        
        # Verify decay is applied - second article should have lower effective score
        assert len(selected) == 3
        scores = [item[1] for item in selected]  # (content, score, reason, breakdown)
        
        # First: 100 * (0.70^0) = 100
        # Second: 100 * (0.70^1) = 70
        # Third: 100 * (0.70^2) = 49
        assert scores[0] == 100.0
        assert scores[1] == 70.0  # 100 * 0.70
        assert scores[2] == 49.0  # 100 * 0.70^2
    
    def test_minimum_three_sources_enforced(self):
        """Verify digest has at least 3 different sources when possible."""
        # Create articles from 5 different sources
        sources_articles = []
        for i, source in enumerate(self.sources[:5]):
            content = Content(
                id=uuid4(),
                title=f"Article from {source.name}",
                source_id=source.id,
                source=source,
                published_at=datetime.now(timezone.utc) - timedelta(hours=i),
                content_type="article"
            )
            sources_articles.append((content, 100.0 - i * 5, []))  # Varying scores
        
        selector = MockDigestSelector(None)
        selected = selector._select_with_diversity(sources_articles, target_count=5)
        
        # Count unique sources
        selected_sources = set(item[0].source_id for item in selected)
        assert len(selected_sources) >= 3, f"Only {len(selected_sources)} sources in digest, expected at least 3"
    
    def test_le_monde_only_user_gets_diversity(self):
        """TEST-02: Le Monde-only user should still get 3+ sources via fallback."""
        # Simulate user who only follows Le Monde
        le_monde = next((s for s in self.sources if "monde" in s.name.lower()), self.sources[0])
        
        # Create articles - 2 from Le Monde (high scores), rest from other sources
        articles = []
        
        # 2 from Le Monde
        for i in range(2):
            content = Content(
                id=uuid4(),
                title=f"Le Monde Article {i}",
                source_id=le_monde.id,
                source=le_monde,
                published_at=datetime.now(timezone.utc) - timedelta(hours=i),
                content_type="article"
            )
            articles.append((content, 100.0, []))
        
        # 5 from other sources (slightly lower scores)
        for i, source in enumerate(self.sources):
            if source.id != le_monde.id and i < 5:
                content = Content(
                    id=uuid4(),
                    title=f"Other Source Article {i}",
                    source_id=source.id,
                    source=source,
                    published_at=datetime.now(timezone.utc) - timedelta(hours=i+2),
                    content_type="article"
                )
                articles.append((content, 90.0, []))
        
        selector = MockDigestSelector(None)
        selected = selector._select_with_diversity(articles, target_count=5)
        
        # Count sources
        selected_sources = set(item[0].source_id for item in selected)
        
        # With decay and diversity, should have 3+ sources
        assert len(selected_sources) >= 3, \
            f"Le Monde-only user scenario: only {len(selected_sources)} sources, expected 3+"
        
        # No source should have more than 2
        source_counts = {}
        for item in selected:
            sid = item[0].source_id
            source_counts[sid] = source_counts.get(sid, 0) + 1
        
        max_count = max(source_counts.values())
        assert max_count <= 2, f"Source has {max_count} articles, max allowed is 2"
```
  </action>
  <verify>
Run the diversity tests:
- cd packages/api && python -m pytest app/services/digest_selector_test.py -v -k "diversity or sources or le_monde"
  </verify>
  <done>
- Decay factor test passes (scores reduced by 0.70^n)
- Minimum 3 sources test passes
- Le Monde-only user test passes with 3+ sources
- All diversity constraints verified
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Verify fixes with manual testing</name>
  <what-built>
Both bug fixes implemented:
1. FIX-01: Digest generation job added to scheduler (8am daily, Europe/Paris)
2. FIX-02: Diversity algorithm with decay factor (0.70) implemented

Automated tests created/updated to verify both fixes.
  </what-built>
  <how-to-verify>
1. **Verify Scheduler Fix:**
   - Open packages/api/app/workers/scheduler.py
   - Confirm import: `from app.jobs.digest_generation_job import run_digest_generation`
   - Confirm job: `scheduler.add_job(run_digest_generation, ...)` with id="daily_digest"
   - Confirm CronTrigger: hour=8, minute=0, timezone="Europe/Paris"

2. **Verify Diversity Fix:**
   - Open packages/api/app/services/digest_selector.py
   - Find _select_with_diversity() method
   - Confirm DECAY_FACTOR = 0.70 constant
   - Confirm decay application: `decayed_score = score * (DECAY_FACTOR ** current_source_count)`
   - Confirm MIN_SOURCES = 3 constant

3. **Run All Tests:**
   ```bash
   cd packages/api
   python -m pytest app/services/digest_selector_test.py -v
   python -m pytest tests/workers/test_scheduler.py -v
   ```

4. **Manual Integration Test (Optional):**
   ```bash
   # Start API server
   cd packages/api && python -m app.main
   
   # In another terminal, check scheduler logs for digest job
   # Or manually trigger: python -c "import asyncio; from app.jobs.digest_generation_job import run_digest_generation; asyncio.run(run_digest_generation())"
   ```
  </how-to-verify>
  <resume-signal>Type "approved" when tests pass and code review is complete</resume-signal>
</task>

</tasks>

<verification>
Verify the fixes:
1. Scheduler test confirms daily_digest job at 8am
2. Decay test confirms 0.70 factor applied correctly
3. Diversity test confirms 3+ sources
4. Le Monde test confirms fallback diversity works
5. All existing tests still pass (no regressions)
</verification>

<success_criteria>
- All tests pass (scheduler + diversity)
- Code review confirms fixes match requirements
- No regressions in existing functionality
- Ready for production deployment
</success_criteria>

<output>
After completion, create `.planning/phases/01-production-fixes/01-production-fixes-03-SUMMARY.md`
</output>
