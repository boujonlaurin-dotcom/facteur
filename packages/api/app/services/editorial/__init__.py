"""Editorial digest pipeline — Story 10.23.

Curation LLM + matching actu/deep pour le digest éditorialisé.
"""

from app.services.editorial.pipeline import EditorialPipelineService
from app.services.editorial.schemas import (
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
    SelectedTopic,
)

__all__ = [
    "EditorialPipelineService",
    "EditorialGlobalContext",
    "EditorialPipelineResult",
    "EditorialSubject",
    "MatchedActuArticle",
    "MatchedDeepArticle",
    "SelectedTopic",
]
