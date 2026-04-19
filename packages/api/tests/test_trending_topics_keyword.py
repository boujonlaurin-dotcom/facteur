"""Unit tests for `_best_keyword` used by /feed/trending-topics.

The trending chip label was previously the full article title — now it's
the most-frequent meaningful token across the cluster's titles. This test
guards that contract: short keyword (≤ 30 chars typically), French stopwords
excluded, frequency-based selection.

See docs/bugs/bug-trending-chip-keywords.md.
"""

from app.routers.feed import _best_keyword


def test_best_keyword_picks_most_frequent_token():
    titles = [
        "Trump annonce de nouvelles sanctions contre la Russie",
        "Trump rencontre Poutine à Genève",
        "Trump signe un décret sur l'immigration",
    ]
    assert _best_keyword(titles) == "trump"


def test_best_keyword_skips_french_stopwords():
    # "dans", "pour", "avec" are stopwords — should not win even if frequent
    titles = [
        "Pékin dans la course pour l'IA avec OpenAI",
        "Pékin dans une dynamique pour rattraper avec succès",
        "Pékin dans une stratégie pour gagner avec talent",
    ]
    assert _best_keyword(titles) == "pékin"


def test_best_keyword_ignores_short_tokens():
    # Tokens < 4 chars are excluded ("psg" is 3 → excluded, "paris" wins)
    titles = [
        "PSG bat Paris en finale",
        "PSG triomphe à Paris contre Lille",
        "PSG en tête à Paris",
    ]
    assert _best_keyword(titles) == "paris"


def test_best_keyword_falls_back_to_truncated_first_title():
    # All tokens are stopwords → fallback returns first 30 chars of first title
    titles = ["dans avec pour"]
    result = _best_keyword(titles)
    assert result == "dans avec pour"


def test_best_keyword_handles_empty_list():
    assert _best_keyword([]) == ""


def test_best_keyword_label_is_short_for_chip_display():
    # Regression check: label used by SearchFilterSheet trending chip
    # must be a short keyword, never a full sentence title
    titles = [
        "Le président français Emmanuel Macron a annoncé hier soir une réforme majeure des retraites qui devrait entrer en vigueur dès janvier 2027",
        "Macron défend sa réforme face aux syndicats lors d'une allocution télévisée",
        "Macron face aux députés : la réforme passe en force avec le 49.3",
    ]
    keyword = _best_keyword(titles)
    assert keyword == "macron"
    # Capitalized form (used as label in the chip) stays short
    assert len(keyword.title()) <= 30
