# Testing Patterns

**Analysis Date:** 2026-02-01

## Test Framework

**Runner:**
- pytest 8.0.0+
- pytest-asyncio 0.23.0+ for async test support
- Configured in `pyproject.toml`:
  ```toml
  [tool.pytest.ini_options]
  asyncio_mode = "auto"
  testpaths = ["tests"]
  ```

**Assertion Library:**
- pytest built-in assertions
- No explicit assertion library (no pytest-assume, etc.)

**Run Commands:**
```bash
cd packages/api
pytest                              # Run all tests
pytest -v                          # Verbose output
pytest tests/test_classification_queue.py  # Run specific test file
pytest -k "test_enqueue"           # Run tests matching pattern
```

## Test File Organization

**Location:**
- Tests located in `packages/api/tests/`
- Co-located with app code (not in separate top-level directory)

**Naming:**
- Test files: `test_*.py`
- Example: `test_classification_queue.py`, `test_source_management.py`

**Structure:**
```
packages/api/tests/
├── conftest.py                 # Shared fixtures
├── test_classification_queue.py
├── test_feed_algo.py
├── test_personalization_router.py
├── test_rss_parser.py
├── test_source_management.py
├── test_top3_selector.py
├── test_importance_detector.py
├── test_scoring_v2.py
├── ml/                         # ML-specific tests
└── recommendation/             # Recommendation tests
```

## Test Structure

**Suite Organization:**
- Both function-based and class-based tests used
- Class-based for grouping related tests:
  ```python
  class TestClassificationQueueService:
      async def test_enqueue_creates_queue_item(self, queue_service, test_content):
          # Test implementation
  ```

**Test Markers:**
- `@pytest.mark.asyncio` for async tests (implicit with asyncio_mode = "auto")
- Explicit usage still present in some tests for clarity

**Pattern:**
```python
import pytest
from app.services.classification_queue_service import ClassificationQueueService

class TestClassificationQueueService:
    async def test_enqueue_creates_queue_item(self, queue_service, test_content):
        # Act
        result = await queue_service.enqueue(test_content.id, priority=5)
        
        # Assert
        assert result is True
```

## Fixtures

**Location:** `packages/api/tests/conftest.py`

**Database Fixtures:**
```python
@pytest_asyncio.fixture
async def db_session():
    """Create a test database session with automatic rollback."""
    async with TestSessionLocal() as session:
        try:
            yield session
        finally:
            await session.rollback()
            await session.close()
```

**Model Fixtures:**
```python
@pytest_asyncio.fixture
async def test_source(db_session):
    """Create a test source for content items."""
    source = Source(
        id=uuid4(),
        name="Test Source",
        url="https://example.com",
        feed_url=f"https://example.com/test-feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db_session.add(source)
    await db_session.commit()
    return source
```

**Service Fixtures:**
```python
@pytest.fixture
async def queue_service(db_session):
    """Create a ClassificationQueueService instance."""
    return ClassificationQueueService(db_session)
```

**Fixture Scopes:**
- Default scope (function) for database fixtures
- Allows test isolation with automatic rollback

## Mocking

**Framework:** unittest.mock (standard library)

**Patterns:**

**AsyncMock for async dependencies:**
```python
from unittest.mock import AsyncMock, MagicMock, patch

mock_db = AsyncMock()
mock_db.scalar = AsyncMock(return_value=None)
```

**Patch for external calls:**
```python
with patch("feedparser.parse", return_value=mock_result):
    with patch("httpx.AsyncClient.get") as mock_get:
        result = await parser.detect("https://techcrunch.com/feed")
```

**Patch for service instantiation:**
```python
with patch("app.routers.personalization.UserService") as mock_user_service_cls:
    mock_user_service = mock_user_service_cls.return_value
    mock_user_service.get_or_create_profile = AsyncMock()
```

**What to Mock:**
- External HTTP calls (httpx, feedparser)
- Database for unit tests (integration tests use real DB)
- Service dependencies in router tests

## Test Types

**Unit Tests:**
- Service logic tests with mocked dependencies
- Example: `test_feed_algo.py` tests `RecommendationService._score_content()`

**Integration Tests:**
- Database integration with real SQLAlchemy sessions
- Full workflow tests
- Example: `test_classification_queue.py` class `TestClassificationQueueIntegration`

**Router Tests:**
- FastAPI endpoint tests with mocked services
- Example: `test_personalization_router.py`

**No E2E Tests:**
- No Playwright, Selenium, or similar E2E framework detected
- Mobile app tests would be in `apps/mobile/test/` (not analyzed)

## Test Data

**Factories:**
- Fixture-based approach
- No factory_boy or similar libraries detected

**Pattern:**
```python
@pytest_asyncio.fixture
async def test_content(db_session, test_source):
    content = Content(
        id=uuid4(),
        source_id=test_source.id,
        title="Test Article",
        url="https://example.com/test",
        guid="test-guid-001",
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
    )
    db_session.add(content)
    await db_session.commit()
    return content
```

**CSV Data Testing:**
- Some tests validate external data files
- Example: `test_source_management.py` tests `sources_master.csv` quality

## Common Patterns

**Async Testing:**
```python
@pytest.mark.asyncio
async def test_async_operation():
    result = await async_function()
    assert result == expected
```

**Exception Testing:**
```python
with pytest.raises(HTTPException) as excinfo:
    await operation_that_fails()

assert excinfo.value.status_code == 500
assert "Error message" in excinfo.value.detail
```

**Database State Verification:**
```python
from sqlalchemy import select

stmt = select(ClassificationQueue).where(
    ClassificationQueue.content_id == test_content.id
)
result = await queue_service.session.execute(stmt)
item = result.scalar_one()

assert item.status == "completed"
```

**Refresh Pattern:**
```python
await queue_service.session.refresh(test_content)
assert test_content.topics == topics
```

## Coverage

**Requirements:**
- pytest-cov available in dev dependencies but not configured
- No explicit coverage target set

**Run Coverage:**
```bash
pytest --cov=app --cov-report=html
pytest --cov=app --cov-report=term-missing
```

## Testing Best Practices

**Test Isolation:**
- Database rollback after each test
- No shared state between tests

**Naming:**
- Descriptive test names: `test_enqueue_creates_queue_item`
- Test names describe the expected behavior

**Arrange-Act-Assert:**
- Clear separation with comments in longer tests
- Example: `test_classification_queue.py` line 42-48

**Integration Tests:**
- Marked with class name `Test*Integration`
- Full workflow testing

---

*Testing analysis: 2026-02-01*
