---
phase: 01-production-fixes
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - packages/api/app/workers/scheduler.py
autonomous: true

must_haves:
  truths:
    - "Daily digest generation job is scheduled at 8:00 Europe/Paris"
    - "run_digest_generation is imported from app.jobs.digest_generation_job"
    - "Job follows same pattern as existing daily_top3 job"
  artifacts:
    - path: "packages/api/app/workers/scheduler.py"
      provides: "Scheduler with digest generation job"
      contains:
        - "from app.jobs.digest_generation_job import run_digest_generation"
        - "CronTrigger(hour=8, minute=0, timezone=pytz.timezone(\"Europe/Paris\"))"
        - 'id="daily_digest"'
  key_links:
    - from: "packages/api/app/workers/scheduler.py"
      to: "app.jobs.digest_generation_job"
      via: "import run_digest_generation"
      pattern: "from app.jobs.digest_generation_job import run_digest_generation"
---

<objective>
Add the missing daily digest generation job to the scheduler.

Purpose: Fix FIX-01 - the digest is not regenerating automatically at 8am because the job is not scheduled.
Output: Modified scheduler.py with digest generation job added following the same pattern as the existing Top 3 job.
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

The job function already exists:
- File: packages/api/app/jobs/digest_generation_job.py
- Function: async def run_digest_generation(target_date=None, batch_size=100, concurrency_limit=10)
- It's already a proper async function that can be scheduled

Existing pattern to follow (from scheduler.py lines 35-41):
```python
# Job Top 3 Briefing Quotidien (8h00 Paris)
scheduler.add_job(
    generate_daily_top3_job,
    trigger=CronTrigger(hour=8, minute=0, timezone=pytz.timezone("Europe/Paris")),
    id="daily_top3",
    name="Daily Top 3 Briefing",
    replace_existing=True,
)
```

Required import at top of file:
- from app.jobs.digest_generation_job import run_digest_generation
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add digest generation job to scheduler</name>
  <files>packages/api/app/workers/scheduler.py</files>
  <action>
Modify packages/api/app/workers/scheduler.py:

1. Add import after line 11 (after top3_job import):
   ```python
   from app.jobs.digest_generation_job import run_digest_generation
   ```

2. Add the digest generation job after the Top 3 job (after line 41, before line 43):
   ```python
   # Job Digest Quotidien (8h00 Paris)
   scheduler.add_job(
       run_digest_generation,
       trigger=CronTrigger(hour=8, minute=0, timezone=pytz.timezone("Europe/Paris")),
       id="daily_digest",
       name="Daily Digest Generation",
       replace_existing=True,
   )
   ```

Follow the EXACT same pattern as the existing daily_top3 job:
- Same CronTrigger with hour=8, minute=0, timezone=pytz.timezone("Europe/Paris")
- Same parameters: trigger, id, name, replace_existing
- Use id="daily_digest" and name="Daily Digest Generation"
  </action>
  <verify>
Verify by checking the file:
- grep -n "from app.jobs.digest_generation_job import run_digest_generation" packages/api/app/workers/scheduler.py
- grep -n "daily_digest" packages/api/app/workers/scheduler.py
- grep -n "run_digest_generation" packages/api/app/workers/scheduler.py
  </verify>
  <done>
- Import line exists for run_digest_generation
- scheduler.add_job call exists with id="daily_digest"
- CronTrigger uses hour=8, minute=0, timezone="Europe/Paris"
- Job is added in start_scheduler() function
  </done>
</task>

</tasks>

<verification>
Verify the fix:
1. Import statement is at top of file
2. Job is added inside start_scheduler() function
3. Job uses same CronTrigger pattern as daily_top3
4. All required parameters present (trigger, id, name, replace_existing)
</verification>

<success_criteria>
- scheduler.py imports run_digest_generation from app.jobs.digest_generation_job
- scheduler.py adds a daily_digest job in start_scheduler()
- Job triggers at 8:00 daily in Europe/Paris timezone
- Code follows same pattern as existing daily_top3 job
</success_criteria>

<output>
After completion, create `.planning/phases/01-production-fixes/01-production-fixes-01-SUMMARY.md`
</output>
