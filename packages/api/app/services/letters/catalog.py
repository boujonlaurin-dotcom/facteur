"""Catalogue des lettres du Facteur (constantes serveur).

V2 = 5 lettres en dur. Rotation éditoriale = redeploy. Les lettres ne sont
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
            "target_route": "/flaner",
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
    "title": "Premières lectures",
    "default_status": "upcoming",
    "intro_palier": (
        "Ta sélection est posée. Voyons maintenant si tu sais en faire bon usage."
    ),
    "actions": [
        {
            "id": "read_first_essentiel",
            "label": "Lire Actu du jour",
            "help": "Cinq articles, choisis pour toi. C'est le rendez-vous quotidien.",
            "completion_palier": "Premier rendez-vous tenu. Ça commence ici.",
            "target_route": "/flux-continu/section/essentiel",
        },
        {
            "id": "read_first_bonnes_nouvelles",
            "label": "Découvrir Les bonnes nouvelles",
            "help": "Quand l'actu pèse, va voir ce qui s'allège.",
            "completion_palier": (
                "Tu sais maintenant que la lecture peut aussi faire du bien."
            ),
            "target_route": "/flux-continu/section/bonnes",
        },
        {
            "id": "read_3_long_articles",
            "label": "Lire 10 articles",
            "help": "Dix articles distincts avec un vrai signal de lecture.",
            "completion_palier": (
                "Dix articles parcourus. Tu prends maintenant le rythme."
            ),
            "target_route": "/flaner",
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
            "target_route": "/flaner",
        },
        {
            "id": "recommend_first_article",
            "label": "Recommander un article",
            "help": (
                "Un like (🌻), c'est un signal. Il oriente ta sélection et celle des autres."
            ),
            "completion_palier": "Un signal envoyé. Le Facteur écoute.",
            "target_route": "/flaner",
        },
    ],
    "message": (
        "Ta sélection est prête. Faisons connaissance avec ce qu'elle "
        "peut t'apporter au quotidien.\n\n"
        "Cinq gestes simples pour entrer dans le rythme."
    ),
    "signature": "Le Facteur",
    "completion_voeu": (
        "Tu as appris à lire avec attention. C'est déjà beaucoup. La suite peut attendre."
    ),
}

LETTER_3: dict = {
    "id": "letter_3",
    "num": "03",
    "title": "Ta tournée s'organise",
    "default_status": "upcoming",
    "intro_palier": (
        "Tu sais lire. Maintenant, apprends à trier : ce que tu gardes, "
        "ce que tu annotes, ce que tu écartes."
    ),
    "actions": [
        {
            "id": "create_first_veille",
            "label": "Créer ta première veille",
            "help": (
                "Choisis un sujet qui compte pour toi. Le Facteur surveillera "
                "pour toi, jour après jour."
            ),
            "completion_palier": (
                "Une veille posée. Le Facteur garde un œil dessus pour toi."
            ),
            "target_route": "/veille/config",
        },
        {
            "id": "save_5_articles",
            "label": "Enregistrer 5 articles",
            "help": (
                "Appuie sur le marque-page d'un article pour le mettre de côté. "
                "Cinq articles, et ton fonds prend forme."
            ),
            "completion_palier": (
                "Cinq articles au chaud. Tu te constitues une vraie réserve."
            ),
            "target_route": "/flaner",
        },
        {
            "id": "write_first_note",
            "label": "Écrire une note sur un article sauvegardé",
            "help": (
                "Ouvre un article sauvegardé, appuie sur le marque-page et "
                "ajoute une note : une idée, une citation, un pourquoi."
            ),
            "completion_palier": (
                "Première note posée. Lire, c'est bien ; garder une trace, "
                "c'est mieux."
            ),
            "target_route": "/saved",
        },
        {
            "id": "mute_3_sources",
            "label": "Masquer 3 sources qui ne te plaisent pas",
            "help": (
                "Depuis un article, ouvre le menu et choisis « Masquer la "
                "source ». Écarter, c'est aussi choisir."
            ),
            "completion_palier": (
                "Trois sources écartées. Ta sélection gagne en caractère."
            ),
            "target_route": "/flaner",
        },
        {
            "id": "add_5_youtube_channels",
            "label": "Ajouter 5 chaînes YouTube",
            "help": (
                "Colle le lien d'une chaîne que tu suis déjà. Tes vidéos "
                "rejoignent ta tournée."
            ),
            "completion_palier": (
                "Cinq chaînes dans la tournée. Ta sélection ne se limite "
                "plus au texte."
            ),
            "target_route": "/settings/sources/add",
        },
    ],
    "message": (
        "Tu lis, et tu lis bien. L'étape suivante, c'est d'organiser ta "
        "tournée : garder ce qui compte, annoter ce qui t'a marqué, "
        "écarter ce qui t'encombre.\n\n"
        "Cinq gestes de tri. C'est là que ta sélection devient la tienne."
    ),
    "signature": "Le Facteur",
    "completion_voeu": (
        "Ta tournée est rangée à ta façon. Peu de lecteurs vont jusque-là."
    ),
}

LETTER_4: dict = {
    "id": "letter_4",
    "num": "04",
    "title": "Facteur de fond",
    "default_status": "upcoming",
    "intro_palier": (
        "Dernière lettre. Ici, on ne compte plus les gestes : on mesure "
        "l'endurance."
    ),
    "actions": [
        {
            "id": "read_50_articles",
            "label": "Lire 50 articles",
            "help": (
                "Cinquante articles, à ton rythme. La régularité fait le "
                "reste."
            ),
            "completion_palier": (
                "Cinquante lectures. Tu n'es plus un visiteur, tu es un "
                "habitué."
            ),
            "target_route": "/flaner",
        },
        {
            "id": "recommend_10_articles",
            "label": "Recommander 10 articles",
            "help": (
                "Le tournesol sous un article, c'est ta voix. Dix signaux, "
                "et ta sélection te ressemble vraiment."
            ),
            "completion_palier": (
                "Dix recommandations. Le Facteur connaît tes goûts par cœur."
            ),
            "target_route": "/flaner",
        },
        {
            "id": "open_10_perspectives",
            "label": "Comparer 10 couvertures médiatiques",
            "help": (
                "Sur un sujet chaud, ouvre les perspectives pour confronter "
                "les angles. Dix comparaisons aiguisent le regard."
            ),
            "completion_palier": (
                "Dix sujets vus sous plusieurs angles. Le doute méthodique "
                "te va bien."
            ),
            "target_route": "/flaner",
        },
        {
            "id": "give_app_feedback",
            "label": "Donner ton avis sur l'app",
            "help": (
                "Dans les réglages, appuie sur « Donner mon avis ». Ce que "
                "tu penses de Facteur aide à le construire."
            ),
            "completion_palier": (
                "Avis transmis. Facteur se construit aussi avec toi."
            ),
            "target_route": "/settings",
        },
    ],
    "message": (
        "Te voilà au dernier palier. Plus rien à t'apprendre sur les "
        "gestes : il reste la profondeur, la constance, et un avis qui "
        "compte, le tien.\n\n"
        "Prends ton temps. Cette lettre se mérite."
    ),
    "signature": "Le Facteur",
    "completion_voeu": (
        "Tu as tout vu, tout lu, tout trié. La tournée est à toi maintenant."
    ),
}

LETTERS_ORDER: list[dict] = [LETTER_0, LETTER_1, LETTER_2, LETTER_3, LETTER_4]
LETTERS_BY_ID: dict[str, dict] = {letter["id"]: letter for letter in LETTERS_ORDER}
