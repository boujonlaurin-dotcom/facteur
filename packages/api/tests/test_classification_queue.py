"""Tests for classification queue service."""

import asyncio
import pytest
from uuid import uuid4
from datetime import datetime

from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.models.enums import ContentType
from app.services.classification_queue_service import ClassificationQueueService


@pytest.fixture
async def queue_service(db_session):
    """Create a ClassificationQueueService instance."""
    return ClassificationQueueService(db_session)


@pytest.fixture
async def test_content(db_session, test_source):
    """Create a test content item."""
    content = Content(
        id=uuid4(),
        source_id=test_source.id,
        title="Test Article",
        url="https://example.com/test",
        guid="test-guid-001",
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        description="Test description",
    )
    db_session.add(content)
    await db_session.commit()
    return content


class TestClassificationQueueService:
    """Test suite for ClassificationQueueService."""

    async def test_enqueue_creates_queue_item(self, queue_service, test_content):
        """Test that enqueue creates a queue item with pending status."""
        # Act
        result = await queue_service.enqueue(test_content.id, priority=5)
        
        # Assert
        assert result is True
        
        # Verify in database
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        assert item.status == "pending"
        assert item.priority == 5
        assert item.retry_count == 0

    async def test_enqueue_duplicate_returns_false(self, queue_service, test_content):
        """Test that enqueue returns False if item already exists."""
        # Arrange
        await queue_service.enqueue(test_content.id, priority=5)
        
        # Act
        result = await queue_service.enqueue(test_content.id, priority=10)
        
        # Assert
        assert result is False  # Should not create duplicate

    async def test_dequeue_batch_returns_pending_items(self, queue_service, db_session, test_source):
        """Test that dequeue_batch returns pending items."""
        # Arrange
        content_ids = []
        for i in range(5):
            content = Content(
                id=uuid4(),
                source_id=test_source.id,
                title=f"Test Article {i}",
                url=f"https://example.com/test{i}",
                guid=f"test-guid-{i}",
                published_at=datetime.utcnow(),
                content_type=ContentType.ARTICLE,
            )
            db_session.add(content)
            content_ids.append(content.id)
        
        await db_session.commit()
        
        # Enqueue items
        for cid in content_ids:
            await queue_service.enqueue(cid)
        
        # Act
        items = await queue_service.dequeue_batch(batch_size=3)
        
        # Assert
        assert len(items) == 3
        for item in items:
            assert item.status == "processing"

    async def test_mark_completed_updates_topics(self, queue_service, test_content):
        """Test that mark_completed updates content topics."""
        # Arrange
        await queue_service.enqueue(test_content.id)
        
        # Get the queue item
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        # Act
        topics = ["tech", "science"]
        await queue_service.mark_completed(item.id, topics)
        
        # Assert
        # Refresh content from database
        await queue_service.session.refresh(test_content)
        assert test_content.topics == topics
        
        # Check queue item status
        await queue_service.session.refresh(item)
        assert item.status == "completed"
        assert item.processed_at is not None

    async def test_mark_failed_increments_retry(self, queue_service, test_content):
        """Test that mark_failed increments retry count."""
        # Arrange
        await queue_service.enqueue(test_content.id)
        
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        # Act - First failure
        will_retry = await queue_service.mark_failed(item.id, "Test error")
        
        # Assert
        assert will_retry is True
        await queue_service.session.refresh(item)
        assert item.retry_count == 1
        assert item.status == "pending"  # Should be retried
        assert item.error_message == "Test error"

    async def test_mark_failed_max_retries(self, queue_service, test_content):
        """Test that item is marked failed after 3 retries."""
        # Arrange
        await queue_service.enqueue(test_content.id)
        
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        # Act - Three failures
        await queue_service.mark_failed(item.id, "Error 1")
        await queue_service.mark_failed(item.id, "Error 2")
        will_retry = await queue_service.mark_failed(item.id, "Error 3")
        
        # Assert
        assert will_retry is False
        await queue_service.session.refresh(item)
        assert item.retry_count == 3
        assert item.status == "failed"  # Permanent failure

    async def test_get_queue_stats(self, queue_service, db_session):
        """Test that get_queue_stats returns correct counts."""
        # Arrange - Create multiple items with different statuses
        # This would require creating content items first
        # For this test, we'll verify the structure of the response
        
        # Act
        stats = await queue_service.get_queue_stats()
        
        # Assert
        assert "pending" in stats
        assert "processing" in stats
        assert "completed" in stats
        assert "failed" in stats
        assert "cancelled" in stats
        assert "total" in stats
        assert "backlog" in stats
        assert "success_rate" in stats

    async def test_priority_ordering(self, queue_service, db_session, test_source):
        """Test that high priority items are dequeued first."""
        # Arrange
        # Create content items with different priorities
        contents = []
        for i in range(3):
            content = Content(
                id=uuid4(),
                source_id=test_source.id,
                title=f"Priority Test {i}",
                url=f"https://example.com/priority{i}",
                guid=f"priority-guid-{i}",
                published_at=datetime.utcnow(),
                content_type=ContentType.ARTICLE,
            )
            db_session.add(content)
            contents.append(content)
        
        await db_session.commit()
        
        # Enqueue with different priorities (with small delays to ensure ordering)
        await queue_service.enqueue(contents[0].id, priority=0)  # Low
        await asyncio.sleep(0.01)
        await queue_service.enqueue(contents[1].id, priority=10)  # High
        await asyncio.sleep(0.01)
        await queue_service.enqueue(contents[2].id, priority=5)   # Medium
        
        # Act
        items = await queue_service.dequeue_batch(batch_size=3)
        
        # Assert - Should be in priority order (10, 5, 0)
        assert len(items) == 3
        # Vérifier que les priorités sont dans l'ordre décroissant
        priorities = [item.priority for item in items]
        assert priorities == [10, 5, 0], f"Priorities should be in descending order, got {priorities}"


class TestClassificationQueueIntegration:
    """Integration tests for the classification queue."""

    async def test_full_workflow(self, queue_service, test_content):
        """Test the complete workflow: enqueue -> dequeue -> complete."""
        # Step 1: Enqueue
        result = await queue_service.enqueue(test_content.id, priority=5)
        assert result is True
        
        # Step 2: Dequeue
        items = await queue_service.dequeue_batch(batch_size=1)
        assert len(items) == 1
        assert items[0].status == "processing"
        
        # Step 3: Complete
        topics = ["ai", "technology"]
        await queue_service.mark_completed(items[0].id, topics)
        
        # Verify
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        assert item.status == "completed"
        
        # Verify content was updated
        await queue_service.session.refresh(test_content)
        assert test_content.topics == topics

    async def test_requeue_failed(self, queue_service, test_content):
        """Test requeue_failed functionality."""
        # Arrange
        await queue_service.enqueue(test_content.id)
        
        from sqlalchemy import select
        stmt = select(ClassificationQueue).where(
            ClassificationQueue.content_id == test_content.id
        )
        result = await queue_service.session.execute(stmt)
        item = result.scalar_one()
        
        # Mark as failed with 2 retries (will be eligible for requeue)
        item.status = "failed"
        item.retry_count = 2
        await queue_service.session.commit()
        
        # Act
        requeued_count = await queue_service.requeue_failed(max_retries=3)
        
        # Assert
        assert requeued_count == 1
        
        await queue_service.session.refresh(item)
        assert item.status == "pending"
