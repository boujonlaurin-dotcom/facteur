# User Story 4.2-US-2 : Async Queue Architecture

**Parent Story:** [4.2.reco-engine-v3.story.md](./4.2.reco-engine-v3.story.md)  
**Status:** Draft  
**Priority:** P0 - Critical  
**Estimated Effort:** 2 days  
**Dependencies:** US-1 (Fix Theme Matching)

---

## 🎯 Problem Statement

**Current Issue:** RSS sync is synchronous and blocking
- Each article classification takes ~200ms with mDeBERTa
- Syncing 50 articles = 10 seconds of blocking time
- Syncing 500 articles = 1 minute 40 seconds of blocking
- API becomes unresponsive during large syncs

**Goal:** Decouple RSS sync from ML classification to enable:
- Fast sync (< 2s regardless of article count)
- Background ML processing
- Scalability to 1000+ articles/day

---

## 📋 Acceptance Criteria

### AC-1: Fast RSS Sync
```gherkin
Given a RSS sync imports 100 new articles
When the sync process runs
Then all articles are saved within 2 seconds
And the API remains responsive
```

### AC-2: Classification Queue
```gherkin
Given articles are saved during RSS sync
When the sync completes
Then articles are added to the classification queue
With status="pending"
```

### AC-3: Async Worker
```gherkin
Given articles in the classification queue
When the background worker runs
Then it processes articles asynchronously
And updates content.topics after classification
```

### AC-4: Error Handling
```gherkin
Given an article fails classification
When the error occurs
Then the article is marked status="failed"
And retry count is incremented
And the article is retried up to 3 times
```

### AC-5: Fallback Mechanism
```gherkin
Given an article in the feed with no topics yet
When the recommendation engine scores it
Then it uses source.granular_topics as fallback
And the article is not excluded from feed
```

---

## 🏗️ Architecture Design

### Data Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   RSS Sync  │────▶│  Save to DB │────▶│ Add to Queue    │
│             │     │ (no topics) │     │ (status=pending)│
└─────────────┘     └─────────────┘     └─────────────────┘
                                                   │
                                                   ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│   Update DB │◀────│  Classify   │◀────│ Worker Picks    │
│  (topics)   │     │   (ML/NER)  │     │ (status=processing)│
└─────────────┘     └─────────────┘     └─────────────────┘
```

### Database Schema

**Table: `classification_queue`**
```sql
CREATE TABLE classification_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id UUID NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    priority INTEGER DEFAULT 0, -- Higher = process first
    retry_count INTEGER DEFAULT 0,
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    
    UNIQUE(content_id)
);

CREATE INDEX idx_queue_status_created ON classification_queue(status, created_at);
CREATE INDEX idx_queue_priority ON classification_queue(priority DESC, created_at);
```

**Table: `contents` (modified)**
```sql
-- Add nullable topics column if not exists
ALTER TABLE contents ADD COLUMN IF NOT EXISTS topics JSONB DEFAULT NULL;

-- Add index for querying
CREATE INDEX idx_contents_topics ON contents USING GIN(topics);
```

### State Machine

```
[pending] ──▶ [processing] ──▶ [completed]
     │              │
     │              └───▶ [failed] ──▶ [pending] (if retry < 3)
     │                         │
     │                         └───▶ [failed] (permanent, if retry >= 3)
     │
     └───▶ [cancelled] (if content deleted)
```

---

## 🔧 Implementation Tasks

### Task 1: Database Migration (3h)

**File:** `packages/api/alembic/versions/xxx_create_classification_queue.py`

```python
def upgrade():
    # Create classification queue table
    op.create_table(
        'classification_queue',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('content_id', postgresql.UUID(as_uuid=True), 
                  sa.ForeignKey('contents.id', ondelete='CASCADE'), 
                  nullable=False, unique=True),
        sa.Column('status', sa.String(20), nullable=False, 
                  server_default='pending'),
        sa.Column('priority', sa.Integer, server_default='0'),
        sa.Column('retry_count', sa.Integer, server_default='0'),
        sa.Column('error_message', sa.Text, nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), 
                  server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(timezone=True), 
                  server_default=sa.func.now(), 
                  onupdate=sa.func.now()),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
    )
    
    # Create indexes
    op.create_index('idx_queue_status_created', 'classification_queue', 
                    ['status', 'created_at'])
    op.create_index('idx_queue_priority', 'classification_queue', 
                    ['priority DESC', 'created_at'])
    
    # Add topics column to contents if not exists
    op.add_column('contents', 
                  sa.Column('topics', postgresql.JSONB, nullable=True))
    
    # Create GIN index for topics
    op.create_index('idx_contents_topics', 'contents', ['topics'], 
                    postgresql_using='gin')
```

### Task 2: Queue Service (4h)

**File:** `packages/api/app/services/classification_queue_service.py`

```python
class ClassificationQueueService:
    """Service for managing the classification queue."""
    
    async def enqueue(self, content_id: UUID, priority: int = 0) -> None:
        """Add a content to the classification queue."""
        query = insert(ClassificationQueue).values(
            content_id=content_id,
            status='pending',
            priority=priority,
        ).on_conflict_do_nothing(
            index_elements=['content_id']
        )
        await self.session.execute(query)
        await self.session.commit()
    
    async def dequeue_batch(self, batch_size: int = 10) -> List[ClassificationQueue]:
        """Get next batch of pending items (atomic operation)."""
        # Use SELECT FOR UPDATE to prevent race conditions
        query = (
            select(ClassificationQueue)
            .where(ClassificationQueue.status == 'pending')
            .order_by(ClassificationQueue.priority.desc(),
                     ClassificationQueue.created_at)
            .limit(batch_size)
            .with_for_update(skip_locked=True)
        )
        
        result = await self.session.execute(query)
        items = result.scalars().all()
        
        # Mark as processing
        for item in items:
            item.status = 'processing'
            item.updated_at = datetime.utcnow()
        
        await self.session.commit()
        return items
    
    async def mark_completed(self, queue_id: UUID, topics: List[str]) -> None:
        """Mark item as completed with topics."""
        item = await self.session.get(ClassificationQueue, queue_id)
        if item:
            item.status = 'completed'
            item.processed_at = datetime.utcnow()
            item.updated_at = datetime.utcnow()
            
            # Update content with topics
            content = await self.session.get(Content, item.content_id)
            if content:
                content.topics = topics
            
            await self.session.commit()
    
    async def mark_failed(self, queue_id: UUID, error: str) -> None:
        """Mark item as failed with retry logic."""
        item = await self.session.get(ClassificationQueue, queue_id)
        if item:
            item.retry_count += 1
            item.error_message = error
            item.updated_at = datetime.utcnow()
            
            if item.retry_count >= 3:
                item.status = 'failed'
            else:
                item.status = 'pending'  # Will be retried
            
            await self.session.commit()
    
    async def get_queue_stats(self) -> dict:
        """Get queue statistics for monitoring."""
        stats = await self.session.execute(
            select(
                ClassificationQueue.status,
                func.count().label('count')
            ).group_by(ClassificationQueue.status)
        )
        return {row.status: row.count for row in stats}
```

### Task 3: Classification Worker (4h)

**File:** `packages/api/app/workers/classification_worker.py`

```python
import asyncio
import structlog
from typing import List

from app.services.classification_queue_service import ClassificationQueueService
from app.services.ml.classification_service import get_classification_service
from app.database import AsyncSessionLocal

logger = structlog.get_logger()

class ClassificationWorker:
    """Background worker for ML classification."""
    
    def __init__(self):
        self.running = False
        self.batch_size = 10
        self.poll_interval = 30  # seconds
    
    async def start(self):
        """Start the worker loop."""
        self.running = True
        logger.info("classification_worker.started")
        
        while self.running:
            try:
                processed = await self.process_batch()
                if processed == 0:
                    # No items, wait before polling again
                    await asyncio.sleep(self.poll_interval)
            except Exception as e:
                logger.error("classification_worker.error", error=str(e))
                await asyncio.sleep(self.poll_interval)
    
    async def process_batch(self) -> int:
        """Process a batch of pending items."""
        async with AsyncSessionLocal() as session:
            queue_service = ClassificationQueueService(session)
            classifier = get_classification_service()
            
            # Get pending items
            items = await queue_service.dequeue_batch(self.batch_size)
            
            if not items:
                return 0
            
            logger.info("classification_worker.processing", 
                       count=len(items))
            
            for item in items:
                try:
                    # Get content
                    content = await session.get(Content, item.content_id)
                    if not content:
                        logger.warning("classification_worker.content_not_found",
                                     content_id=str(item.content_id))
                        await queue_service.mark_failed(
                            item.id, "Content not found"
                        )
                        continue
                    
                    # Classify
                    topics = classifier.classify(
                        title=content.title,
                        description=content.description or "",
                        top_k=3,
                        threshold=0.3
                    )
                    
                    # Mark completed
                    await queue_service.mark_completed(item.id, topics)
                    
                    logger.debug("classification_worker.success",
                               content_id=str(item.content_id),
                               topics=topics)
                
                except Exception as e:
                    logger.error("classification_worker.item_failed",
                               content_id=str(item.content_id),
                               error=str(e))
                    await queue_service.mark_failed(item.id, str(e))
            
            return len(items)
    
    async def stop(self):
        """Stop the worker gracefully."""
        self.running = False
        logger.info("classification_worker.stopped")
```

### Task 4: Modify SyncService (3h)

**File:** `packages/api/app/services/sync_service.py`

**Changes in `_save_content()`:**

```python
async def _save_content(self, content_data: dict) -> bool:
    """Save content and add to classification queue."""
    # ... existing logic ...
    
    # Insert content without topics (will be set by worker)
    content = Content(
        **content_data,
        topics=None  # Will be set by classification worker
    )
    
    self.session.add(content)
    await self.session.flush()  # Get content.id
    
    # Add to classification queue
    from app.services.classification_queue_service import ClassificationQueueService
    queue_service = ClassificationQueueService(self.session)
    
    # Priority: Higher for recent articles
    priority = 0
    if content_data.get('published_at'):
        hours_old = (datetime.utcnow() - content_data['published_at']).total_seconds() / 3600
        if hours_old < 24:
            priority = 10  # Recent articles
        elif hours_old < 72:
            priority = 5   # 1-3 days old
    
    await queue_service.enqueue(content.id, priority=priority)
    
    await self.session.commit()
    return True
```

### Task 5: Worker Lifecycle Management (2h)

**File:** `packages/api/app/main.py` (modifications)

```python
from app.workers.classification_worker import ClassificationWorker

# Global worker instance
classification_worker: ClassificationWorker | None = None

@app.on_event("startup")
async def startup_event():
    # ... existing startup code ...
    
    # Start classification worker if ML is enabled
    settings = get_settings()
    if settings.ml_enabled:
        global classification_worker
        classification_worker = ClassificationWorker()
        # Run in background task
        asyncio.create_task(classification_worker.start())
        logger.info("classification_worker.started_on_startup")

@app.on_event("shutdown")
async def shutdown_event():
    # ... existing shutdown code ...
    
    # Stop classification worker
    if classification_worker:
        await classification_worker.stop()
        logger.info("classification_worker.stopped_on_shutdown")
```

---

## 🧪 Testing Strategy

### Unit Tests
```python
async def test_enqueue_creates_queue_item():
    """Test that enqueue creates a queue item."""
    content_id = uuid4()
    await queue_service.enqueue(content_id, priority=5)
    
    item = await session.execute(
        select(ClassificationQueue).where(
            ClassificationQueue.content_id == content_id
        )
    )
    assert item.scalar_one().status == 'pending'

async def test_dequeue_batch_atomic():
    """Test that dequeue marks items as processing."""
    # Create 5 pending items
    for i in range(5):
        await queue_service.enqueue(uuid4())
    
    # Dequeue 3
    items = await queue_service.dequeue_batch(3)
    assert len(items) == 3
    
    # All marked as processing
    for item in items:
        assert item.status == 'processing'
```

### Integration Tests
```python
async def test_worker_processes_queue():
    """Test end-to-end worker processing."""
    # Create content and enqueue
    content = create_test_content()
    await queue_service.enqueue(content.id)
    
    # Run worker once
    worker = ClassificationWorker()
    processed = await worker.process_batch()
    
    assert processed == 1
    
    # Check content has topics
    await session.refresh(content)
    assert content.topics is not None
    assert len(content.topics) > 0
```

---

## 📁 Files Created/Modified

| File | Type | Description |
|------|------|-------------|
| `alembic/versions/xxx_create_classification_queue.py` | Created | DB migration |
| `app/models/classification_queue.py` | Created | SQLAlchemy model |
| `app/services/classification_queue_service.py` | Created | Queue management |
| `app/workers/classification_worker.py` | Created | Background worker |
| `app/services/sync_service.py` | Modified | Add to queue on sync |
| `app/main.py` | Modified | Worker lifecycle |
| `tests/test_classification_queue.py` | Created | Unit tests |

---

## 🚀 Deployment

### Local Testing
```bash
# Run migration
alembic upgrade head

# Start API (worker starts automatically)
python -m app.main

# Check queue stats
curl http://localhost:8000/admin/queue-stats
```

### Monitoring
```python
# Add endpoint for queue monitoring
@router.get("/admin/queue-stats")
async def get_queue_stats(session: AsyncSession = Depends(get_session)):
    service = ClassificationQueueService(session)
    return await service.get_queue_stats()
```

Expected output:
```json
{
  "pending": 45,
  "processing": 2,
  "completed": 1234,
  "failed": 3
}
```

---

*Story created: 2026-01-29*  
*Part of: Recommendation Engine V3*
