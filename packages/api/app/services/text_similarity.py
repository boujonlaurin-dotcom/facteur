"""Helpers de similarité textuelle (titre normalisation + Jaccard).

Extrait depuis briefing/importance_detector.py pour permettre la réutilisation
hors du pipeline de digest (ex: PerspectiveService post-filter).
"""

import re
import unicodedata

# Stop words français courants (à filtrer des titres).
# IMPORTANT: Les mots sont en version SANS ACCENT car normalize_title() strip les accents.
# Enrichi avec les mots news-génériques pour éviter les faux clusters.
FRENCH_STOP_WORDS: frozenset[str] = frozenset(
    [
        # --- Articles, pronoms, déterminants ---
        "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux",
        "ce", "ces", "cet", "cette",
        "mon", "ton", "son", "ma", "ta", "sa", "mes", "tes", "ses",
        "notre", "votre", "leur", "nos", "vos", "leurs",
        "qui", "que", "quoi", "dont", "quel", "quelle", "quels", "quelles",
        "il", "elle", "ils", "elles", "on", "nous", "vous", "je", "tu",
        "se", "ne", "pas", "plus", "moins", "tres", "aussi",
        "tout", "tous", "toute", "meme", "autres", "autre",
        # --- Conjonctions, prépositions ---
        "et", "ou", "mais", "donc", "or", "ni", "car",
        "pour", "par", "avec", "sans", "sous", "sur", "dans", "en",
        "est", "sont", "ont", "entre", "apres", "avant", "comme",
        "vers", "chez", "face", "contre", "selon", "suite",
        "depuis", "lors", "durant", "pendant",
        # --- Verbes courants ---
        "etre", "avoir", "faire", "fait", "dit", "peut", "faut", "doit",
        "ete", "sera", "peuvent", "vont", "veut",
        "alors", "si", "quand", "comment", "pourquoi", "combien",
        # --- Adverbes ---
        "encore", "toujours", "jamais", "souvent",
        "bien", "mal", "peu", "beaucoup", "trop", "assez", "vraiment",
        # --- Noms news-génériques (causent les faux clusters) ---
        "monde", "pays", "president", "gouvernement", "ministre",
        "politique", "economie", "societe", "histoire",
        "international", "national", "local",
        # --- Adjectifs courants ---
        "nouveau", "nouvelle", "nouveaux", "nouvelles",
        "grand", "grande", "grands", "grandes",
        "petit", "petite", "petits", "petites",
        "premier", "premiere", "dernier", "derniere",
        # --- Temporels ---
        "annee", "annees", "jour", "jours", "fois", "temps",
        "heure", "heures", "minute", "minutes",
        # --- Nombres ---
        "deux", "trois", "quatre", "cinq",
        # --- Personnes/lieux génériques ---
        "personnes", "gens", "hommes", "femmes", "enfants",
        "ville", "villes", "region", "zone", "secteur",
        # --- Abstraits ---
        "question", "probleme", "solution", "projet", "plan", "mesure",
        "effet", "impact", "consequence", "resultat", "cause", "raison",
        # --- Géo génériques ---
        "europe", "europeen", "europeenne", "americain", "occidental",
        # --- News filler ---
        "informations", "article", "articles",
        "savoir", "retenir", "exclusif", "exclusive", "urgent", "breaking",
        "video", "photo", "photos", "images", "podcast", "interview",
        "analyse", "decryptage", "explications", "enquete", "dossier",
        "revele", "montre", "indique", "suggere", "affirme", "estime",
    ]
)


def normalize_title(title: str) -> set[str]:
    """Normalise un titre en ensemble de tokens.

    Transformations: lowercase → strip accents → strip ponctuation/chiffres →
    split → filtre len>=3 et hors stop words.
    """
    if not title:
        return set()

    text = title.lower()
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = re.sub(r"[^\w\s]", " ", text)
    text = re.sub(r"\d+", "", text)

    tokens = text.split()
    return {t for t in tokens if len(t) >= 3 and t not in FRENCH_STOP_WORDS}


def jaccard_similarity(tokens_a: set[str], tokens_b: set[str]) -> float:
    """Jaccard = |A ∩ B| / |A ∪ B|. Retourne 0.0 si l'un des deux est vide."""
    if not tokens_a or not tokens_b:
        return 0.0
    union = len(tokens_a | tokens_b)
    if union == 0:
        return 0.0
    return len(tokens_a & tokens_b) / union
