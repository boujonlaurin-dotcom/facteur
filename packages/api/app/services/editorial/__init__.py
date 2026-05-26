"""Editorial digest pipeline — Stories 10.23 + 10.24.

Curation LLM + actu matching + perspective analysis.

Note: writing/pépite/coup_de_coeur/actu_decalee stages and the "Pas de recul"
deep_matcher integration were removed/disabled in the post-unification cleanup.
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
    "EditorialGlobalContext",
    "EditorialPipelineService",
    "EditorialPipelineResult",
    "EditorialSubject",
    "MatchedActuArticle",
    "MatchedDeepArticle",
    "SelectedTopic",
]
