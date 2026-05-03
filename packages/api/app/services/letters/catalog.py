"""Catalogue des lettres du Facteur (constantes serveur).

V1 = 3 lettres en dur. Rotation éditoriale = redeploy. Les lettres ne sont
pas en DB — la table `user_letter_progress` ne stocke que la progression
utilisateur.
"""

LETTER_0: dict = {
    "id": "letter_0",
    "num": "00",
    "title": "Bienvenue sur Facteur !",
    "default_status": "archived",
    "actions": [],
    "message": (
        "Bienvenue dans Facteur. Je m'occuperai chaque jour de te déposer "
        "ce qui mérite ton attention."
    ),
    "signature": "Le Facteur",
}

LETTER_1: dict = {
    "id": "letter_1",
    "num": "01",
    "title": "Tes premières sources",
    "default_status": "active",
    "actions": [
        {
            "id": "define_editorial_line",
            "label": "Définir ta ligne éditoriale",
            "help": "3 à 5 centres d'intérêt — tech, climat, culture…",
        },
        {
            "id": "add_5_sources",
            "label": "Ajouter 5 sources à ta sélection",
            "help": (
                "Pioche dans la liste suggérée. Tu peux toujours en retirer plus tard."
            ),
        },
        {
            "id": "add_2_personal_sources",
            "label": "Ajouter 2 sources personnelles",
            "help": "Un blog, une newsletter, un site que tu lis déjà.",
        },
        {
            "id": "first_perspectives_open",
            "label": "Lancer ta première analyse de comparaison",
            "help": "Compare deux angles sur le même sujet.",
        },
    ],
    "message": (
        "Bienvenue. Avant de t'emmener plus loin, posons les bases : "
        "ta ligne éditoriale, les sources que tu connais, et celles que "
        "tu veux ajouter à ta sélection."
    ),
    "signature": "Le Facteur",
}

LETTER_2: dict = {
    "id": "letter_2",
    "num": "02",
    "title": "Ton rythme idéal",
    "default_status": "upcoming",
    "actions": [
        {
            "id": "set_frequency",
            "label": "Choisir ta fréquence de digest",
            "help": "Quotidien, hebdomadaire, ou à la demande.",
        },
    ],
    "message": ("Maintenant que ta sélection est posée, choisissons ton rythme."),
    "signature": "Le Facteur",
}

LETTERS_ORDER: list[dict] = [LETTER_0, LETTER_1, LETTER_2]
LETTERS_BY_ID: dict[str, dict] = {letter["id"]: letter for letter in LETTERS_ORDER}
