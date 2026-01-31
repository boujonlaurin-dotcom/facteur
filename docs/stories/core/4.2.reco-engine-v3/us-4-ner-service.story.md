# User Story 4.2-US-4 : NER Service (spaCy)

**Parent Story:** [4.2.reco-engine-v3.story.md](./4.2.reco-engine-v3.story.md)  
**Status:** In Progress → Ready for Review  
**Priority:** P0 - Critical  
**Estimated Effort:** 2 days  
**Dependencies:** US-2 (Async Queue Architecture)

---

## 🎯 Problem Statement

**Limitation of Current System:**
- 47 predefined topics capture broad categories ("tech", "science")
- Cannot detect specific entities users care about ("Elon Musk", "Tesla", "COP29")
- Missing the "niche" level that makes GAFAM recommendations precise

**Goal:**
- Extract named entities from articles (people, organizations, products, events)
- Enable entity-level user profiling
- Support unlimited micro-topics beyond the 47 predefined labels

---

## 📋 Acceptance Criteria

### AC-1: Entity Extraction
```gherkin
Given an article with text "Elon Musk launches Neuralink brain chip"
When the NER service processes it
Then entities are extracted: ["Elon Musk" (PERSON), "Neuralink" (ORG)]
And stored in content.entities
```

### AC-2: Entity Types
```gherkin
Given various articles
When NER runs
Then it detects these entity types:
  - PERSON (people)
  - ORG (organizations/companies)
  - PRODUCT (products/services)
  - GPE (geopolitical entities/locations)
  - EVENT (events)
```

### AC-3: Performance
```gherkin
Given an article with 500 words
When NER processes it
Then extraction completes within 50ms
And uses <100MB additional RAM
```

### AC-4: French Language Support
```gherkin
Given an article in French
When NER processes it
Then entities are correctly extracted
Example: "Emmanuel Macron" → PERSON, "Assemblée Nationale" → ORG
```

---

## 🏗️ Technical Architecture

### NER Pipeline

```
Article Text
    │
    ▼
┌─────────────────────┐
│ spaCy NER Pipeline  │
│ fr_core_news_md     │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Entity Filter       │
│ (remove common      │
│  words, duplicates) │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ Store in DB         │
│ content.entities    │
└─────────────────────┘
```

### Why spaCy?

| Feature | spaCy | Alternatives |
|---------|-------|--------------|
| Speed | 10-50ms/article | Flair: 100ms+, Stanza: 200ms+ |
| RAM | ~100MB | CamemBERT-NER: 400MB+ |
| French | Native model | Most are English-centric |
| License | MIT | Free for commercial use |
| Accuracy | 85-90% | Good for production |

**Model:** `fr_core_news_md` (medium size, best speed/accuracy ratio)

---

## 🔧 Implementation Tasks

### Task 1: Add Dependencies (1h)

**File:** `packages/api/requirements-ml.txt`

```txt
# Existing
transformers==4.38.2
torch==2.2.0

# Add spaCy
spacy==3.8.11

# French model (downloaded separately)
# python -m spacy download fr_core_news_md
```

**Installation Script:**

```bash
#!/bin/bash
# scripts/install_spacy_model.sh

echo "Installing spaCy French model..."
python -m spacy download fr_core_news_md

echo "Verifying installation..."
python -c "import spacy; nlp = spacy.load('fr_core_news_md'); print('✓ Model loaded successfully')"
```

### Task 2: Create NER Service (4h)

**File:** `packages/api/app/services/ml/ner_service.py`

```python
"""
NER Service: Named Entity Recognition using spaCy.
Extracts people, organizations, products, and events from articles.
"""

import asyncio
import structlog
from typing import List, Dict, Set
from dataclasses import dataclass
from functools import lru_cache

log = structlog.get_logger()

@dataclass
class Entity:
    """Represents an extracted entity."""
    text: str
    label: str  # PERSON, ORG, PRODUCT, etc.
    start: int  # Character position
    end: int
    
    def to_dict(self) -> dict:
        return {
            "text": self.text,
            "label": self.label,
        }


class NERService:
    """
    Named Entity Recognition service using spaCy.
    Lightweight (~100MB RAM), fast (~50ms/article).
    """
    
    # Entity types we care about
    RELEVANT_LABELS: Set[str] = {
        "PER",      # Person
        "ORG",      # Organization
        "PRODUCT",  # Product
        "GPE",      # Geopolitical entity (countries, cities)
        "EVENT",    # Events
        "WORK_OF_ART",  # Books, movies, etc.
    }
    
    # Common words to filter out (case-insensitive)
    FILTERED_WORDS: Set[str] = {
        "le", "la", "les", "un", "une", "des",
        "et", "ou", "mais", "donc", "car",
        "ce", "cet", "cette", "ces",
        "mon", "ton", "son", "notre", "votre", "leur",
        "il", "elle", "on", "nous", "vous", "ils", "elles",
        "je", "tu", "me", "te", "se",
        "à", "de", "pour", "par", "sur", "dans", "avec",
    }
    
    def __init__(self):
        self._nlp = None
        self._model_name = "fr_core_news_md"
        self._load_model()
    
    def _load_model(self) -> None:
        """Load spaCy model."""
        try:
            import spacy
            
            log.info("ner.loading_model", model=self._model_name)
            
            self._nlp = spacy.load(self._model_name)
            
            log.info("ner.model_loaded", model=self._model_name)
            
        except OSError as e:
            log.error("ner.model_not_found", 
                     model=self._model_name,
                     error=str(e))
            log.error("ner.run_install", 
                     command="python -m spacy download fr_core_news_md")
            raise
        except Exception as e:
            log.error("ner.load_error", error=str(e))
            raise
    
    async def extract_entities(
        self,
        title: str,
        description: str = "",
        max_entities: int = 10,
    ) -> List[Entity]:
        """
        Extract entities from article text.
        
        Args:
            title: Article title
            description: Article description/body
            max_entities: Maximum entities to return
            
        Returns:
            List of Entity objects
        """
        if not self._nlp:
            log.warning("ner.not_loaded")
            return []
        
        # Combine title and description
        text = f"{title}. {description}".strip() if description else title
        
        if not text:
            return []
        
        try:
            # Run in thread pool to not block event loop
            loop = asyncio.get_event_loop()
            doc = await loop.run_in_executor(None, self._nlp, text)
            
            # Extract and filter entities
            entities = self._process_entities(doc.ents, max_entities)
            
            log.debug(
                "ner.extracted",
                title=title[:50],
                entity_count=len(entities),
                entities=[e.text for e in entities],
            )
            
            return entities
            
        except Exception as e:
            log.error("ner.extraction_error", error=str(e), title=title[:50])
            return []
    
    def _process_entities(
        self,
        spacy_entities,
        max_entities: int,
    ) -> List[Entity]:
        """Process spaCy entities into our format."""
        entities = []
        seen: Set[str] = set()
        
        for ent in spacy_entities:
            # Filter by label
            if ent.label_ not in self.RELEVANT_LABELS:
                continue
            
            # Clean entity text
            text = self._clean_entity_text(ent.text)
            
            # Filter common words
            if text.lower() in self.FILTERED_WORDS:
                continue
            
            # Deduplicate (case-insensitive)
            text_lower = text.lower()
            if text_lower in seen:
                continue
            seen.add(text_lower)
            
            # Map spaCy labels to our labels
            label = self._map_label(ent.label_)
            
            entities.append(Entity(
                text=text,
                label=label,
                start=ent.start_char,
                end=ent.end_char,
            ))
            
            if len(entities) >= max_entities:
                break
        
        return entities
    
    def _clean_entity_text(self, text: str) -> str:
        """Clean entity text (remove extra spaces, normalize)."""
        # Remove leading/trailing whitespace
        text = text.strip()
        
        # Remove common prefixes/suffixes
        text = text.replace("' ", "'")  # French apostrophe spacing
        
        # Normalize whitespace
        text = " ".join(text.split())
        
        return text
    
    def _map_label(self, spacy_label: str) -> str:
        """Map spaCy labels to our standard labels."""
        label_map = {
            "PER": "PERSON",
            "ORG": "ORG",
            "PRODUCT": "PRODUCT",
            "GPE": "LOCATION",
            "EVENT": "EVENT",
            "WORK_OF_ART": "WORK_OF_ART",
        }
        return label_map.get(spacy_label, spacy_label)
    
    def is_ready(self) -> bool:
        """Check if service is ready."""
        return self._nlp is not None
    
    def get_stats(self) -> dict:
        """Get service stats."""
        return {
            "model_loaded": self.is_ready(),
            "model_name": self._model_name,
            "relevant_labels": list(self.RELEVANT_LABELS),
        }


# Singleton
_ner_service: NERService | None = None


def get_ner_service() -> NERService:
    """Get NER service singleton."""
    global _ner_service
    if _ner_service is None:
        _ner_service = NERService()
    return _ner_service
```

### Task 3: Database Schema Update (1h)

**File:** `packages/api/alembic/versions/xxx_add_entities_to_content.py`

```python
def upgrade():
    # Add entities column to contents
    op.add_column(
        'contents',
        sa.Column('entities', postgresql.JSONB, nullable=True)
    )
    
    # Create GIN index for querying
    op.create_index(
        'idx_contents_entities',
        'contents',
        ['entities'],
        postgresql_using='gin'
    )

def downgrade():
    op.drop_index('idx_contents_entities')
    op.drop_column('contents', 'entities')
```

**Update Content Model:**

```python
# app/models/content.py

class Content(Base):
    # ... existing columns ...
    
    topics: Mapped[Optional[list]] = mapped_column(
        postgresql.JSONB, nullable=True
    )
    
    entities: Mapped[Optional[list]] = mapped_column(
        postgresql.JSONB, nullable=True
    )
```

### Task 4: Integrate in ClassificationWorker (3h)

**File:** `packages/api/app/workers/classification_worker.py` (update)

```python
from app.services.ml.ner_service import get_ner_service

class ClassificationWorker:
    """
    Enhanced worker with NER extraction.
    """
    
    def __init__(self):
        # ... existing ...
        self.ner = get_ner_service()
    
    async def _classify_content(self, content: Content) -> tuple[list[str], list[dict]]:
        """
        Classify content and extract entities.
        
        Returns:
            (topics, entities)
        """
        topics = []
        entities = []
        
        # 1. Topic classification (mDeBERTa)
        if self.classifier and self.classifier.is_ready():
            topics = await self.classifier.classify_async(
                title=content.title,
                description=content.description or "",
            )
        
        # 2. Entity extraction (spaCy)
        if self.ner and self.ner.is_ready():
            ner_entities = await self.ner.extract_entities(
                title=content.title,
                description=content.description or "",
                max_entities=10,
            )
            entities = [e.to_dict() for e in ner_entities]
        
        # Fallback to source topics
        if not topics and content.source:
            topics = content.source.granular_topics or []
        
        return topics, entities
    
    async def process_batch(self) -> int:
        """Process batch with both classification and NER."""
        # ... dequeue items ...
        
        for item in items:
            try:
                content = await session.get(Content, item.content_id)
                
                # Get topics and entities
                topics, entities = await self._classify_content(content)
                
                # Update content
                content.topics = topics
                content.entities = entities
                
                # Mark queue item completed
                await queue_service.mark_completed_with_entities(
                    item.id, topics, entities
                )
                
            except Exception as e:
                await queue_service.mark_failed(item.id, str(e))
```

### Task 5: Update Queue Service (1h)

**File:** `packages/api/app/services/classification_queue_service.py` (add method)

```python
async def mark_completed_with_entities(
    self, 
    queue_id: UUID, 
    topics: list[str],
    entities: list[dict],
) -> None:
    """Mark completed with topics AND entities."""
    item = await self.session.get(ClassificationQueue, queue_id)
    if item:
        item.status = 'completed'
        item.processed_at = datetime.utcnow()
        item.updated_at = datetime.utcnow()
        
        # Update content
        content = await self.session.get(Content, item.content_id)
        if content:
            content.topics = topics
            content.entities = entities
        
        await self.session.commit()
```

---

## 🧪 Testing

### Unit Tests

```python
# tests/ml/test_ner_service.py

@pytest.mark.asyncio
async def test_extract_person():
    """Test extracting person entity."""
    ner = NERService()
    
    entities = await ner.extract_entities(
        title="Emmanuel Macron annonce de nouvelles mesures",
    )
    
    assert len(entities) > 0
    assert any(e.text == "Emmanuel Macron" and e.label == "PERSON" 
               for e in entities)

@pytest.mark.asyncio
async def test_extract_organization():
    """Test extracting organization."""
    ner = NERService()
    
    entities = await ner.extract_entities(
        title="Tesla annonce une nouvelle usine en Allemagne",
    )
    
    assert any(e.text == "Tesla" and e.label == "ORG" 
               for e in entities)

@pytest.mark.asyncio
async def test_no_common_words():
    """Test filtering common words."""
    ner = NERService()
    
    entities = await ner.extract_entities(
        title="Le président et le ministre",
    )
    
    # "Le" should be filtered
    assert not any(e.text.lower() == "le" for e in entities)
```

### Performance Test

```python
@pytest.mark.asyncio
async def test_ner_performance():
    """Test NER performance <50ms."""
    ner = NERService()
    
    long_text = "Lorem ipsum... " * 100  # ~500 words
    
    import time
    start = time.time()
    
    await ner.extract_entities(title="Test", description=long_text)
    
    elapsed_ms = (time.time() - start) * 1000
    assert elapsed_ms < 50, f"NER took {elapsed_ms}ms"
```

---

## 📊 Expected Results

### Example Extractions

| Article Title | Entities Extracted |
|--------------|-------------------|
| "Elon Musk achète Twitter" | [{"text": "Elon Musk", "label": "PERSON"}, {"text": "Twitter", "label": "ORG"}] |
| "Apple lance l'iPhone 15" | [{"text": "Apple", "label": "ORG"}, {"text": "iPhone 15", "label": "PRODUCT"}] |
| "COP29 à Dubaï" | [{"text": "COP29", "label": "EVENT"}, {"text": "Dubaï", "label": "LOCATION"}] |

### Performance

| Metric | Target | Expected |
|--------|--------|----------|
| Extraction time | <50ms | ~20-30ms |
| RAM usage | <100MB | ~80MB |
| Entities per article | 3-10 | 5-8 average |

---

## 📁 Files Created

| File | Description |
|------|-------------|
| `app/services/ml/ner_service.py` | NER service with spaCy |
| `alembic/versions/xxx_add_entities_to_content.py` | DB migration |
| `app/models/content.py` | Add entities column |
| `tests/ml/test_ner_service.py` | Unit tests |
| `scripts/install_spacy_model.sh` | Installation script |

---

## 🚀 Deployment

```bash
# 1. Install dependencies
pip install -r requirements-ml.txt

# 2. Download French model
python -m spacy download fr_core_news_md

# 3. Run migration
alembic upgrade head

# 4. Test extraction
python -c "
from app.services.ml.ner_service import NERService
ner = NERService()
import asyncio
result = asyncio.run(ner.extract_entities('Elon Musk launches Tesla'))
print(result)
"
```

---

*Story created: 2026-01-29*  
*Part of: Recommendation Engine V3*
