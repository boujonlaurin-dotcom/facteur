"""Tests unitaires pour `language_filter`."""

from __future__ import annotations

import pytest

from app.services.ml.language_filter import is_french_source, looks_english


class TestIsFrenchSource:
    @pytest.mark.parametrize(
        "name",
        [
            "Le Monde",
            "le monde",
            "LE MONDE",
            "Le Figaro",
            "Mediapart",
            "France Culture",
            "France Info",
            "Numerama",
            "Numerama — Décryptages",
            "Ouest-France",
            "Reporterre",
            "Slate FR — Explainers",
            "Télérama - Actus et critiques culturelles",
            "Trust My Science",
            "L'Humanité",
            "Frandroid",
            "Korben",
            "Les news de Korben",
            "Linfodurable.fr",
            "Cerveau & Psycho",
            "Courrier International",
            "Contrepoints",
            "Vertige Media",
            "Gamekult - Jeux vidéo PC et consoles",
            "IGN France",
            "ARTE",
            "Assemblée nationale",
            "LCP - Assemblée nationale",
            "BDM",
            "Europe 1",
            "La Croix — Analyses",
            "La Science CQFD",
            "Actualités VIDAL",
        ],
    )
    def test_known_french_sources(self, name: str) -> None:
        assert is_french_source(name) is True

    @pytest.mark.parametrize(
        "name",
        [
            "BBC News",
            "The Guardian",
            "The New York Times",
            "Ars Technica",
            "MIT Technology Review",
            "Politico Europe",
            "Techmeme",
            "Reddit's Startup Community",
            "Random English Outlet",
            "",
            None,
        ],
    )
    def test_non_french_sources_rejected(self, name: str | None) -> None:
        assert is_french_source(name) is False


class TestLooksEnglish:
    @pytest.mark.parametrize(
        "title",
        [
            "The future of AI is uncertain and slow",
            "How the new policy will change the way we work",
            "What this means for the industry",
            "Five things to know about the deal",
            "The rise and fall of the empire",
        ],
    )
    def test_english_titles_detected(self, title: str) -> None:
        assert looks_english(title) is True

    @pytest.mark.parametrize(
        "title",
        [
            "L'Assemblée vote la fin du glyphosate dans les jardins publics",
            "Le Monde publie une enquête inédite sur les retraites",
            "Une avancée majeure contre le cancer du pancréas",
            "Réchauffement climatique : la France adopte un plan ambitieux",
            "Découverte d'une nouvelle exoplanète habitable",
            "Mort de Charles Aznavour à 94 ans",
            "",
            None,
        ],
    )
    def test_french_titles_pass(self, title: str | None) -> None:
        assert looks_english(title) is False

    def test_single_english_token_not_flagged(self) -> None:
        # "the" tout seul ne doit pas suffire (les anglicismes sont fréquents
        # dans la presse FR — ex. "the place to be").
        assert looks_english("Voici the place to be cet été à Marseille") is False

    def test_two_english_tokens_flagged(self) -> None:
        assert looks_english("This is a test") is True
