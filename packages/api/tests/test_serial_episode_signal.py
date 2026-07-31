"""Tests du signal « feuilleton / épisode de série » et de son malus.

Cf. docs/bugs/bug-curation-entree-sections-thematiques.md (Partie 2).

Le signal doit :
- attraper les compteurs de série réellement produits par les flux (compteur nu
  au milieu du titre, introduisant un sous-titre) ;
- ne JAMAIS attraper une date JJ/MM de fin de titre, très courante sur les fils
  d'actualité (« … - 24/07 ») ;
- ne déprioriser qu'en `personalized_theme_mode` (décision PO).

Les titres positifs et négatifs sont des relevés réels (sources suivies du
compte de référence, fenêtre 7 jours), pas des exemples inventés.
"""

from uuid import uuid4

import pytest

from app.models.enums import ContentType
from app.services.recommendation.filter_presets import is_serial_episode_title
from app.services.recommendation.pillars.penalties import PenaltyPass
from app.services.recommendation.scoring_config import ScoringWeights

# Relevé réel — feuilletons / épisodes / numérotation de newsletter.
SERIAL_TITLES = [
    "Les sciences dans le règne animal 4/4 : Emotions des cétacés : les ondes sensibles",
    "Et si nous vivions dans une simulation  3/3 : Ce qu'on gagne à interroger notre réalité",
    "La révolution numérique 2/10 : 1942-1946 : l’ENIAC, le premier ordinateur électronique",
    "La mémoire des vaincus : histoires intimes de la guerre d'Espagne 13/25 : On l'appelait La Pastora",
    "Extrait : Les après-midi de France Culture - Les cosmologies, mythes et sciences du monde 4/22 : L’Inde",
    "#IA (7/10). Société : le grand effritement",
    "QSPTAG #332 — 24 juillet 2026",
    "Ardennes 1944 : la bande au bossu 1/2 : Un maquis américain",
    # Forme déjà couverte par NEWS_BULLETIN_PATTERNS — doit l'être ici aussi.
    "Un truc en plus (1/4)",
]

# Relevé réel — actualité datée JJ/MM, ne doit JAMAIS être dépriorisée.
NEWS_TITLES = [
    "Édition spéciale : feu en Gironde, 3 400 hectares brûlés (préfecture) - 23/07",
    "BFM Conso : Incendies, ce qu'ils coutent (vraiment) à la France - 24/07",
    "intensité du feu en gironde par vue satellite le 24/07",
    "En portefeuille : La saison des publications lancée - 24/07",
    "Le Grand entretien : Les solutions pour améliorer la vie face aux canicules - 21/07",
    # Date de décembre : jour ≤ mois, donc non discriminée par le seul test
    # index ≤ total — c'est le second garde-fou (sous-titre / total > 12) qui
    # doit la sauver.
    "Un accord commercial signé le 05/12",
    # Fraction en plein texte, sans sous-titre derrière.
    "Sondage : 4/5 des Français se disent inquiets",
    "OpenAI lève 40 milliards de dollars",
    "La première partie du rapport est publiée",
]


@pytest.mark.parametrize("title", SERIAL_TITLES)
def test_detects_serial_titles(title):
    assert is_serial_episode_title(title) is True


@pytest.mark.parametrize("title", NEWS_TITLES)
def test_does_not_flag_news_titles(title):
    assert is_serial_episode_title(title) is False


def test_empty_title_is_not_serial():
    assert is_serial_episode_title(None) is False
    assert is_serial_episode_title("") is False


class _FakeContent:
    """Content minimal — le PenaltyPass ne lit que ces champs ici."""

    def __init__(self, title: str):
        self.id = uuid4()
        self.title = title
        self.source_id = uuid4()
        self.theme = "tech"
        self.topics = None
        self.entities = None
        self.content_type = ContentType.ARTICLE
        self.source = None


class _FakeContext:
    def __init__(self, personalized_theme_mode: bool):
        self.personalized_theme_mode = personalized_theme_mode
        self.muted_sources = set()
        self.muted_themes = set()
        self.muted_topics = set()
        self.muted_content_types = set()
        self.impression_data = {}


def test_malus_applied_in_tournee_mode():
    score, contributions = PenaltyPass().compute(
        _FakeContent(SERIAL_TITLES[0]), _FakeContext(personalized_theme_mode=True)
    )
    assert score == ScoringWeights.SERIAL_EPISODE_MALUS
    assert any(c.label == "Épisode d'une série" for c in contributions)


def test_malus_not_applied_outside_tournee():
    """« Pour vous », Flâner scoré et digest gardent leur classement."""
    score, contributions = PenaltyPass().compute(
        _FakeContent(SERIAL_TITLES[0]), _FakeContext(personalized_theme_mode=False)
    )
    assert score == 0.0
    assert contributions == []


def test_news_title_untouched_in_tournee_mode():
    score, contributions = PenaltyPass().compute(
        _FakeContent(NEWS_TITLES[0]), _FakeContext(personalized_theme_mode=True)
    )
    assert score == 0.0
    assert contributions == []


def test_malus_is_soft_relative_to_mutes():
    """Garde-fou de calibration : dépriorisation, jamais exclusion. Le malus
    doit rester très en deçà des mutes (source -80, thème -40) et de la
    pénalité d'impression la plus faible (-20)."""
    from app.services.recommendation.pillars.penalties import (
        MUTED_SOURCE_MALUS,
        MUTED_THEME_MALUS,
    )

    assert ScoringWeights.SERIAL_EPISODE_MALUS < 0
    assert abs(ScoringWeights.SERIAL_EPISODE_MALUS) < abs(MUTED_THEME_MALUS)
    assert abs(ScoringWeights.SERIAL_EPISODE_MALUS) < abs(MUTED_SOURCE_MALUS)
    assert abs(ScoringWeights.SERIAL_EPISODE_MALUS) < abs(
        ScoringWeights.IMPRESSION_OLD
    )
