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
            "target_route": "/settings/interests",
        },
        {
            "id": "add_5_sources",
            "label": "Ajouter 5 sources à ta sélection",
            "help": (
                "Pioche dans la liste suggérée. Tu peux toujours en retirer plus tard."
            ),
            "target_route": "/settings/sources",
        },
        {
            "id": "add_2_personal_sources",
            "label": "Ajouter 2 sources personnelles",
            "help": "Un blog, une newsletter, un site que tu lis déjà.",
            "target_route": "/settings/sources/add",
        },
        {
            "id": "first_perspectives_open",
            "label": "Lancer ta première analyse de comparaison",
            "help": "Compare deux angles sur le même sujet.",
            "target_route": "/feed",
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
    "title": "Tes premières lectures",
    "default_status": "upcoming",
    "intro_palier": (
        "Ta sélection est posée. Voyons maintenant si tu sais en faire bon usage."
    ),
    "actions": [
        {
            "id": "read_first_essentiel",
            "label": "Lire L'essentiel du jour",
            "help": "Cinq articles, choisis pour toi. C'est le rendez-vous quotidien.",
            "completion_palier": "Premier rendez-vous tenu. Ça commence ici.",
            "target_route": "/digest",
        },
        {
            "id": "read_first_bonnes_nouvelles",
            "label": "Découvrir Les bonnes nouvelles",
            "help": "Quand l'actu pèse, va voir ce qui s'allège.",
            "completion_palier": (
                "Tu sais maintenant que la lecture peut aussi faire du bien."
            ),
            "target_route": "/digest?serein=1",
        },
        {
            "id": "read_3_long_articles",
            "label": "Lire 10 articles",
            "help": "Dix articles distincts avec un vrai signal de lecture.",
            "completion_palier": (
                "Dix articles parcourus. Tu prends maintenant le rythme."
            ),
            "target_route": "/feed",
        },
        {
            "id": "read_first_video_podcast",
            "label": "Sauvegarder 3 articles dans vos collections",
            "help": (
                "Ajoute trois articles distincts dans tes collections, y compris "
                "la collection par défaut."
            ),
            "completion_palier": (
                "Trois articles mis de côté. Tu commences à te constituer un fonds."
            ),
            "target_route": "/feed",
        },
        {
            "id": "recommend_first_article",
            "label": "Recommander un article",
            "help": (
                "Un like (🌻), c'est un signal. Il oriente ta sélection et celle des autres."
            ),
            "completion_palier": "Un signal envoyé. Le Facteur écoute.",
            "target_route": "/feed",
        },
    ],
    "message": (
        "Ta sélection est prête. Maintenant, faisons connaissance avec ce qu'elle "
        "peut t'apporter au quotidien.\n\n"
        "Pas de course à la lecture, pas de chiffres à atteindre — "
        "juste cinq gestes simples pour entrer dans le rythme."
    ),
    "signature": "Le Facteur",
    "completion_voeu": (
        "Tu as appris à lire avec attention. C'est déjà beaucoup. La suite peut attendre."
    ),
}

LETTERS_ORDER: list[dict] = [LETTER_0, LETTER_1, LETTER_2]
LETTERS_BY_ID: dict[str, dict] = {letter["id"]: letter for letter in LETTERS_ORDER}
