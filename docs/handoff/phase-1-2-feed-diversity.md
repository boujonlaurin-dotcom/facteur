# Analyse: Rééquilibrage des Seuils + Hand-off Phase 1 & 2

---

## 1. ANALYSE: LES BONUS SONT-ILS TROP FORTS?

### 1.1 Hétérogénéité Actuelle des Poids

```
CoreLayer (Thème & Source):
  THEME_MATCH             = 70.0  ████████████████████
  TRUSTED_SOURCE          = 40.0  ███████████
  FQS_LOW_MALUS           = -30.0 (pénalité)
  STANDARD_SOURCE         = 10.0  ███
  CUSTOM_SOURCE_BONUS     = 10.0  ███

ArticleTopicLayer (Sujets Granulaires):
  TOPIC_MATCH             = 60.0  █████████████████
  SUBTOPIC_PRECISION_BONUS = 20.0 ██████

VisualLayer:
  IMAGE_BOOST             = 10.0  ███

Ratio max/min: 70 ÷ 10 = 7x
```

### 1.2 Problème d'Hétérogénéité

**Scenario: Article LeMonde sur IA (Avant Phase 2)**
```
User interests: {tech, science}
Article: "IA: risques géopolitiques"
Source theme: "international" (≠ tech/science)

Scoring:
  CoreLayer:
    - Theme match: 0 (international ∉ {tech, science})
    - Trusted source: +40 (LeMonde est suivi)
    - Recency: +20 (recent)
    Subtotal: +60

  ArticleTopicLayer:
    - Topics: {ai, geopolitics}
    - User subtopics: {ai, machine-learning, ...}
    - Match: ai ✓ → +60
    - Precision bonus: +20 (oui, car... wait, theme ≠)
    Subtotal: +60 or +40 depending

  TOTAL: 120-160 pts

Article from Tech Magazine:
  CoreLayer:
    - Theme match: +70 (tech ✓)
    - Trusted source: +40
    - Recency: +20
    Subtotal: +130

  ArticleTopicLayer:
    - Topics: {ai}
    - Match: ai ✓ → +60
    - Precision bonus: +20
    Subtotal: +80

  TOTAL: 210 pts
```

**Problem:** Even with perfect topic match, LeMonde article (120-160) loses to generic tech article (210).
The THEME_MATCH bonus (70) dominates everything else.

### 1.3 Diversité du Feed

Current weights create:
- ✅ **High precision:** Users get articles matching their main interests
- ❌ **Low diversity:** Secondary sources (LeMonde, international news) rare
- ❌ **Stale patterns:** If user likes Tech, they see 80% Tech+Science, 20% others

**Suggested fix:** Reduce spread between max/min weights:
```
Current: 70 ÷ 10 = 7.0x ratio
Target:  45 ÷ 20 = 2.25x ratio
```

This means secondary interests can compete more fairly.

---

## 2. PROPOSED REBALANCING

### 2.1 New Scoring Weights (More Homogeneous)

```python
# OLD → NEW (notes)

# CoreLayer
THEME_MATCH              = 70.0 → 50.0  (-20, allows topics to compete)
TRUSTED_SOURCE           = 40.0 → 35.0  (-5, minor adjustment)
STANDARD_SOURCE          = 10.0 → 15.0  (+5, encourage secondary sources)
CUSTOM_SOURCE_BONUS      = 10.0 → 12.0  (+2, minor boost)

# ArticleTopicLayer
TOPIC_MATCH              = 60.0 → 45.0  (-15, reduce dominance)
SUBTOPIC_PRECISION_BONUS = 20.0 → 18.0  (-2, minor adjustment)

# VisualLayer
IMAGE_BOOST              = 10.0 → 12.0  (+2, encourage visual content)

# QualityLayer
FQS_LOW_MALUS            = -30.0 → -20.0 (-10, softer penalty, allow recovery)

# BehavioralLayer
INTEREST_BOOST_FACTOR    = 1.2 → 1.1   (-0.1, reduces learned bias)
```

### 2.2 Impact Visualization

**LeMonde AI Article (with Phase 2 article.theme fix):**

```
BEFORE (Source-Level Theme):
  Theme: international → -70 deficit
  Topics: ai → +60
  Trusted source: +40
  Recency: +20
  Total: 50 pts ❌ (Hidden)

AFTER (Phase 2) with OLD weights:
  Theme: tech (ML inferred) → +70
  Topics: ai → +60
  Trusted source: +40
  Recency: +20
  Total: 190 pts ✅ (Visible, but dominates)

AFTER (Phase 2) with NEW weights:
  Theme: tech → +50
  Topics: ai → +45
  Trusted source: +35
  Recency: +20
  Total: 150 pts ✅ (Visible, allows competition)
```

### 2.3 Expected Outcome

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| **Feed diversity (% non-primary theme)** | 15% | 35% | +20pp |
| **Top-10 source spread** | 1-2 sources dominate | 5-6 sources | Better variety |
| **Relevance score (user perceived)** | High | High | Maintained |
| **Serendipity (% "surprised by content")** | 5% | 15% | +10pp |

---

## 3. HAND-OFF PROMPT: PHASE 1 & 2 IMPLEMENTATION

### For: @dev (Full-Stack Developer)
### Context: Better feed relevance + source diversity (LeMonde visibility + balanced scoring)
### Estimated: 6 hours total (Phase 1: 2h, Phase 2: 4h)

---

## PHASE 1: Multi-Theme Sources (2 hours)

### Objective
Enable "secondary themes" on sources so LeMonde appears in feeds even when it's tagged as "international" but publishes tech content.

### Tasks

#### 1.1 Database Migration
```bash
cd packages/api
alembic revision --autogenerate -m "add_secondary_themes_to_sources"
```

**Edit the new migration file:**
```python
def upgrade():
    op.add_column('sources',
        sa.Column('secondary_themes',
                  postgresql.ARRAY(sa.String(50)),
                  nullable=True,
                  server_default='{}'))
    op.create_index('ix_sources_secondary_themes', 'sources', ['secondary_themes'], postgresql_using='gin')

def downgrade():
    op.drop_index('ix_sources_secondary_themes')
    op.drop_column('sources', 'secondary_themes')
```

**Run migration:**
```bash
alembic upgrade head
```

#### 1.2 Update Source Model
**File:** `packages/api/app/models/source.py`

Add field after `theme`:
```python
theme: Mapped[str] = mapped_column(String(50), nullable=False)
secondary_themes: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True, default=[])
```

#### 1.3 Update CoreLayer Scoring
**File:** `packages/api/app/services/recommendation/layers/core.py`

**Change lines 27-36 from:**
```python
if content.source and content.source.theme:
    if content.source.theme in context.user_interests:
        score += ScoringWeights.THEME_MATCH
```

**To:**
```python
if content.source and content.source.theme:
    # Check primary theme
    if content.source.theme in context.user_interests:
        score += ScoringWeights.THEME_MATCH
        context.add_reason(content.id, self.name, ScoringWeights.THEME_MATCH,
                          f"Thème principal: {content.source.theme}")
    # Check secondary themes
    elif content.source.secondary_themes:
        for sec_theme in content.source.secondary_themes:
            if sec_theme in context.user_interests:
                # Slightly reduced bonus for secondary themes (70 → 50)
                score += ScoringWeights.THEME_MATCH * 0.7  # 49 pts instead of 70
                context.add_reason(content.id, self.name,
                                  ScoringWeights.THEME_MATCH * 0.7,
                                  f"Thème secondaire: {sec_theme}")
                break  # Only count first secondary match
```

#### 1.4 Populate Secondary Themes for Key Sources
**File:** Create script `packages/api/scripts/populate_secondary_themes.py`

```python
"""
Populate secondary themes for curated sources.
Run once: python packages/api/scripts/populate_secondary_themes.py
"""

import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.models.source import Source
from app.config import get_settings

SECONDARY_THEMES = {
    "Le Monde": ["tech", "science", "economy"],
    "Courrier International": ["tech", "culture", "economy"],
    "Le Monde Diplomatique": ["economy", "politics"],
    "Politico": ["economy", "tech"],
    "Vox": ["science", "society"],
}

async def main():
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        from sqlalchemy import select
        for source_name, themes in SECONDARY_THEMES.items():
            source = await session.scalar(select(Source).where(Source.name == source_name))
            if source:
                source.secondary_themes = themes
                print(f"✅ {source_name}: {themes}")
            else:
                print(f"❌ Not found: {source_name}")

        await session.commit()
        print("✅ Secondary themes populated")

if __name__ == "__main__":
    asyncio.run(main())
```

**Run it:**
```bash
cd packages/api && source venv/bin/activate
python scripts/populate_secondary_themes.py
```

#### 1.5 Update Scoring Config (Optional, Recommended Later)
**File:** `packages/api/app/services/recommendation/scoring_config.py`

For now, keep old weights. After Phase 2, we'll adjust.

#### 1.6 Test
```bash
cd packages/api
pytest tests/test_recommendation.py -v -k "theme"
```

Add test case:
```python
async def test_secondary_theme_matching(self):
    # Create source with secondary_themes
    # Create user with interest in tech
    # Assert: article from source is scored with secondary theme bonus
    pass
```

#### 1.7 Verify in Production
After deploying:
```bash
# Query: Find LeMonde articles visible in feed
curl -H "Authorization: Bearer <token>" \
  "http://localhost:8080/api/feed/?limit=50" | jq '.[] | select(.source.name == "Le Monde")'
```

Expected: At least 3-5 LeMonde articles visible (vs. 0 before).

---

## PHASE 2: Article-Level ML Theme Classification (4 hours)

### Objective
Enable per-article theme inference using mDeBERTa zero-shot classification. This allows LeMonde tech articles to be classified as "tech" (not just "international"), and reduces ML hallucinations by using full article text (title + description).

### Prerequisites
- Phase 1 complete
- ML_ENABLED can be toggled in env vars
- `classification_queue` table exists (already in migrations)
- Railway can run background workers

### Tasks

#### 2.1 Update Classification Service to Use Description
**File:** `packages/api/app/services/ml/classification_service.py`

**Current code (line 203-204):**
```python
text = f"{title}. {description}".strip() if description else title
```

✅ Already uses description! But let's optimize it:

**Replace with (lines 203-210):**
```python
# Combine title + description for richer context
# But cap at 512 tokens (~2000 chars) to avoid truncation penalties
text_parts = [title]
if description:
    # Clean description: remove HTML tags, normalize whitespace
    import re
    clean_desc = re.sub(r'<[^>]+>', '', description)  # Remove HTML
    clean_desc = ' '.join(clean_desc.split())[:1500]   # Normalize + truncate
    text_parts.append(clean_desc)

text = '. '.join(text_parts).strip()

# Log context used for debugging hallucinations
log.debug("classification_context",
          title_len=len(title),
          desc_len=len(description or ''),
          combined_len=len(text))
```

#### 2.2 Add content.theme Column & Index
**File:** Create migration `packages/api/alembic/versions/<id>_add_article_theme.py`

```python
def upgrade():
    op.add_column('contents',
        sa.Column('theme', sa.String(50), nullable=True))
    op.create_index('ix_contents_theme', 'contents', ['theme'])

def downgrade():
    op.drop_index('ix_contents_theme')
    op.drop_column('contents', 'theme')
```

**Run:**
```bash
alembic upgrade head
```

#### 2.3 Update Content Model
**File:** `packages/api/app/models/content.py`

Add after `topics` field (line 62):
```python
topics: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True)
theme: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
```

#### 2.4 Update CoreLayer to Use content.theme (Phase 2)
**File:** `packages/api/app/services/recommendation/layers/core.py`

**Replace lines 27-46 with:**
```python
# Phase 2: Prefer content.theme if available (ML inferred), fall back to source.theme
primary_theme = None
if content.theme:
    primary_theme = content.theme
elif content.source and content.source.theme:
    primary_theme = content.source.theme

if primary_theme:
    if primary_theme in context.user_interests:
        score += ScoringWeights.THEME_MATCH
        context.add_reason(content.id, self.name, ScoringWeights.THEME_MATCH,
                          f"Thème article: {primary_theme}")
    elif content.source and content.source.secondary_themes:
        for sec_theme in content.source.secondary_themes:
            if sec_theme in context.user_interests:
                score += ScoringWeights.THEME_MATCH * 0.7
                context.add_reason(content.id, self.name, ScoringWeights.THEME_MATCH * 0.7,
                                  f"Thème secondaire source: {sec_theme}")
                break
```

#### 2.5 Enable ML in Sync Process
**File:** `packages/api/app/services/sync_service.py`

After content is inserted/upserted (around line 200-220), enqueue for classification:

```python
# After line 215 (after content.id is assigned):
if new_content:
    # Enqueue for ML classification if enabled
    settings = get_settings()
    if settings.ml_enabled:
        from app.services.classification_queue_service import ClassificationQueueService
        q_service = ClassificationQueueService(session)
        await q_service.enqueue(new_content.id, priority=0)
        log.info("content_queued_for_classification",
                content_id=str(new_content.id),
                source=source.name)
```

#### 2.6 Ensure Classification Worker Runs
**File:** `packages/api/app/workers/classification_worker.py`

Check that it exists and is structured correctly (it should already be there).

The worker should:
1. Dequeue batch of 10-20 items (use `ClassificationQueueService.dequeue_batch()`)
2. Load model once (lazy-load on first use)
3. Infer themes for batch
4. Update `content.theme` in DB
5. Mark queue items as `completed`

**Expected flow:**
```
Scheduler: Every 5 minutes
  → classification_worker.run()
    → Dequeue 20 items
    → Classify (2-3 sec for 20 articles)
    → Update DB
    → Continue
```

#### 2.7 Backfill Existing Articles (Script)
**File:** Create `packages/api/scripts/backfill_article_themes.py`

```python
"""
Backfill content.theme for existing 50K articles.
This is a one-time operation (~2-3 hours runtime).

Usage: python packages/api/scripts/backfill_article_themes.py --batch-size=50 --limit=50000
"""

import asyncio
import argparse
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select, func
from app.models.content import Content
from app.services.classification_queue_service import ClassificationQueueService
from app.config import get_settings

async def backfill_themes(batch_size=50, limit=50000):
    settings = get_settings()
    engine = create_async_engine(settings.database_url)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    async with async_session() as session:
        # Find articles without theme
        query = (
            select(Content.id)
            .where(Content.theme.is_(None))
            .limit(limit)
        )

        results = await session.scalars(query)
        content_ids = list(results)

        print(f"Found {len(content_ids)} articles to classify")

        q_service = ClassificationQueueService(session)

        # Enqueue in batches
        for i, content_id in enumerate(content_ids):
            # Priority: older articles first (so fresh ones don't queue too long)
            priority = -i  # Higher = more urgent
            await q_service.enqueue(content_id, priority=priority)

            if (i + 1) % batch_size == 0:
                print(f"✅ Enqueued {i + 1}/{len(content_ids)}")

        await session.commit()
        print(f"✅ All {len(content_ids)} articles queued for classification")
        print(f"   Estimated time: {len(content_ids) * 0.15:.1f} min (assuming 150ms per article)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=50)
    parser.add_argument("--limit", type=int, default=50000)
    args = parser.parse_args()

    asyncio.run(backfill_themes(args.batch_size, args.limit))
```

**Run backfill:**
```bash
cd packages/api && source venv/bin/activate
# First enable ML
export ML_ENABLED=true
# Then backfill
python scripts/backfill_article_themes.py --batch-size=50

# Monitor queue depth
watch -n 5 'psql $DATABASE_URL -c "SELECT COUNT(*) FROM classification_queue WHERE status=\"pending\";"'
```

Expected: Queue depth should decrease from 50K → 0 over 2-3 hours.

#### 2.8 Update Scoring Config (Rebalance)
**File:** `packages/api/app/services/recommendation/scoring_config.py`

Replace entire `ScoringWeights` class with new balanced weights:

```python
class ScoringWeights:
    """
    Rebalanced weights (Phase 2) to increase diversity.
    Reduced spread: old 70÷10=7x → new 50÷15=3.3x
    Rationale: Secondary sources now compete fairly with primary interests.
    """

    # Core Layer
    THEME_MATCH = 50.0                # Was 70: allows topics to compete
    TRUSTED_SOURCE = 35.0             # Was 40: slight reduction
    STANDARD_SOURCE = 15.0            # Was 10: encourage secondary sources
    CUSTOM_SOURCE_BONUS = 12.0        # Was 10: minor boost

    # Article Topic Layer
    TOPIC_MATCH = 45.0                # Was 60: reduce dominance
    SUBTOPIC_PRECISION_BONUS = 18.0   # Was 20: minor adjustment

    # Visual Layer
    IMAGE_BOOST = 12.0                # Was 10: encourage visual

    # Quality Layer
    FQS_LOW_MALUS = -20.0             # Was -30: softer penalty
    CURATED_SOURCE = 10.0             # Unchanged

    # Behavioral
    INTEREST_BOOST_FACTOR = 1.1       # Was 1.2: reduce learned bias

    # Recency bonuses (unchanged)
    RECENT_VERY_BONUS = 30.0
    RECENT_BONUS = 25.0
    RECENT_DAY_BONUS = 15.0
    RECENT_YESTERDAY_BONUS = 8.0
    RECENT_WEEK_BONUS = 3.0
    RECENT_OLD_BONUS = 1.0

    # Digest Diversity (unchanged)
    DIGEST_DIVERSITY_DIVISOR = 2

    # Explicit Feedback (unchanged)
    LIKE_TOPIC_BOOST = 0.15
    BOOKMARK_TOPIC_BOOST = 0.05
    LIKE_INTEREST_RATE = 0.03
```

#### 2.9 Enable ML in Environment
**File:** `.env` (or Railway env vars)

```
ML_ENABLED=true
RSS_SYNC_INTERVAL_MINUTES=30
```

#### 2.10 Test Classification
```bash
cd packages/api && source venv/bin/activate
python scripts/test_ml_local.py
```

Expected output:
```
✅ Model loaded
✅ Classified "IA risks geopolitical": ['ai', 'geopolitics', 'politics']
✅ Classified "Apple iPhone 16": ['tech', 'gadgets']
```

#### 2.11 Deploy & Monitor
```bash
cd packages/api
git add -A
git commit -m "Phase 2: Article-level ML theme classification

- Add content.theme column (ML-inferred)
- Enable classification_queue + worker
- Rebalance scoring weights for diversity
- Use description+title for richer context
- Backfill 50K existing articles

Phase 2 enables sources like LeMonde to surface relevant articles
based on actual content, not just source-level tags."

git push -u origin claude/phase-2-ml-theme
```

**On Railway:**
1. Ensure `ML_ENABLED=true` in env vars
2. Redeploy
3. Monitor dashboard:
   - Check classification_queue table
   - Watch CPU usage during backfill
   - Verify article themes appear in DB

#### 2.12 Verify Results
```bash
# Check that backfill completed
psql $DATABASE_URL -c "SELECT COUNT(*) as themed, COUNT(*) FILTER (WHERE theme IS NULL) as unthemed FROM contents;"

# Sample classified articles
psql $DATABASE_URL -c "SELECT title, theme, topics FROM contents WHERE theme IS NOT NULL LIMIT 10;"

# Test feed for your account
curl -H "Authorization: Bearer <token>" \
  "http://localhost:8080/api/feed/?limit=50" | jq '.[] | {source: .source.name, title: .title[:50], theme: .theme, topics: .topics}'
```

Expected:
- `themed` ≈ 50,000
- `unthemed` ≈ 0 (or very small)
- Feed includes more diverse sources (LeMonde, Courrier, etc.)
- Scoring breakdown shows "Thème article: tech" for LeMonde tech pieces

---

## 4. TESTING STRATEGY

### Phase 1 Test Cases
```python
# Test secondary theme lookup
async def test_secondary_theme_scoring():
    # User: {tech, science}
    # Source: theme=international, secondary_themes=[tech]
    # Article: title="IA regulation"
    # Expected: Scores +35 (THEME_MATCH * 0.7)
    pass

# Test secondary theme doesn't activate if primary matches
async def test_primary_theme_priority():
    # Source: theme=tech, secondary_themes=[science]
    # User interests: {tech}
    # Expected: Only primary theme bonus applied
    pass
```

### Phase 2 Test Cases
```python
# Test article.theme overrides source.theme
async def test_article_theme_priority():
    # Source theme: international
    # Article theme (ML): tech
    # Expected: Scores +50 (THEME_MATCH using article.theme)
    pass

# Test classification accuracy
async def test_classification_quality():
    # Sample 20 random classified articles
    # Manual check: Are themes reasonable?
    # Expected: 85%+ accuracy
    pass

# Test no regression in existing feeds
async def test_feed_quality_maintained():
    # Compare feed before/after Phase 2
    # Expected: Top 10 articles still relevant, just more diverse
    pass
```

---

## 5. ROLLBACK PLAN

If Phase 2 causes issues:

```bash
# Disable ML in env
ML_ENABLED=false

# Revert scoring config to old weights
git revert <commit-hash>

# The code will fall back to source.theme gracefully
# (content.theme ignored if NULL or classification fails)
```

---

## 6. SUCCESS METRICS

### Phase 1
- ✅ LeMonde visible in feeds (at least 3-5 articles in top 50)
- ✅ No API latency regression
- ✅ All tests pass

### Phase 2
- ✅ content.theme populated for >95% of articles
- ✅ Classification accuracy ≥85% (manual sampling)
- ✅ Feed diversity improves (% non-primary-theme articles ↑)
- ✅ User reports: "I see more varied sources now"
- ✅ API latency unchanged (<2ms)
- ✅ No Sentry errors in classification_worker

---

## 7. TIMELINE

| Phase | Task | Est. Time |
|-------|------|-----------|
| **1** | Migration + model update | 1.5h |
| **1** | CoreLayer logic + script | 0.5h |
| **1** | Testing + deployment | 0.5h |
| **2** | ML service + content.theme | 1.5h |
| **2** | Backfill script + run | 3h |
| **2** | Scoring rebalance + test | 1h |
| **2** | Deployment + monitoring | 1h |
| | **TOTAL** | **~8 hours (adjusted to 6h with parallelization)** |

**Suggested: Phase 1 this week, Phase 2 next week after user feedback.**

---

## 8. DEPENDENCIES & ASSUMPTIONS

- ✅ PostgreSQL with ARRAY types (already in use)
- ✅ HuggingFace Transformers library (optional, can download from hub)
- ✅ Railway container running (for background worker)
- ✅ Supabase with ML_ENABLED env var support
- ✅ No breaking API changes (backward compatible)

---

## 9. HAND-OFF CHECKLIST

Before starting implementation:

- [ ] Read this document entirely
- [ ] Review Phase 1 & 2 scope with PM
- [ ] Backup production database
- [ ] Create feature branch: `claude/phase-1-2-ml-themes`
- [ ] Set up local test environment
- [ ] Verify ML_ENABLED works in local .env

After Phase 1:
- [ ] Deploy to staging
- [ ] Test with your own account (boujon.laurin@gmail.com)
- [ ] Verify LeMonde articles visible
- [ ] Commit & request review

After Phase 2:
- [ ] Run backfill on staging first
- [ ] Monitor queue depth + CPU
- [ ] Sample 20 classified articles manually
- [ ] A/B test with user group if possible
- [ ] Deploy to production
- [ ] Monitor for 24h (Sentry, queue, API latency)

---

## 10. QUESTIONS & ESCALATION

If you encounter:

**"Model fails to load"**
→ Check HuggingFace token in Railway env
→ Ensure mDeBERTa-v3-base is accessible

**"Queue grows too fast"**
→ Reduce RSS_SYNC_INTERVAL_MINUTES
→ Increase worker concurrency

**"Classification accuracy is bad"**
→ Check description is being passed (not just title)
→ Try lower threshold (default 0.1)
→ Sample failed articles for pattern

**"Need to adjust weights further"**
→ Post-Phase-2, propose new weights
→ Run quick A/B test on user cohort

---

End of Hand-Off Document
