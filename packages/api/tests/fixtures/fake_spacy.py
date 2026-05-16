"""Minimal spaCy doubles for hermetic tests.

Mimics the subset of `Doc / Token / Ent / Language` that
`TitleAnnotationService` consumes. Tests build a `FakeDoc` per title
they want to feed through the service, wire them into a `FakeNlp`, and
inject it onto a service instance via `service_with_nlp`.
"""

from dataclasses import dataclass, field

from app.services.title_annotation_service import TitleAnnotationService


@dataclass
class FakeToken:
    text: str
    idx: int
    pos_: str
    lemma_: str
    is_stop: bool = False


@dataclass
class FakeEnt:
    start_char: int
    end_char: int
    label_: str


@dataclass
class FakeDoc:
    tokens: list[FakeToken]
    ents: list[FakeEnt] = field(default_factory=list)

    def __iter__(self):
        return iter(self.tokens)


class FakeNlp:
    """Callable that returns a precomputed FakeDoc per title."""

    def __init__(self, docs_by_title: dict[str, FakeDoc]):
        self._docs = docs_by_title
        self.call_count = 0

    def __call__(self, title: str) -> FakeDoc:
        self.call_count += 1
        return self._docs.get(title, FakeDoc(tokens=[]))

    def pipe(self, titles):
        """Match spaCy's batched-inference API."""
        for t in titles:
            yield self(t)


def service_with_nlp(nlp) -> TitleAnnotationService:
    """Bypass __init__ to inject a fake nlp without touching the NER singleton."""
    svc = TitleAnnotationService.__new__(TitleAnnotationService)
    svc._nlp = nlp
    return svc
