"""Filtre de langue pour la curation `is_good_news`.

Deux fonctions complémentaires :

- `is_french_source(name)` : whitelist explicite des sources francophones
  connues du pipeline d'ingestion. Une source absente est considérée
  non-francophone (rejet par défaut, pour éviter de polluer le digest).
- `looks_english(title)` : garde-fou heuristique sur le titre. Détecte la
  présence de mots fonctionnels typiquement anglais. Utilisé pour rattraper
  les rares cas où une source whitelistée publie occasionnellement un article
  en anglais (syndication, traduction).

Aucune dépendance externe, aucun appel API. Tout se joue sur des sets en
mémoire et un tokenizer minimal.
"""

from __future__ import annotations

# Sous-chaînes (insensibles à la casse) qui identifient une source
# francophone. Construit à partir de la liste réelle des sources observées
# en production (cf. story 15.2). Volontairement permissif : on préfère
# inclure une source borderline et laisser le garde-fou heuristique trier.
_FRENCH_SOURCE_TOKENS: tuple[str, ...] = (
    "actualités vidal",
    "arte",
    "assemblée nationale",
    "bdm",
    "blog du modérateur",
    "cerveau & psycho",
    "contrepoints",
    "courrier international",
    "europe 1",
    "developpez.com",
    "france culture",
    "france info",
    "franceinfo",
    "frandroid",
    "gamekult",
    "ign france",
    "l'humanité",
    "humanité",
    "la croix",
    "la science cqfd",
    "lcp",
    "le figaro",
    "le monde",
    "le nouvel obs",
    "le parisien",
    "korben",
    "linfodurable",
    "mediapart",
    "numerama",
    "ouest-france",
    "ouest france",
    "r/france",
    "reporterre",
    "slate fr",
    "télérama",
    "telerama",
    "trust my science",
    "vertige media",
    "20 minutes",
    "rfi",
    "rtl",
    "rmc",
    "bfm",
    "lci",
)

# Mots fonctionnels anglais courants, en lowercase, à comparer après
# tokenisation simple. La liste est volontairement courte : on cherche
# des marqueurs très fréquents pour limiter les faux positifs sur du
# français contenant un anglicisme isolé.
_ENGLISH_FUNCTION_WORDS: frozenset[str] = frozenset(
    {
        "the",
        "of",
        "and",
        "for",
        "this",
        "that",
        "with",
        "from",
        "are",
        "is",
        "was",
        "were",
        "have",
        "has",
        "will",
        "would",
        "should",
        "could",
        "their",
        "they",
        "what",
        "when",
        "why",
        "how",
        "about",
        "into",
        "after",
        "before",
        "between",
        "against",
        "without",
    }
)


def is_french_source(source_name: str | None) -> bool:
    """Renvoie True si la source est listée comme francophone.

    Args:
        source_name: Nom de la source tel que stocké en base (peut être
            None ou vide pour les contenus orphelins).

    Returns:
        True si une sous-chaîne de la whitelist est trouvée dans le nom
        (insensible à la casse). False sinon — y compris pour None / "".
    """
    if not source_name:
        return False
    needle = source_name.casefold()
    return any(token in needle for token in _FRENCH_SOURCE_TOKENS)


def detect_language(title: str | None, source_name: str | None) -> str | None:
    """Heuristique : "en" si le titre semble anglais, sinon "fr" si la source
    est francophone connue, sinon None. Single source of truth partagée entre
    le backfill (migration `lg01_add_language_to_contents`) et l'ingestion
    (`sync_service._save_content`) — si la règle évolue ("on ajoute es"), les
    deux call sites restent cohérents.
    """
    if looks_english(title):
        return "en"
    if is_french_source(source_name):
        return "fr"
    return None


def looks_english(title: str | None) -> bool:
    """Renvoie True si le titre semble être en anglais.

    Heuristique : on tokenise sur les espaces et la ponctuation simple,
    puis on compte combien de tokens appartiennent à la liste de mots
    fonctionnels anglais. À partir de 2 occurrences distinctes, on
    considère que le titre est anglophone.

    Args:
        title: Titre de l'article. None / vide → False (on laisse passer
            pour ne pas rejeter par excès de prudence).

    Returns:
        True si ≥ 2 mots fonctionnels anglais distincts sont trouvés.
    """
    if not title:
        return False

    normalized = "".join(
        c if c.isalpha() or c == "'" else " " for c in title.casefold()
    )
    tokens = set(normalized.split())
    matches = tokens & _ENGLISH_FUNCTION_WORDS
    return len(matches) >= 2
