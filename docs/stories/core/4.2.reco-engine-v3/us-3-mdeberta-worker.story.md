# User Story 4.2-US-3 : Integrate mDeBERTa in Worker

**Parent Story:** [4.2.reco-engine-v3.story.md](./4.2.reco-engine-v3.story.md)  
**Status:** Draft  
**Priority:** P0 - Critical  
**Estimated Effort:** 2 days  
**Dependencies:** US-2 (Async Queue Architecture)

---

## 🎯 Problem Statement

**Current State:** 
- The `ClassificationService` with mDeBERTa exists and is fully implemented
- It's never called during RSS sync (ml_enabled is False)
- Articles are saved without ML classification
- Feed uses `source.granular_topics` as fallback (static, imprecise)

**Goal:** 
- Activate mDeBERTa classification in the worker
- Enable `ml_enabled` flag in production
- Process 1000+ articles/day with <300ms latency each

---

## 📋 Acceptance Criteria

### AC-1: mDeBERTa Activation
```gherkin
Given the ml_enabled flag is set to True
When the API starts
Then the mDeBERTa model loads in memory (~500MB)
And classification service is ready
```

### AC-2: Article Classification
```gherkin
Given an article in the classification queue
When the worker processes it
Then mDeBERTa classifies the content
And returns 1-3 relevant topics
And stores them in content.topics
```

### AC-3: Processing Time
```gherkin
Given an article with title and description
When classification runs
Then processing completes within 300ms
And 95th percentile < 500ms
```

### AC-4: Fallback Mechanism
```gherkin
Given mDeBERTa returns empty results
When the classification completes
Then the article uses source.granular_topics as fallback
And is marked with fallback flag
```

### AC-5: Error Recovery
```gherkin
Given mDeBERTa throws an exception
When processing an article
Then the error is logged
And the article is retried (up to 3 times)
And if all retries fail, uses fallback
```

---

## 🏗️ Technical Architecture

### mDeBERTa Integration Flow

```
ClassificationWorker
    │
    ▼
┌─────────────────────┐
│ Get Pending Article │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Fetch Content       │
│ (title + desc)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ mDeBERTa Pipeline   │
│ Zero-shot           │
│ classification      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Map to slugs        │
│ (47 topics)         │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Store in DB         │
│ content.topics      │
└─────────────────────┘
```

### mDeBERTa Configuration

**Model:** `MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7`

**Why this model?**
- Multilingual (French optimized)
- Zero-shot classification (no training needed)
- Specifically trained for NLI (Natural Language Inference)
- ~500MB RAM, ~200ms/article on CPU

**Parameters:**
```python
{
    "task": "zero-shot-classification",
    "model": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
    "device": -1,  # CPU
    "batch_size": 1,  # Process one by one for queue
}
```

---

## 🔧 Implementation Tasks

### Task 1: Activate ML Configuration (1h)

**File:** `packages/api/.env` (or environment config)

```bash
# Enable ML classification
ML_ENABLED=true

# Optional: Model caching
TRANSFORMERS_CACHE=/tmp/transformers_cache
```

**File:** `packages/api/app/config.py` (verify)

Already exists:
```python
ml_enabled: bool = False  # Set via env var ML_ENABLED
```

Just need to set `ML_ENABLED=true` in environment.

### Task 2: Enhance ClassificationService (3h)

**File:** `packages/api/app/services/ml/classification_service.py`

**Current:** Service exists but may need optimizations for production.

**Enhancements:**

```python
class ClassificationService:
    """
    Production-ready classification service.
    """
    
    # 47 candidate labels (existing)
    CANDIDATE_LABELS_FR = [...]  # Already defined
    LABEL_TO_SLUG = {...}  # Already defined
    
    def __init__(self):
        self.classifier: Pipeline | None = None
        self._model_loaded = False
        self._lock = asyncio.Lock()
        
        settings = get_settings()
        if settings.ml_enabled:
            self._load_model()
    
    def _load_model(self):
        """Load model with error handling."""
        try:
            from transformers import pipeline
            
            logger.info("classification.loading_model", 
                       model="mDeBERTa-v3-base-xnli")
            
            self.classifier = pipeline(
                task="zero-shot-classification",
                model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
                device=-1,  # CPU
                batch_size=1,
            )
            
            self._model_loaded = True
            logger.info("classification.model_loaded")
            
        except Exception as e:
            logger.error("classification.load_failed", error=str(e))
            raise RuntimeError(f"Failed to load ML model: {e}")
    
    async def classify_async(
        self,
        title: str,
        description: str = "",
        top_k: int = 3,
        threshold: float = 0.3,
    ) -> list[str]:
        """
        Async wrapper for classification.
        Runs the blocking classifier in thread pool.
        """
        if not self.classifier:
            logger.warning("classification.not_loaded")
            return []
        
        loop = asyncio.get_event_loop()
        
        # Run in thread pool to not block event loop
        return await loop.run_in_executor(
            None,  # Default executor
            self._classify_sync,
            title,
            description,
            top_k,
            threshold,
        )
    
    def _classify_sync(
        self,
        title: str,
        description: str,
        top_k: int,
        threshold: float,
    ) -> list[str]:
        """Synchronous classification (runs in thread)."""
        text = f"{title}. {description}".strip() if description else title
        
        if not text:
            return []
        
        try:
            start_time = time.time()
            
            result = self.classifier(
                text,
                candidate_labels=self.CANDIDATE_LABELS_FR,
                multi_label=True,
            )
            
            elapsed = time.time() - start_time
            
            # Extract topics above threshold
            topics = []
            for label, score in zip(result["labels"], result["scores"]):
                if score >= threshold and len(topics) < top_k:
                    slug = self.LABEL_TO_SLUG.get(label)
                    if slug:
                        topics.append(slug)
            
            logger.debug(
                "classification.success",
                text=text[:100],
                topics=topics,
                elapsed_ms=elapsed * 1000,
            )
            
            return topics
            
        except Exception as e:
            logger.error("classification.error", error=str(e))
            return []
    
    def get_stats(self) -> dict:
        """Get model stats."""
        return {
            "model_loaded": self._model_loaded,
            "model_name": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
            "candidate_labels_count": len(self.CANDIDATE_LABELS_FR),
        }
```

### Task 3: Integrate in ClassificationWorker (4h)

**File:** `packages/api/app/workers/classification_worker.py` (update)

```python
class ClassificationWorker:
    """
    Enhanced worker with mDeBERTa integration.
    """
    
    def __init__(self):
        self.running = False
        self.batch_size = 10
        self.poll_interval = 30
        self.classifier = get_classification_service()
        self.metrics = {
            "processed": 0,
            "failed": 0,
            "avg_time_ms": 0,
        }
    
    async def process_batch(self) -> int:
        """Process batch with mDeBERTa classification."""
        async with AsyncSessionLocal() as session:
            queue_service = ClassificationQueueService(session)
            
            # Get pending items
            items = await queue_service.dequeue_batch(self.batch_size)
            
            if not items:
                return 0
            
            logger.info("worker.processing_batch", count=len(items))
            
            for item in items:
                try:
                    start_time = time.time()
                    
                    # Get content
                    content = await session.get(Content, item.content_id)
                    if not content:
                        await queue_service.mark_failed(
                            item.id, "Content not found"
                        )
                        continue
                    
                    # Classify with mDeBERTa
                    topics = await self._classify_content(content)
                    
                    # Mark completed
                    await queue_service.mark_completed(item.id, topics)
                    
                    # Update metrics
                    elapsed_ms = (time.time() - start_time) * 1000
                    self._update_metrics(elapsed_ms)
                    
                    logger.debug(
                        "worker.item_processed",
                        content_id=str(content.id),
                        topics=topics,
                        elapsed_ms=elapsed_ms,
                    )
                
                except Exception as e:
                    logger.error(
                        "worker.item_failed",
                        content_id=str(item.content_id),
                        error=str(e),
                    )
                    await queue_service.mark_failed(item.id, str(e))
            
            return len(items)
    
    async def _classify_content(self, content: Content) -> list[str]:
        """Classify a single content with fallback."""
        topics = []
        
        # Try mDeBERTa classification
        if self.classifier and self.classifier.is_ready():
            topics = await self.classifier.classify_async(
                title=content.title,
                description=content.description or "",
                top_k=3,
                threshold=0.3,
            )
        
        # Fallback to source topics if ML fails or returns empty
        if not topics and content.source and content.source.granular_topics:
            topics = content.source.granular_topics
            logger.debug(
                "worker.using_fallback",
                content_id=str(content.id),
                topics=topics,
            )
        
        return topics
    
    def _update_metrics(self, elapsed_ms: float):
        """Update running metrics."""
        self.metrics["processed"] += 1
        # Running average
        n = self.metrics["processed"]
        self.metrics["avg_time_ms"] = (
            (self.metrics["avg_time_ms"] * (n - 1)) + elapsed_ms
        ) / n
```

### Task 4: Add Monitoring & Health Checks (2h)

**File:** `packages/api/app/routers/admin.py` (new or update)

```python
@router.get("/admin/ml-status")
async def get_ml_status():
    """Get ML classification status."""
    classifier = get_classification_service()
    
    return {
        "enabled": classifier.is_ready(),
        "model_loaded": classifier._model_loaded,
        "model_name": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
        "stats": classifier.get_stats(),
    }

@router.get("/admin/classification-metrics")
async def get_classification_metrics():
    """Get classification metrics."""
    # Get from worker or compute from DB
    async with AsyncSessionLocal() as session:
        # Queue stats
        queue_stats = await session.execute(
            select(
                ClassificationQueue.status,
                func.count().label('count')
            ).group_by(ClassificationQueue.status)
        )
        
        # Processing time stats (last 24h)
        time_stats = await session.execute(
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
        
        return {
            "queue": {row.status: row.count for row in queue_stats},
            "avg_processing_time_sec": time_stats.scalar() or 0,
        }
```

### Task 5: Testing (2h)

**File:** `packages/api/tests/ml/test_classification_integration.py`

```python
import pytest

@pytest.mark.asyncio
async def test_classify_real_article():
    """Test classification of a real article."""
    classifier = ClassificationService()
    
    topics = await classifier.classify_async(
        title="Elon Musk annonce Neuralink pour contrôler l'iPhone par la pensée",
        description="La startup de neurotechnologie veut révolutionner...",
    )
    
    # Should detect tech/science topics
    assert len(topics) > 0
    assert any(t in ["tech", "science"] for t in topics)

@pytest.mark.asyncio
async def test_classification_performance():
    """Test classification performance (<300ms)."""
    classifier = ClassificationService()
    
    import time
    start = time.time()
    
    await classifier.classify_async(
        title="Test article about technology",
        description="This is a test description",
    )
    
    elapsed_ms = (time.time() - start) * 1000
    assert elapsed_ms < 300, f"Classification took {elapsed_ms}ms"

@pytest.mark.asyncio
async def test_worker_end_to_end():
    """Test worker processes article end-to-end."""
    # Create test content
    content = await create_test_content(
        title="Apple launches new iPhone",
        description="The latest smartphone from Apple...",
    )
    
    # Enqueue
    await queue_service.enqueue(content.id)
    
    # Run worker
    worker = ClassificationWorker()
    processed = await worker.process_batch()
    
    assert processed == 1
    
    # Check content has topics
    await session.refresh(content)
    assert content.topics is not None
    assert len(content.topics) > 0
    assert "tech" in content.topics
```

---

## 📁 Files Modified

| File | Type | Description |
|------|------|-------------|
| `.env` | Modified | Enable ML_ENABLED=true |
| `app/services/ml/classification_service.py` | Modified | Add async wrapper, stats |
| `app/workers/classification_worker.py` | Modified | Integrate classifier |
| `app/routers/admin.py` | Created/Modified | ML status endpoints |
| `tests/ml/test_classification_integration.py` | Created | Integration tests |

---

## 🚀 Deployment Checklist

- [ ] Set `ML_ENABLED=true` in environment
- [ ] Verify 500MB+ RAM available
- [ ] Deploy code
- [ ] Check `/admin/ml-status` endpoint
- [ ] Verify model loads successfully
- [ ] Run integration tests
- [ ] Monitor first 100 classifications
- [ ] Check average processing time <300ms

---

## 📊 Performance Targets

| Metric | Target | Current (Expected) |
|--------|--------|-------------------|
| Classification time | <300ms | ~200ms |
| RAM usage | <600MB | ~500MB |
| Throughput | 1000/day | ~170/hour (serial) |
| Accuracy | >80% | 85-90% |

---

## ⚠️ Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Model fails to load | High | Fallback to source topics; alert on-call |
| OOM (RAM) | High | Monitor memory; scale plan if needed |
| Slow processing | Medium | Batch size 10; parallel workers if needed |
| Low accuracy | Medium | Tune threshold; add fallback logic |

---

*Story created: 2026-01-29*  
*Part of: Recommendation Engine V3*
