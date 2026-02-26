"""
NER Service: Named Entity Recognition using spaCy.
Extracts people, organizations, products, and events from articles.
US-4: NER Service Implementation
"""

import asyncio
from dataclasses import dataclass

import structlog

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
    RELEVANT_LABELS: set[str] = {
        "PER",  # Person
        "ORG",  # Organization
        "PRODUCT",  # Product
        "GPE",  # Geopolitical entity (countries, cities)
        "EVENT",  # Events
        "WORK_OF_ART",  # Books, movies, etc.
    }

    # Common words to filter out (case-insensitive)
    FILTERED_WORDS: set[str] = {
        "le",
        "la",
        "les",
        "un",
        "une",
        "des",
        "et",
        "ou",
        "mais",
        "donc",
        "car",
        "ce",
        "cet",
        "cette",
        "ces",
        "mon",
        "ton",
        "son",
        "notre",
        "votre",
        "leur",
        "il",
        "elle",
        "on",
        "nous",
        "vous",
        "ils",
        "elles",
        "je",
        "tu",
        "me",
        "te",
        "se",
        "à",
        "de",
        "pour",
        "par",
        "sur",
        "dans",
        "avec",
        "the",
        "a",
        "an",
        "and",
        "or",
        "but",
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

        except ImportError:
            log.warning(
                "ner.spacy_not_installed",
                message="spaCy not installed. NER service will be unavailable.",
                install_command="pip install spacy==3.8.11 && python -m spacy download fr_core_news_md",
            )
            self._nlp = None
        except OSError as e:
            log.error("ner.model_not_found", model=self._model_name, error=str(e))
            log.error(
                "ner.run_install", command="python -m spacy download fr_core_news_md"
            )
            self._nlp = None
        except Exception as e:
            log.error("ner.load_error", error=str(e))
            self._nlp = None

    async def extract_entities(
        self,
        title: str,
        description: str = "",
        max_entities: int = 10,
    ) -> list[Entity]:
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
    ) -> list[Entity]:
        """Process spaCy entities into our format."""
        entities = []
        seen: set[str] = set()

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

            entities.append(
                Entity(
                    text=text,
                    label=label,
                    start=ent.start_char,
                    end=ent.end_char,
                )
            )

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
