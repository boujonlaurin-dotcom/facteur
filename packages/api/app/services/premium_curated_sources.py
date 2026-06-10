"""Config curée des sources payantes (connexion WebView mobile).

Map en code plutôt qu'en base : la découvrabilité du CTA "Connecter mon
abonnement" ne dépend d'aucun id de source ni d'aucune migration Alembic
(conforme "exactement 1 head" / pas de SQL manuel via Supabase). On clé par
domaine eTLD+1, ce qui couvre toutes les sources d'un même média (sous-domaines
``www``/``m``/``abonnes`` inclus) sans connaître leur id.

Facteur ne collecte jamais d'identifiants : ces URLs ne servent qu'à charger la
page de connexion et une page de test dans la WebView de l'app, côté device.
"""

from urllib.parse import urlsplit

# Suffixes composés courants (eTLD à deux labels). On reste centré FR/EU : le
# fallback générique couvre tout le reste, donc cette liste n'a pas à être
# exhaustive.
_MULTI_PART_TLDS = frozenset(
    {"co.uk", "org.uk", "gov.uk", "ac.uk", "com.au", "co.jp", "co.nz"}
)


def domain_key(url: str | None) -> str:
    """Retourne l'eTLD+1 normalisé d'une URL (clé de ``PREMIUM_CURATED_MAP``).

    ``https://www.lemonde.fr/...`` → ``lemonde.fr`` ;
    ``https://abonnes.lefigaro.fr`` → ``lefigaro.fr``. Approximation FR-first
    (deux derniers labels), avec garde pour les quelques suffixes composés
    usuels. Renvoie ``""`` si l'URL est inexploitable.
    """
    if not isinstance(url, str):
        return ""
    raw = url.strip()
    if not raw:
        return ""
    # Autorise les hôtes nus ("lemonde.fr") en leur donnant un schéma fictif.
    if "//" not in raw:
        raw = "//" + raw
    host = (urlsplit(raw).hostname or "").lower().strip(".")
    if not host:
        return ""
    labels = host.split(".")
    if len(labels) <= 2:
        return host
    if ".".join(labels[-2:]) in _MULTI_PART_TLDS and len(labels) >= 3:
        return ".".join(labels[-3:])
    return ".".join(labels[-2:])


# Config curée : login_url = page de connexion du média ; test_url = page chargée
# pour vérifier que la session est active (idéalement un article abonné
# "evergreen", à défaut la home du média). display_hint = consigne affichée à
# l'utilisateur pendant la connexion. À enrichir éditorialement sans migration.
PREMIUM_CURATED_MAP: dict[str, dict] = {
    "lemonde.fr": {
        "login_url": "https://secure.lemonde.fr/sfuser/connexion",
        "test_url": "https://www.lemonde.fr/",
        "display_hint": "Connecte-toi à ton compte Le Monde, puis reviens lire tes articles.",
    },
    "mediapart.fr": {
        "login_url": "https://www.mediapart.fr/login",
        "test_url": "https://www.mediapart.fr/",
        "display_hint": "Connecte-toi à ton compte Mediapart pour lire les articles réservés.",
    },
    "lefigaro.fr": {
        "login_url": "https://plus.lefigaro.fr/account/login",
        "test_url": "https://www.lefigaro.fr/",
        "display_hint": "Connecte-toi à ton compte Figaro pour lire les articles abonnés.",
    },
    "lequipe.fr": {
        "login_url": "https://compte.lequipe.fr/",
        "test_url": "https://www.lequipe.fr/",
        "display_hint": "Connecte-toi à ton compte L'Équipe pour lire les articles abonnés.",
    },
    "liberation.fr": {
        "login_url": "https://www.liberation.fr/auth/login/",
        "test_url": "https://www.liberation.fr/",
        "display_hint": "Connecte-toi à ton compte Libération pour lire les articles abonnés.",
    },
    "lesechos.fr": {
        "login_url": "https://www.lesechos.fr/connexion",
        "test_url": "https://www.lesechos.fr/",
        "display_hint": "Connecte-toi à ton compte Les Échos pour lire les articles abonnés.",
    },
    "telerama.fr": {
        "login_url": "https://www.telerama.fr/connexion",
        "test_url": "https://www.telerama.fr/",
        "display_hint": "Connecte-toi à ton compte Télérama pour lire les articles abonnés.",
    },
}


def is_paywalled_source(source: object, *, curated_map: dict | None = None) -> bool:
    """Indique si une source est payante (signal ``has_paywall`` côté mobile).

    Vrai si l'un des deux signaux fiables est présent :
    - ``paywall_config`` renseigné (patterns de détection paywall) ;
    - domaine présent dans ``PREMIUM_CURATED_MAP``.

    On n'utilise **pas** ``source_tier`` (faux signal), ni la simple présence
    d'un ``premium_connection_config`` partiel (une config explicite valide est
    gérée en amont par ``PremiumConnectionResponse.from_source``).
    """
    if curated_map is None:
        curated_map = PREMIUM_CURATED_MAP

    if getattr(source, "paywall_config", None) is not None:
        return True

    domain = domain_key(getattr(source, "url", None))
    return bool(domain) and domain in curated_map
