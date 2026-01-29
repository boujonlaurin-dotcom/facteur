# User Story 4.2-US-5 : EntityLayer Scoring

**Parent Story:** [4.2.reco-engine-v3.story.md](./4.2.reco-engine-v3.story.md)  
**Status:** Draft  
**Priority:** P0 - Critical  
**Estimated Effort:** 3 days  
**Dependencies:** US-3 (mDeBERTa Integration), US-4 (NER Service)

---

## 🎯 Problem Statement

**Current Scoring:**
- Articles are scored on broad topics (+40pts per topic match)
- Cannot detect if user cares about specific entities ("Elon Musk", "Tesla")
- Missing the micro-interest level that makes recommendations "telepathic"

**Goal:**
- Track which entities each user cares about
- Score articles based on entity matches (+60pts per entity)
- Create user profiles at entity level

---

## 📋 Acceptance Criteria

### AC-1: User Entity Tracking
```gherkin
Given a user reads 3 articles mentioning "Tesla"
When the system updates user profile
Then user_entities contains {"Tesla": {"score": 15, "count": 3}}
And Tesla is marked as a user interest
```

### AC-2: Entity Scoring
```gherkin
Given a user profile with entity "Tesla" (score: 15)
And a new article mentioning "Tesla"
When the recommendation engine scores the article
Then EntityLayer adds +60pts
And the reason shows "Centre d'intérêt: Tesla"
```

### AC-3: Decay System
```gherkin
Given a user hasn't read about "Bitcoin" in 30 days
When the system updates entity scores
Then the Bitcoin entity score decays
And eventually drops below threshold
```

### AC-4: Transparency
```gherkin
Given an article is recommended based on entity match
When the user views the article
Then they see "Recommandé car vous lisez souvent sur: Tesla"
```

---

## 🏗️ Technical Architecture

### User Entity Profile

```sql
CREATE TABLE user_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_text VARCHAR(255) NOT NULL,  -- "Tesla", "Elon Musk"
    entity_label VARCHAR(50) NOT NULL,  -- ORG, PERSON, etc.
    score INTEGER DEFAULT 0,            -- Cumulative score
    read_count INTEGER DEFAULT 0,       -- Times seen in articles
    first_seen_at TIMESTAMPTZ DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    decay_factor FLOAT DEFAULT 1.0,     -- For time decay
    
    UNIQUE(user_id, entity_text)
);

CREATE INDEX idx_user_entities_user ON user_entities(user_id);
CREATE INDEX idx_user_entities_score ON user_entities(user_id, score DESC);
```

### Scoring Matrix V3

| Layer | Match Type | Points | Example Reason |
|-------|-----------|--------|----------------|
| CoreLayer | Theme match | +50 | "Thème: tech" |
| CoreLayer | Trusted source | +40 | "Source suivie" |
| ArticleTopicLayer | Topic match | +40 | "Sujet: startups" |
| **EntityLayer** | **Entity match** | **+60** | **"Centre d'intérêt: Tesla"** |
| QualityLayer | Reliable source | +10 | "Source fiable" |

### Entity Detection Flow

```
User reads article
    │
    ▼
Extract entities from article
    │
    ▼
For each entity:
  - Update user_entities table
  - Increment score (+5 per read)
  - Update last_seen_at
    │
    ▼
Next feed request:
  - Load user_entities
  - For each candidate article:
    - Check entity overlap
    - Add +60pts per match
```

---

## 🔧 Implementation Tasks

### Task 1: Database Migration (2h)

**File:** `packages/api/alembic/versions/xxx_create_user_entities.py`

```python
def upgrade():
    op.create_table(
        'user_entities',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), 
                  sa.ForeignKey('users.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('entity_text', sa.String(255), nullable=False),
        sa.Column('entity_label', sa.String(50), nullable=False),
        sa.Column('score', sa.Integer, server_default='0'),
        sa.Column('read_count', sa.Integer, server_default='0'),
        sa.Column('first_seen_at', sa.DateTime(timezone=True), 
                  server_default=sa.func.now()),
        sa.Column('last_seen_at', sa.DateTime(timezone=True), 
                  server_default=sa.func.now()),
        sa.Column('decay_factor', sa.Float, server_default='1.0'),
    )
    
    # Unique constraint: one entry per user per entity
    op.create_unique_constraint(
        'uq_user_entities_user_entity',
        'user_entities',
        ['user_id', 'entity_text']
    )
    
    # Indexes
    op.create_index('idx_user_entities_user', 'user_entities', ['user_id'])
    op.create_index('idx_user_entities_score', 'user_entities', 
                    ['user_id', sa.text('score DESC')])

def downgrade():
    op.drop_table('user_entities')
```

**Model:** `packages/api/app/models/user_entity.py`

```python
class UserEntity(Base):
    """User's interest in specific entities."""
    
    __tablename__ = "user_entities"
    
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    entity_text: Mapped[str] = mapped_column(String(255))
    entity_label: Mapped[str] = mapped_column(String(50))
    score: Mapped[int] = mapped_column(default=0)
    read_count: Mapped[int] = mapped_column(default=0)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    decay_factor: Mapped[float] = mapped_column(default=1.0)
```

### Task 2: User Entity Service (4h)

**File:** `packages/api/app/services/user_entity_service.py`

```python
"""
Service for managing user entity interests.
Tracks which entities (people, orgs, etc.) each user cares about.
"""

import structlog
from datetime import datetime, timedelta
from typing import List, Optional
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user_entity import UserEntity
from app.models.content import Content

logger = structlog.get_logger()


class UserEntityService:
    """Manage user entity interests and scoring."""
    
    # Points per entity read
    SCORE_PER_READ = 5
    
    # Minimum score to be considered an interest
    MIN_INTEREST_SCORE = 10
    
    # Decay settings
    DECAY_DAYS = 30
    DECAY_FACTOR = 0.9  # Lose 10% every 30 days
    
    def __init__(self, session: AsyncSession):
        self.session = session
    
    async def track_article_read(
        self,
        user_id: UUID,
        content: Content,
    ) -> None:
        """
        Track entities from an article the user read.
        Called when user opens/reads an article.
        """
        if not content.entities:
            return
        
        for entity_data in content.entities:
            await self._update_entity(
                user_id=user_id,
                entity_text=entity_data["text"],
                entity_label=entity_data["label"],
            )
        
        logger.debug(
            "user_entity.tracked_read",
            user_id=str(user_id),
            content_id=str(content.id),
            entity_count=len(content.entities),
        )
    
    async def _update_entity(
        self,
        user_id: UUID,
        entity_text: str,
        entity_label: str,
    ) -> None:
        """Update or create user entity."""
        # Normalize entity text
        entity_text = entity_text.strip()
        entity_key = entity_text.lower()  # Case-insensitive matching
        
        # Try to get existing entity
        result = await self.session.execute(
            select(UserEntity).where(
                UserEntity.user_id == user_id,
                UserEntity.entity_text.ilike(entity_text)
            )
        )
        entity = result.scalar_one_or_none()
        
        if entity:
            # Update existing
            entity.score += self.SCORE_PER_READ
            entity.read_count += 1
            entity.last_seen_at = datetime.utcnow()
        else:
            # Create new
            entity = UserEntity(
                user_id=user_id,
                entity_text=entity_text,
                entity_label=entity_label,
                score=self.SCORE_PER_READ,
                read_count=1,
                first_seen_at=datetime.utcnow(),
                last_seen_at=datetime.utcnow(),
            )
            self.session.add(entity)
        
        await self.session.commit()
    
    async def get_user_entities(
        self,
        user_id: UUID,
        min_score: int = None,
        limit: int = 50,
    ) -> List[UserEntity]:
        """Get user's top entities."""
        if min_score is None:
            min_score = self.MIN_INTEREST_SCORE
        
        result = await self.session.execute(
            select(UserEntity)
            .where(
                UserEntity.user_id == user_id,
                UserEntity.score >= min_score
            )
            .order_by(UserEntity.score.desc())
            .limit(limit)
        )
        
        return result.scalars().all()
    
    async def apply_decay(self, user_id: UUID) -> None:
        """
        Apply time decay to entity scores.
        Called periodically (e.g., daily).
        """
        cutoff_date = datetime.utcnow() - timedelta(days=self.DECAY_DAYS)
        
        # Get entities not seen recently
        result = await self.session.execute(
            select(UserEntity).where(
                UserEntity.user_id == user_id,
                UserEntity.last_seen_at < cutoff_date,
                UserEntity.score > 0
            )
        )
        
        entities = result.scalars().all()
        
        for entity in entities:
            # Apply decay
            entity.score = int(entity.score * self.DECAY_FACTOR)
            entity.decay_factor *= self.DECAY_FACTOR
        
        if entities:
            await self.session.commit()
            logger.info(
                "user_entity.decay_applied",
                user_id=str(user_id),
                entity_count=len(entities),
            )
    
    async def get_entity_intersection_score(
        self,
        user_id: UUID,
        content_entities: List[dict],
    ) -> tuple[int, List[str]]:
        """
        Calculate score for entity matches.
        
        Returns:
            (total_score, matched_entities)
        """
        if not content_entities:
            return 0, []
        
        # Get user's entities
        user_entities = await self.get_user_entities(user_id, limit=100)
        user_entity_set = {e.entity_text.lower() for e in user_entities}
        
        # Find matches
        matched = []
        total_score = 0
        
        for content_entity in content_entities:
            entity_text = content_entity["text"].lower()
            if entity_text in user_entity_set:
                # Find the user entity to get score
                user_entity = next(
                    (e for e in user_entities 
                     if e.entity_text.lower() == entity_text),
                    None
                )
                if user_entity:
                    matched.append(content_entity["text"])
                    total_score += 60  # Base entity score
        
        return total_score, matched
```

### Task 3: EntityLayer Scoring Layer (4h)

**File:** `packages/api/app/services/recommendation/layers/entity_layer.py`

```python
"""
EntityLayer: Scoring based on entity matches.
+60 points per entity the user has shown interest in.
"""

from app.services.recommendation.scoring_engine import BaseScoringLayer, ScoringContext
from app.services.user_entity_service import UserEntityService
from app.models.content import Content


class EntityLayer(BaseScoringLayer):
    """
    Couche de scoring basée sur les entités.
    
    Détecte si l'utilisateur s'intéresse à des entités spécifiques
    (personnes, organisations, produits) mentionnées dans l'article.
    """
    
    @property
    def name(self) -> str:
        return "entity_match"
    
    def score(self, content: Content, context: ScoringContext) -> float:
        """
        Score based on entity overlap with user interests.
        
        Returns:
            Score: +60 per matched entity
        """
        # Skip if no entities in content
        if not content.entities:
            return 0.0
        
        # Skip if we can't access user entity service
        if not hasattr(context, 'user_id'):
            return 0.0
        
        # This requires DB access, so we do it differently
        # The entities are pre-computed and passed in context
        user_entities = getattr(context, 'user_entities', set())
        
        if not user_entities:
            return 0.0
        
        # Find matches
        content_entity_texts = {
            e["text"].lower() for e in content.entities
        }
        
        matches = content_entity_texts & user_entities
        
        if not matches:
            return 0.0
        
        # +60 per match, max 180 (3 entities)
        score = min(len(matches) * 60, 180)
        
        # Add reason for transparency
        matched_list = sorted(list(matches))[:3]
        detail = f"Centre d'intérêt: {', '.join(matched_list)}"
        
        context.add_reason(
            content.id,
            self.name,
            score,
            detail
        )
        
        return score
```

**Update ScoringContext:**

```python
# app/services/recommendation/scoring_engine.py

class ScoringContext:
    def __init__(
        self,
        # ... existing params ...
        user_entities: Set[str] = None,  # NEW
    ):
        # ... existing ...
        self.user_entities = user_entities or set()
```

**Update RecommendationService:**

```python
# app/services/recommendation_service.py

async def get_feed(self, user_id: UUID, ...) -> List[Content]:
    # ... existing code ...
    
    # Load user entities
    from app.services.user_entity_service import UserEntityService
    entity_service = UserEntityService(self.session)
    user_entities = await entity_service.get_user_entities(user_id, limit=100)
    user_entity_set = {e.entity_text.lower() for e in user_entities}
    
    # Create context with entities
    context = ScoringContext(
        # ... existing params ...
        user_entities=user_entity_set,
    )
    
    # ... rest of scoring ...
```

**Update ScoringEngine:**

```python
# Add EntityLayer to engine
from app.services.recommendation.layers.entity_layer import EntityLayer

self.scoring_engine = ScoringEngine([
    CoreLayer(),
    StaticPreferenceLayer(),
    BehavioralLayer(),
    QualityLayer(),
    VisualLayer(),
    ArticleTopicLayer(),
    PersonalizationLayer(),
    EntityLayer(),  # NEW
])
```

### Task 4: Track Article Reads (2h)

**File:** `packages/api/app/routers/contents.py` (update)

```python
@router.post("/{content_id}/read")
async def mark_article_read(
    content_id: UUID,
    session: AsyncSession = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Mark article as read and track entities."""
    
    # Get content with entities
    content = await session.get(Content, content_id)
    if not content:
        raise HTTPException(404, "Content not found")
    
    # Track entities
    from app.services.user_entity_service import UserEntityService
    entity_service = UserEntityService(session)
    await entity_service.track_article_read(
        user_id=current_user.id,
        content=content,
    )
    
    # ... rest of logic ...
```

### Task 5: Decay Job (2h)

**File:** `packages/api/app/workers/entity_decay_job.py`

```python
"""
Daily job to apply time decay to user entity scores.
Prevents old interests from dominating forever.
"""

import asyncio
import structlog
from datetime import datetime

from app.database import AsyncSessionLocal
from app.models.user import User
from app.services.user_entity_service import UserEntityService

logger = structlog.get_logger()


async def run_entity_decay_job():
    """Apply decay to all user entities."""
    logger.info("entity_decay_job.started")
    
    async with AsyncSessionLocal() as session:
        # Get all active users
        result = await session.execute(select(User.id))
        user_ids = [row[0] for row in result]
        
        processed = 0
        
        for user_id in user_ids:
            try:
                service = UserEntityService(session)
                await service.apply_decay(user_id)
                processed += 1
                
                # Small delay to not overwhelm DB
                await asyncio.sleep(0.1)
                
            except Exception as e:
                logger.error(
                    "entity_decay_job.user_failed",
                    user_id=str(user_id),
                    error=str(e),
                )
        
        logger.info(
            "entity_decay_job.completed",
            users_processed=processed,
        )


# Run daily at 3 AM
async def schedule_decay_job():
    """Schedule the decay job."""
    from apscheduler.schedulers.asyncio import AsyncIOScheduler
    
    scheduler = AsyncIOScheduler()
    scheduler.add_job(
        run_entity_decay_job,
        'cron',
        hour=3,
        minute=0,
    )
    scheduler.start()
```

---

## 🧪 Testing

### Unit Tests

```python
# tests/recommendation/test_entity_layer.py

@pytest.mark.asyncio
async def test_entity_match_scoring():
    """Test entity match adds score."""
    content = create_mock_content(
        entities=[{"text": "Tesla", "label": "ORG"}]
    )
    context = create_mock_context(
        user_entities={"tesla", "spacex"}
    )
    
    layer = EntityLayer()
    score = layer.score(content, context)
    
    assert score == 60
    assert_reason_contains(context, "Centre d'intérêt: Tesla")

@pytest.mark.asyncio
async def test_user_entity_service_tracks_read():
    """Test service tracks entity reads."""
    service = UserEntityService(session)
    
    content = create_mock_content(
        entities=[{"text": "Apple", "label": "ORG"}]
    )
    
    await service.track_article_read(user_id, content)
    
    # Check entity was created
    entities = await service.get_user_entities(user_id)
    assert len(entities) == 1
    assert entities[0].entity_text == "Apple"
    assert entities[0].score == 5
```

---

## 📁 Files Created

| File | Description |
|------|-------------|
| `alembic/versions/xxx_create_user_entities.py` | DB migration |
| `app/models/user_entity.py` | SQLAlchemy model |
| `app/services/user_entity_service.py` | Entity tracking service |
| `app/services/recommendation/layers/entity_layer.py` | Scoring layer |
| `app/workers/entity_decay_job.py` | Daily decay job |
| `tests/recommendation/test_entity_layer.py` | Tests |

---

## 📊 Expected Impact

### Before EntityLayer
- Article about "Tesla" matches: `tech` topic (+40pts)
- User gets generic tech articles

### After EntityLayer
- Article about "Tesla" matches: `tech` topic (+40pts) + `Tesla` entity (+60pts)
- User gets Tesla-specific articles prioritized
- Reason: "Centre d'intérêt: Tesla"

---

*Story created: 2026-01-29*  
*Part of: Recommendation Engine V3*
