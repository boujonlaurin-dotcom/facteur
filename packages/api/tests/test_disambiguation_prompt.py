"""Garde-fou sur le prompt de désambiguïsation.

B1 (recherche par sujets) repose sur le fait qu'un token isolé courant
(« Donald », « Patrick ») soit étendu vers le(s) sujet(s) public(s) saillant(s)
au lieu d'être renvoyé littéralement. Ce test documente cette exigence et la
règle « 1 à 3 interprétations » sans appeler le LLM.
"""

from app.services.ml.classification_service import SLUG_TO_LABEL
from app.services.ml.topic_enrichment_service import DISAMBIGUATION_SYSTEM_PROMPT


def test_prompt_documents_isolated_token_expansion():
    prompt = DISAMBIGUATION_SYSTEM_PROMPT
    # La règle d'expansion des prénoms/noms partiels est présente.
    assert "token isolé" in prompt
    # Les exemples canoniques d'expansion sont fournis.
    assert "Donald Trump" in prompt
    assert "Donald Tusk" in prompt
    assert "Patrick Bruel" in prompt


def test_prompt_keeps_one_to_three_rule():
    assert "1 à 3 interprétations" in DISAMBIGUATION_SYSTEM_PROMPT


def test_prompt_example_slugs_are_valid():
    # Tout slug_parent cité en exemple doit exister dans le référentiel.
    for slug in ("politics", "music", "economy", "tech", "food"):
        assert slug in SLUG_TO_LABEL
