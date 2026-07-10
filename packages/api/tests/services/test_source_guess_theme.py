"""Tests unitaires de `SourceService._guess_theme()`.

Régression de l'incident 2026-07-10 : Basket USA (source sport) taguée `tech`
parce que le matching sous-chaîne faisait matcher « ia » dans « média », d'où une
égalité de score `tech`/`culture` tie-breakée arbitrairement sur `tech`.
"""

from app.services.ml.topic_theme_mapper import VALID_THEMES
from app.services.source_service import SourceService


def _guess(name: str, description: str) -> str:
    # _guess_theme n'utilise pas la DB : on peut instancier sans session réelle.
    return SourceService(db=None)._guess_theme(name, description)


def test_basket_usa_not_tech():
    """Le cas réel de l'incident : nom + description Basket USA -> sport, pas tech."""
    theme = _guess(
        "Basket USA",
        "Groupe média spécialisé dans les médias sportifs digitaux, "
        "média de référence NBA.",
    )
    assert theme == "sport"
    assert theme != "tech"


def test_word_boundary_no_substring_false_positive():
    """« média »/« médiatisation » ne doivent plus matcher le mot-clé tech « ia »."""
    theme = _guess("Le Média", "Un média d'information et de médiatisation citoyenne.")
    assert theme != "tech"


def test_legit_tech_source_still_matches():
    """Non-régression : une vraie source tech (mots isolés) reste taguée tech."""
    theme = _guess(
        "Next.ink",
        "Actualité tech : IA, startup, logiciel et innovations du numérique.",
    )
    assert theme == "tech"


def test_score_tie_falls_back_to_society():
    """Égalité de score entre deux thèmes -> défaut `society`, pas l'ordre du dict."""
    # « art » (culture) + « justice » (society) : 1 point chacun, aucun autre match.
    theme = _guess("Revue", "Chronique sur l'art et la justice.")
    assert theme == "society"


def test_no_match_defaults_to_society():
    """Aucun mot-clé -> défaut `society`."""
    assert _guess("Zzz", "Contenu neutre sans mot-clé thématique.") == "society"


def test_guessed_theme_is_always_valid():
    """Tout thème deviné doit appartenir à la taxonomie officielle."""
    for name, desc in [
        ("Basket USA", "média sportif NBA"),
        ("Next.ink", "tech IA startup"),
        ("Zzz", "neutre"),
    ]:
        assert _guess(name, desc) in VALID_THEMES
