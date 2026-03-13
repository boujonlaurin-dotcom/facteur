"""Editorial digest pipeline — Stories 10.23 + 10.24.

Curation LLM + matching actu/deep + rédaction éditoriale + pépite + coup de coeur.
"""

from app.services.editorial.pipeline import EditorialPipelineService
from app.services.editorial.schemas import (
    CoupDeCoeurArticle,
    EditorialGlobalContext,
    EditorialPipelineResult,
    EditorialSubject,
    MatchedActuArticle,
    MatchedDeepArticle,
    PepiteArticle,
    SelectedTopic,
    SubjectWriting,
    WritingOutput,
)
from app.services.editorial.writer import EditorialWriterService

__all__ = [
    "CoupDeCoeurArticle",
    "EditorialGlobalContext",
    "EditorialPipelineService",
    "EditorialPipelineResult",
    "EditorialSubject",
    "EditorialWriterService",
    "MatchedActuArticle",
    "MatchedDeepArticle",
    "PepiteArticle",
    "SelectedTopic",
    "SubjectWriting",
    "WritingOutput",
]
