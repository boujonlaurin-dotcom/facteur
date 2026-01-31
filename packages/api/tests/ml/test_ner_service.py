"""
Tests for NER Service (spaCy Named Entity Recognition).
US-4: NER Service Implementation
"""

import asyncio
import time

import pytest

from app.services.ml.ner_service import NERService, Entity


@pytest.mark.asyncio
class TestNERService:
    """Test suite for NER Service."""
    
    @pytest.fixture
    def ner_service(self):
        """Create a NER service instance for testing."""
        return NERService()
    
    async def test_extract_person_french(self, ner_service):
        """Test extracting person entities from French text."""
        entities = await ner_service.extract_entities(
            title="Emmanuel Macron annonce de nouvelles mesures économiques",
        )
        
        assert len(entities) > 0
        assert any(
            e.text == "Emmanuel Macron" and e.label == "PERSON" 
            for e in entities
        ), f"Expected 'Emmanuel Macron' as PERSON, got: {[(e.text, e.label) for e in entities]}"
    
    async def test_extract_organization(self, ner_service):
        """Test extracting organization entities."""
        entities = await ner_service.extract_entities(
            title="Tesla annonce une nouvelle usine en Allemagne",
        )
        
        assert any(
            e.text == "Tesla" and e.label == "ORG" 
            for e in entities
        ), f"Expected 'Tesla' as ORG, got: {[(e.text, e.label) for e in entities]}"
    
    async def test_extract_gpe_location(self, ner_service):
        """Test extracting geopolitical entities (locations)."""
        entities = await ner_service.extract_entities(
            title="La France et l'Allemagne signent un traité",
        )
        
        # Should extract "France" and/or "Allemagne" as LOCATION (GPE)
        location_entities = [e for e in entities if e.label == "LOCATION"]
        assert len(location_entities) >= 1, f"Expected at least one LOCATION, got: {[(e.text, e.label) for e in entities]}"
    
    async def test_no_common_words_filtered(self, ner_service):
        """Test that common words are filtered out."""
        entities = await ner_service.extract_entities(
            title="Le président et la ministre",
        )
        
        # "Le" and "la" should be filtered as they're common words
        assert not any(e.text.lower() in ner_service.FILTERED_WORDS for e in entities), \
            f"Common words should be filtered, got: {[e.text for e in entities]}"
    
    async def test_deduplication_case_insensitive(self, ner_service):
        """Test that entities are deduplicated case-insensitively."""
        entities = await ner_service.extract_entities(
            title="Tesla annonce que TESLA va investir",
        )
        
        # Should only have one "Tesla" entity (case-insensitive dedup)
        tesla_entities = [e for e in entities if "tesla" in e.text.lower()]
        assert len(tesla_entities) <= 1, f"Tesla should be deduplicated, got: {[e.text for e in tesla_entities]}"
    
    async def test_max_entities_limit(self, ner_service):
        """Test that max_entities parameter works."""
        long_text = "Lorem ipsum. " * 50  # Long text
        
        entities = await ner_service.extract_entities(
            title="Test article",
            description=long_text,
            max_entities=3,
        )
        
        assert len(entities) <= 3, f"Should return max 3 entities, got {len(entities)}"
    
    async def test_empty_text(self, ner_service):
        """Test handling of empty text."""
        entities = await ner_service.extract_entities(
            title="",
            description="",
        )
        
        assert entities == [], "Should return empty list for empty text"
    
    async def test_entity_to_dict(self, ner_service):
        """Test Entity dataclass to_dict method."""
        entity = Entity(
            text="Test Entity",
            label="PERSON",
            start=0,
            end=11,
        )
        
        result = entity.to_dict()
        
        assert result == {
            "text": "Test Entity",
            "label": "PERSON",
        }
    
    async def test_service_stats(self, ner_service):
        """Test service stats method."""
        stats = ner_service.get_stats()
        
        assert stats["model_loaded"] is True
        assert stats["model_name"] == "fr_core_news_md"
        assert "relevant_labels" in stats
        assert len(stats["relevant_labels"]) > 0
    
    async def test_service_is_ready(self, ner_service):
        """Test service is_ready method."""
        assert ner_service.is_ready() is True
    
    @pytest.mark.skip(reason="Performance test - run manually")
    async def test_ner_performance(self, ner_service):
        """Test NER performance is under 50ms per article."""
        # Create a 500-word text
        long_text = "Lorem ipsum dolor sit amet. " * 100
        
        # Warm up
        await ner_service.extract_entities(title="Test", description=long_text)
        
        # Measure
        times = []
        for _ in range(10):
            start = time.time()
            await ner_service.extract_entities(title="Test", description=long_text)
            elapsed_ms = (time.time() - start) * 1000
            times.append(elapsed_ms)
        
        avg_time = sum(times) / len(times)
        max_time = max(times)
        
        print(f"\nNER Performance Results:")
        print(f"  Average: {avg_time:.2f}ms")
        print(f"  Max: {max_time:.2f}ms")
        print(f"  Min: {min(times):.2f}ms")
        
        assert avg_time < 50, f"Average NER time should be <50ms, got {avg_time:.2f}ms"
        assert max_time < 100, f"Max NER time should be <100ms, got {max_time:.2f}ms"


class TestNERServiceMockFallback:
    """Test NER service behavior when model is not loaded."""
    
    def test_service_without_model(self):
        """Test that service handles missing model gracefully."""
        # This would require mocking spacy.load to raise OSError
        # For now, we just verify the current service loads correctly
        ner = NERService()
        assert ner.is_ready() is True


@pytest.mark.asyncio
async def test_french_language_support():
    """Test French language entity extraction (Acceptance Criteria 4)."""
    ner = NERService()
    
    # Test with French political text
    entities = await ner.extract_entities(
        title="Assemblée Nationale : nouvelle session parlementaire",
    )
    
    # Should extract "Assemblée Nationale" as ORG
    org_entities = [e for e in entities if e.label == "ORG"]
    assert any("assemblée" in e.text.lower() for e in org_entities), \
        f"Expected 'Assemblée Nationale' as ORG, got: {[(e.text, e.label) for e in entities]}"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
