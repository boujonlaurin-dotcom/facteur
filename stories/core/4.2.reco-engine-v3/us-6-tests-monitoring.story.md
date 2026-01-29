# User Story 4.2-US-6 : Tests & Monitoring

**Parent Story:** [4.2.reco-engine-v3.story.md](./4.2.reco-engine-v3.story.md)  
**Status:** Draft  
**Priority:** P1 - High  
**Estimated Effort:** 2 days  
**Dependencies:** US-1 through US-5

---

## 🎯 Problem Statement

**Need:** Comprehensive testing and monitoring for production deployment

**Risks without proper testing:**
- ML model failures in production
- Silent scoring bugs (recommendations degrade)
- Performance degradation (slow feeds)
- Data inconsistencies

**Goal:** 
- 90%+ test coverage on new code
- Real-time monitoring dashboards
- Automated alerts for anomalies
- Performance benchmarks met

---

## 📋 Acceptance Criteria

### AC-1: Test Coverage
```gherkin
Given the new recommendation code
When tests run
Then coverage is >90% for:
  - ClassificationQueueService
  - ClassificationWorker
  - NERService
  - UserEntityService
  - EntityLayer
```

### AC-2: Performance Monitoring
```gherkin
Given the system is in production
When I check metrics
Then:
  - Classification avg time < 300ms
  - NER avg time < 50ms
  - Feed generation < 500ms
  - 95th percentile < 2x avg
```

### AC-3: Alerting
```gherkin
Given a production issue
When classification fails >5% of articles
Then an alert is sent
And the on-call is notified
```

### AC-4: End-to-End Tests
```gherkin
Given a complete user journey
When tests run
Then:
  - RSS sync → Queue → Classification → Scoring works
  - User reads article → Entities tracked
  - Feed reflects new interests
```

---

## 🔧 Implementation Tasks

### Task 1: Unit Tests (4h)

**File:** `packages/api/tests/recommendation/test_classification_queue.py`

```python
import pytest
from uuid import uuid4

class TestClassificationQueueService:
    """Test suite for queue service."""
    
    @pytest.mark.asyncio
    async def test_enqueue_creates_pending_item(self, session):
        """Test enqueue creates item with pending status."""
        service = ClassificationQueueService(session)
        content_id = uuid4()
        
        await service.enqueue(content_id, priority=5)
        
        item = await session.get(
            ClassificationQueue, 
            content_id  # or query by content_id
        )
        assert item.status == "pending"
        assert item.priority == 5
    
    @pytest.mark.asyncio
    async def test_dequeue_returns_pending_items(self, session):
        """Test dequeue returns only pending items."""
        service = ClassificationQueueService(session)
        
        # Create 3 pending, 1 processing
        for i in range(3):
            await service.enqueue(uuid4())
        
        processing_item = ClassificationQueue(
            content_id=uuid4(),
            status="processing",
        )
        session.add(processing_item)
        await session.commit()
        
        # Dequeue should return only pending
        items = await service.dequeue_batch(10)
        assert len(items) == 3
        assert all(i.status == "processing" for i in items)  # Marked as processing
    
    @pytest.mark.asyncio
    async def test_mark_completed_updates_content(self, session):
        """Test completed marks content with topics."""
        service = ClassificationQueueService(session)
        
        content = Content(title="Test")
        session.add(content)
        await session.flush()
        
        queue_item = ClassificationQueue(
            content_id=content.id,
            status="processing",
        )
        session.add(queue_item)
        await session.commit()
        
        await service.mark_completed(
            queue_item.id, 
            topics=["tech", "startups"]
        )
        
        await session.refresh(content)
        assert content.topics == ["tech", "startups"]
    
    @pytest.mark.asyncio
    async def test_retry_logic(self, session):
        """Test failed items are retried up to 3 times."""
        service = ClassificationQueueService(session)
        
        queue_item = ClassificationQueue(content_id=uuid4())
        session.add(queue_item)
        await session.commit()
        
        # Fail 3 times
        for _ in range(3):
            await service.mark_failed(queue_item.id, "Error")
            await session.refresh(queue_item)
            assert queue_item.status == "pending"  # Retried
        
        # 4th failure
        await service.mark_failed(queue_item.id, "Error")
        await session.refresh(queue_item)
        assert queue_item.status == "failed"  # Permanent
```

**File:** `packages/api/tests/ml/test_ner_service.py`

```python
import pytest

class TestNERService:
    """Test suite for NER service."""
    
    @pytest.mark.asyncio
    async def test_extract_person_entity(self):
        """Test extracting person."""
        ner = NERService()
        
        entities = await ner.extract_entities(
            title="Emmanuel Macron annonce des mesures"
        )
        
        persons = [e for e in entities if e.label == "PERSON"]
        assert any("Macron" in e.text for e in persons)
    
    @pytest.mark.asyncio
    async def test_extract_organization(self):
        """Test extracting organization."""
        ner = NERService()
        
        entities = await ner.extract_entities(
            title="Tesla construit une usine en Allemagne"
        )
        
        orgs = [e for e in entities if e.label == "ORG"]
        assert any("Tesla" in e.text for e in orgs)
    
    @pytest.mark.asyncio
    async def test_filters_common_words(self):
        """Test common words are filtered."""
        ner = NERService()
        
        entities = await ner.extract_entities(
            title="Le président et le ministre"
        )
        
        texts = [e.text.lower() for e in entities]
        assert "le" not in texts
        assert "et" not in texts
    
    @pytest.mark.asyncio
    async def test_performance_under_50ms(self):
        """Test NER completes in <50ms."""
        ner = NERService()
        
        import time
        start = time.time()
        
        await ner.extract_entities(
            title="Test article",
            description="Lorem ipsum " * 100,  # ~500 words
        )
        
        elapsed_ms = (time.time() - start) * 1000
        assert elapsed_ms < 50, f"NER took {elapsed_ms}ms"
```

### Task 2: Integration Tests (3h)

**File:** `packages/api/tests/integration/test_full_pipeline.py`

```python
import pytest

class TestFullClassificationPipeline:
    """End-to-end integration tests."""
    
    @pytest.mark.asyncio
    async def test_rss_sync_to_classification(self, client, db):
        """Test full flow: RSS → Queue → Classification."""
        # 1. Create source
        source = await create_test_source(
            name="Test Blog",
            feed_url="http://example.com/feed",
        )
        
        # 2. Mock RSS response
        mock_entries = [
            {
                "title": "Apple launches new iPhone",
                "link": "http://example.com/1",
                "published_parsed": time.gmtime(),
            }
        ]
        
        # 3. Run sync
        sync_service = SyncService(db)
        result = await sync_service.process_source(source)
        
        # 4. Verify article added to queue
        queue_items = await db.execute(
            select(ClassificationQueue)
        )
        assert queue_items.scalar_one_or_none() is not None
        
        # 5. Run worker
        worker = ClassificationWorker()
        await worker.process_batch()
        
        # 6. Verify article classified
        content = await db.execute(
            select(Content).where(Content.title == "Apple launches new iPhone")
        )
        article = content.scalar_one()
        assert article.topics is not None
        assert len(article.topics) > 0
    
    @pytest.mark.asyncio
    async def test_user_read_tracking(self, client, db):
        """Test: User reads → Entities tracked → Feed updated."""
        # 1. Create user
        user = await create_test_user()
        
        # 2. Create article with entities
        article = await create_test_content(
            title="Tesla stock rises",
            entities=[{"text": "Tesla", "label": "ORG"}],
        )
        
        # 3. User reads article
        await client.post(
            f"/api/contents/{article.id}/read",
            headers={"Authorization": f"Bearer {user.token}"},
        )
        
        # 4. Verify entity tracked
        entity_service = UserEntityService(db)
        user_entities = await entity_service.get_user_entities(user.id)
        
        assert len(user_entities) == 1
        assert user_entities[0].entity_text == "Tesla"
        assert user_entities[0].score == 5
    
    @pytest.mark.asyncio
    async def test_feed_includes_entity_scores(self, client, db):
        """Test feed scoring includes entity matches."""
        # 1. Setup user with entity interest
        user = await create_test_user()
        entity_service = UserEntityService(db)
        
        # Manually add entity interest
        await entity_service._update_entity(
            user.id, "SpaceX", "ORG"
        )
        # Read 2 more times to boost score
        await entity_service._update_entity(user.id, "SpaceX", "ORG")
        await entity_service._update_entity(user.id, "SpaceX", "ORG")
        
        # 2. Create article mentioning SpaceX
        article = await create_test_content(
            title="SpaceX launches rocket",
            entities=[{"text": "SpaceX", "label": "ORG"}],
        )
        
        # 3. Get feed
        response = await client.get(
            "/api/feed",
            headers={"Authorization": f"Bearer {user.token}"},
        )
        
        # 4. Verify article in feed with entity reason
        feed_items = response.json()["items"]
        spacex_article = next(
            (i for i in feed_items if i["id"] == str(article.id)),
            None
        )
        
        assert spacex_article is not None
        assert any(
            "SpaceX" in r["label"] 
            for r in spacex_article.get("recommendation_reasons", [])
        )
```

### Task 3: Performance Tests (2h)

**File:** `packages/api/tests/performance/test_classification_perf.py`

```python
import pytest
import time
import statistics

class TestClassificationPerformance:
    """Performance benchmarks."""
    
    @pytest.mark.asyncio
    async def test_classification_latency(self):
        """Benchmark classification latency."""
        classifier = ClassificationService()
        
        latencies = []
        for _ in range(100):
            start = time.time()
            await classifier.classify_async(
                title="Test article about technology and startups",
            )
            latencies.append((time.time() - start) * 1000)
        
        avg_latency = statistics.mean(latencies)
        p95_latency = sorted(latencies)[int(len(latencies) * 0.95)]
        
        print(f"Avg: {avg_latency:.1f}ms, P95: {p95_latency:.1f}ms")
        
        assert avg_latency < 300, f"Avg latency {avg_latency}ms too high"
        assert p95_latency < 500, f"P95 latency {p95_latency}ms too high"
    
    @pytest.mark.asyncio
    async def test_ner_latency(self):
        """Benchmark NER latency."""
        ner = NERService()
        
        test_texts = [
            "Short title",
            "Medium length title with some description",
            "Long article " * 100,
        ]
        
        for text in test_texts:
            start = time.time()
            await ner.extract_entities(title=text[:100], description=text)
            elapsed = (time.time() - start) * 1000
            
            assert elapsed < 50, f"NER took {elapsed}ms for text length {len(text)}"
    
    @pytest.mark.asyncio
    async def test_feed_generation_latency(self, client):
        """Benchmark feed generation."""
        # Generate feed 10 times
        latencies = []
        for _ in range(10):
            start = time.time()
            await client.get("/api/feed")
            latencies.append((time.time() - start) * 1000)
        
        avg = statistics.mean(latencies)
        assert avg < 500, f"Feed generation avg {avg}ms too slow"
```

### Task 4: Monitoring Dashboard (3h)

**File:** `packages/api/app/routers/monitoring.py`

```python
"""
Monitoring endpoints for production observability.
"""

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.services.ml.classification_service import get_classification_service
from app.services.ml.ner_service import get_ner_service

router = APIRouter(prefix="/monitoring", tags=["monitoring"])


@router.get("/health")
async def health_check(session: AsyncSession = Depends(get_session)):
    """Basic health check."""
    # Check DB connection
    await session.execute(select(1))
    
    # Check ML services
    classifier = get_classification_service()
    ner = get_ner_service()
    
    return {
        "status": "healthy",
        "database": "connected",
        "ml_classifier": "ready" if classifier.is_ready() else "not_loaded",
        "ner_service": "ready" if ner.is_ready() else "not_loaded",
    }


@router.get("/metrics")
async def get_metrics(session: AsyncSession = Depends(get_session)):
    """Get system metrics."""
    
    # Queue metrics
    queue_stats = await session.execute(
        select(
            ClassificationQueue.status,
            func.count().label('count')
        ).group_by(ClassificationQueue.status)
    )
    queue_metrics = {row.status: row.count for row in queue_stats}
    
    # Processing time (last 24h)
    time_result = await session.execute(
        select(
            func.avg(
                func.extract('epoch', ClassificationQueue.processed_at) - 
                func.extract('epoch', ClassificationQueue.created_at)
            ).label('avg_seconds')
        ).where(
            ClassificationQueue.status == 'completed',
            ClassificationQueue.processed_at >= func.now() - timedelta(hours=24)
        )
    )
    avg_processing_time = time_result.scalar() or 0
    
    # Content metrics
    content_stats = await session.execute(
        select(
            func.count().label('total'),
            func.count(Content.topics).label('with_topics'),
            func.count(Content.entities).label('with_entities'),
        )
    )
    content_row = content_stats.one()
    
    return {
        "queue": queue_metrics,
        "avg_classification_time_sec": round(avg_processing_time, 2),
        "content": {
            "total": content_row.total,
            "with_topics": content_row.with_topics,
            "with_entities": content_row.with_entities,
            "classification_rate": round(
                content_row.with_topics / content_row.total * 100, 1
            ) if content_row.total > 0 else 0,
        },
    }


@router.get("/alerts")
async def get_alerts(session: AsyncSession = Depends(get_session)):
    """Get current alerts/warnings."""
    alerts = []
    
    # Check for high failure rate
    failure_result = await session.execute(
        select(func.count()).where(
            ClassificationQueue.status == 'failed'
        )
    )
    failed_count = failure_result.scalar()
    
    total_result = await session.execute(
        select(func.count()).where(
            ClassificationQueue.status.in_(['completed', 'failed'])
        )
    )
    total_processed = total_result.scalar()
    
    if total_processed > 0:
        failure_rate = failed_count / total_processed
        if failure_rate > 0.05:  # >5% failure rate
            alerts.append({
                "level": "warning",
                "message": f"High classification failure rate: {failure_rate:.1%}",
                "metric": "failure_rate",
                "value": failure_rate,
            })
    
    # Check for queue backlog
    pending_result = await session.execute(
        select(func.count()).where(
            ClassificationQueue.status == 'pending'
        )
    )
    pending_count = pending_result.scalar()
    
    if pending_count > 1000:
        alerts.append({
            "level": "warning",
            "message": f"Large queue backlog: {pending_count} pending items",
            "metric": "queue_backlog",
            "value": pending_count,
        })
    
    return {"alerts": alerts}
```

### Task 5: Alerting Configuration (1h)

**File:** `packages/api/scripts/setup_alerts.py` (or integrate with Sentry/Monitoring tool)

```python
"""
Setup monitoring alerts.
Can be integrated with Sentry, Datadog, or custom alerting.
"""

import structlog
from datetime import datetime

logger = structlog.get_logger()

# Alert thresholds
THRESHOLDS = {
    "classification_failure_rate": 0.05,  # 5%
    "classification_latency_p95": 500,    # 500ms
    "queue_backlog": 1000,                # 1000 items
    "ner_latency_p95": 100,               # 100ms
}


async def check_alerts(session):
    """Check metrics and trigger alerts if needed."""
    from sqlalchemy import func
    from app.models.classification_queue import ClassificationQueue
    
    # Check failure rate
    result = await session.execute(
        select(
            func.count().filter(ClassificationQueue.status == 'failed'),
            func.count().filter(ClassificationQueue.status.in_(['completed', 'failed']))
        )
    )
    failed, total = result.one()
    
    if total > 0:
        failure_rate = failed / total
        if failure_rate > THRESHOLDS["classification_failure_rate"]:
            await send_alert(
                level="error",
                title="High Classification Failure Rate",
                message=f"{failure_rate:.1%} of classifications failed",
            )
    
    # Check queue backlog
    backlog_result = await session.execute(
        select(func.count()).where(ClassificationQueue.status == 'pending')
    )
    backlog = backlog_result.scalar()
    
    if backlog > THRESHOLDS["queue_backlog"]:
        await send_alert(
            level="warning",
            title="Classification Queue Backlog",
            message=f"{backlog} items pending in queue",
        )


async def send_alert(level: str, title: str, message: str):
    """Send alert to configured channels."""
    logger.error(f"ALERT [{level.upper()}]: {title} - {message}")
    
    # TODO: Integrate with:
    # - Sentry
    # - Slack/Discord webhook
    # - PagerDuty (for critical)
    # - Email
    
    # Example Sentry integration:
    # import sentry_sdk
    # sentry_sdk.capture_message(f"{title}: {message}", level=level)
```

---

## 📁 Test Structure

```
tests/
├── recommendation/
│   ├── test_classification_queue.py    # Queue service tests
│   ├── test_entity_layer.py            # Entity scoring tests
│   └── test_scoring_integration.py     # Full scoring tests
├── ml/
│   ├── test_classification_service.py  # mDeBERTa tests
│   ├── test_ner_service.py             # spaCy NER tests
│   └── test_ml_integration.py          # End-to-end ML
├── integration/
│   └── test_full_pipeline.py           # Full system tests
├── performance/
│   ├── test_classification_perf.py     # Performance benchmarks
│   └── test_feed_latency.py            # Feed timing tests
└── conftest.py                         # Shared fixtures
```

---

## 📊 Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Code coverage | >90% | pytest-cov |
| Classification latency | <300ms avg | Monitoring endpoint |
| Classification latency P95 | <500ms | Monitoring endpoint |
| NER latency | <50ms avg | Monitoring endpoint |
| Feed generation | <500ms | Performance tests |
| Failure rate | <5% | Alerting |
| Test pass rate | 100% | CI/CD |

---

## 🚀 Running Tests

```bash
# Unit tests
pytest tests/recommendation tests/ml -v

# Integration tests
pytest tests/integration -v

# Performance tests
pytest tests/performance -v --benchmark-only

# With coverage
pytest --cov=app --cov-report=html --cov-report=term

# Specific test
pytest tests/ml/test_ner_service.py::TestNERService::test_extract_person_entity -v
```

---

*Story created: 2026-01-29*  
*Part of: Recommendation Engine V3*
