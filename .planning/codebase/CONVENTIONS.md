# Coding Conventions

**Analysis Date:** 2026-02-01

## Naming Patterns

**Files:**
- Lowercase with underscores (snake_case)
- Examples: `user_service.py`, `content.py`, `test_classification_queue.py`

**Classes:**
- PascalCase for class names
- Examples: `UserService`, `Content`, `ClassificationQueueService`

**Functions/Methods:**
- snake_case
- Examples: `get_profile()`, `add_custom_source()`, `save_onboarding()`

**Variables:**
- snake_case for local variables
- Descriptive names preferred
- Examples: `user_id`, `content_count`, `preference_value`

**Constants:**
- Not explicitly defined, typically module-level uppercase in configuration files
- Environment variables use lowercase in `Settings` class (e.g., `app_name`, `database_url`)

**Private Methods:**
- Single underscore prefix for internal methods
- Example: `_get_source_by_feed_url()`, `_guess_theme()`, `_score_content()`

## Code Style

**Formatter:**
- Ruff (configured in `pyproject.toml`)
- Line length: 88 characters
- Target Python version: 3.12

**Linting:**
- Tool: Ruff
- Rules enabled: E, W, F, I, B, C4, UP, ARG, SIM
- Ignored: E501 (line too long handled by formatter), B008 (function calls in defaults)
- Import sorting: isort with `known-first-party = ["app"]`

**Type Hints:**
- Mandatory throughout codebase
- Use `from __future__ import annotations` implicitly via Python 3.12
- Examples:
  ```python
  async def get_profile(self, user_id: str) -> Optional[UserProfile]:
  async def get_all_sources(self, user_id: str) -> SourceCatalogResponse:
  ```

**Async/Await:**
- Full async/await pattern for all I/O operations
- SQLAlchemy async sessions throughout
- Example pattern:
  ```python
  async def get_profile(self, user_id: str) -> Optional[UserProfile]:
      result = await self.db.execute(
          select(UserProfile).where(UserProfile.user_id == UUID(user_id))
      )
      return result.scalar_one_or_none()
  ```

## Import Organization

**Order:**
1. Standard library (e.g., `datetime`, `uuid`, `typing`)
2. Third-party packages (e.g., `fastapi`, `sqlalchemy`, `structlog`)
3. First-party app modules (e.g., `from app.models...`, `from app.services...`)

**Example:**
```python
from datetime import datetime
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.user import UserProfileResponse
```

**TYPE_CHECKING Block:**
- Use for imports only needed for type hints
- Prevents circular imports
- Example: `packages/api/app/models/content.py` lines 15-17

## Error Handling

**Router Layer:**
- Raise `HTTPException` with appropriate status codes
- Pattern:
  ```python
  if not profile:
      raise HTTPException(
          status_code=status.HTTP_404_NOT_FOUND,
          detail="Profile not found",
      )
  ```

**Service Layer:**
- Raise `ValueError` for business logic errors
- Let exceptions bubble up to router or handle gracefully
- Example: `packages/api/app/services/source_service.py` line 256

**Database Transactions:**
- Automatic rollback on exception in `get_db()` dependency
- Pattern: `packages/api/app/database.py` lines 88-98

**Global Exception Handling:**
- No explicit global handler; rely on FastAPI defaults
- Sentry integration for error tracking

## Logging

**Framework:** structlog

**Configuration:**
- JSON renderer in production
- ISO timestamp format
- Log level included

**Pattern:**
```python
import structlog
logger = structlog.get_logger()

logger.info("operation_started", user_id=user_id, action="create_profile")
logger.error("operation_failed", error=str(e), context="additional_info")
```

**Usage Guidelines:**
- Use structured logging with key-value pairs
- Include relevant context (user_id, operation name)
- Use appropriate log levels (info, error, warning, critical)

## Pydantic Models

**Schemas:**
- Separate request/response models
- Use `BaseModel` for all schemas
- Enable `from_attributes = True` for ORM compatibility

**Pattern:**
```python
class UserProfileResponse(BaseModel):
    id: UUID
    user_id: UUID
    display_name: Optional[str]
    
    class Config:
        from_attributes = True
```

**Validation:**
- Use `Field()` for constraints (e.g., `Field(None, ge=5, le=15)`)
- Custom validators use `@field_validator` or `@model_validator`
- Example: `packages/api/app/config.py` lines 39-59

## SQLAlchemy Models

**Pattern:**
- Use `Mapped` and `mapped_column` (SQLAlchemy 2.0 style)
- Type hints on all columns
- Relationships with back_populates

**Example:**
```python
class UserProfile(Base):
    __tablename__ = "user_profiles"
    
    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), unique=True, nullable=False)
    
    preferences: Mapped[list["UserPreference"]] = relationship(
        back_populates="profile", cascade="all, delete-orphan"
    )
```

## Comments

**Language:**
- French for docstrings and business logic comments
- English for technical comments and TODOs

**Docstrings:**
- Module-level docstrings present
- Function docstrings for public APIs
- Class docstrings explaining purpose

**TODO Comments:**
- Format: `# TODO: Description`
- Present in several files for known gaps
- Examples found in `user_service.py`, `source_service.py`, `recommendation_service.py`

## Function Design

**Size:**
- Functions typically under 50 lines
- Services split into focused methods
- Example: `UserService` has separate methods for `get_profile`, `create_profile`, `update_profile`

**Parameters:**
- Use type hints
- Accept primitive types (str, UUID) rather than objects for IDs
- Use Pydantic models for complex inputs

**Return Values:**
- Return Pydantic response models from routers
- Return ORM models or Optional from services
- Use `Optional[Type]` for nullable returns

## Module Design

**Service Pattern:**
- Class-based services with `db: AsyncSession` dependency
- Example:
  ```python
  class UserService:
      def __init__(self, db: AsyncSession):
          self.db = db
  ```

**Router Pattern:**
- FastAPI APIRouter per domain
- Dependency injection for `get_db()` and `get_current_user_id()`

**Exports:**
- No explicit `__all__` definitions found
- Import explicitly from modules

---

*Convention analysis: 2026-02-01*
