class ScoringWeights:
    """
    Configuration centralisée des poids de l'algorithme de recommandation.
    Permet d'ajuster facilement l'équilibre entre Pertinence, Qualité et Habitudes.

    Rééquilibrage Phase 2 (diversité feed):
    - Spread réduit : ancien 70÷10=7x → nouveau 50÷15=3.3x
    - Les sources secondaires peuvent maintenant rivaliser avec les intérêts primaires
    """

    # --- CORE LAYER (Pertinence & Habitudes) ---

    # Poids accordé à un contenu qui matche un intérêt déclaré de l'utilisateur.
    # Réduit de 70→50 pour permettre aux topics de rivaliser.
    THEME_MATCH = 50.0

    # Facteur multiplicatif pour les thèmes secondaires d'une source.
    # Un match de thème secondaire rapporte THEME_MATCH * SECONDARY_THEME_FACTOR points.
    SECONDARY_THEME_FACTOR = 0.7

    # Poids pour une source de confiance (explicitement suivie par l'utilisateur).
    # Réduit de 40→35 pour ne pas dominer la pertinence thématique.
    TRUSTED_SOURCE = 35.0

    # Bonus pour une source non suivie mais "Standard" (vs suivie).
    # Augmenté de 10→15 pour encourager les sources secondaires.
    STANDARD_SOURCE = 15.0

    # Bonus pour une source ajoutée manuellement (Custom Source).
    # S'ajoute au bonus TRUSTED_SOURCE. Augmenté de 10→12.
    CUSTOM_SOURCE_BONUS = 12.0

    # Base du score de fraîcheur (Recency).
    recency_base = 30.0

    # --- DIGEST RECENCY BONUSES (Tiered) ---
    # Bonus de fraîcheur hiérarchisés pour l'algorithme de digest

    # Article très récent (< 6h): +30 pts
    RECENT_VERY_BONUS = 30.0

    # Article récent (< 24h): +25 pts
    RECENT_BONUS = 25.0

    # Publié aujourd'hui (< 48h): +15 pts
    RECENT_DAY_BONUS = 15.0

    # Publié hier (< 72h): +8 pts
    RECENT_YESTERDAY_BONUS = 8.0

    # Article de la semaine (< 120h): +3 pts
    RECENT_WEEK_BONUS = 3.0

    # Article ancien (< 168h): +1 pt
    RECENT_OLD_BONUS = 1.0


    # --- QUALITY LAYER (FQS - Facteur Quality Score) ---

    # Bonus léger pour les sources qualitatives (curées par Facteur).
    CURATED_SOURCE = 10.0

    # Pénalité pour les sources de basse qualité/fiabilité.
    # Adouci de -30→-20 pour permettre la récupération.
    FQS_LOW_MALUS = -20.0


    # --- BEHAVIORAL LAYER (Engagement) ---

    # Multiplicateur appliqué au poids de l'intérêt si l'utilisateur consomme beaucoup ce thème.
    # Réduit de 1.2→1.1 pour limiter le biais d'apprentissage.
    INTEREST_BOOST_FACTOR = 1.1

    # --- VISUAL LAYER (Attractivité) ---

    # Boost pour les contenus possédant une image de couverture.
    # Augmenté de 10→12 pour encourager le contenu visuel.
    IMAGE_BOOST = 12.0

    # --- ARTICLE TOPIC LAYER (Topics Granulaires) ---

    # Bonus par topic granulaire matchant entre content.topics et user_subtopics.
    # Réduit de 60→45 car content.theme capture déjà le signal broad.
    TOPIC_MATCH = 45.0
    TOPIC_MAX_MATCHES = 2  # Max 90pts (2 x 45)

    # Bonus de précision : si article a match thème ET sous-thème
    # Réduit de 20→18.
    SUBTOPIC_PRECISION_BONUS = 18.0

    # --- DIGEST DIVERSITY (Revue de presse) ---

    # Diviseur appliqué au score du 2ème article d'une même source dans le digest.
    # Effet : score ÷ 2 pour tout doublon de source.
    #
    # Rationale:
    # Les articles du top digest scorent entre 150 et 260 pts. Une pénalité fixe
    # (-10, -30) est insuffisante : un doublon à 220 pts resterait à 190+ pts,
    # bien au-dessus des articles alternatifs. Le ÷2 relègue ce doublon à 110 pts,
    # permettant aux articles d'autres sources (typiquement 140-180 pts) de prendre
    # la place. Cela crée l'effet "revue de presse" souhaité — pluralité des sources
    # plutôt que domination d'une seule.
    DIGEST_DIVERSITY_DIVISOR = 2

    # --- DIGEST TRENDING/IMPORTANCE (Pour vous hybride) ---

    # Bonus pour article trending (couvert par ≥3 sources distinctes).
    # Calibré pour rivaliser avec un article personnalisé moyen (~150 pts)
    # sans dominer un personnalisé fort (~250 pts).
    DIGEST_TRENDING_BONUS = 45.0

    # Bonus pour article provenant d'un feed "À la Une" (importance éditoriale).
    # Inférieur au trending car signal d'1 seule source vs cross-source.
    DIGEST_UNE_BONUS = 35.0

    # Fraction cible du digest réservée aux articles trending/importants.
    # 0.5 = ceil(7 * 0.5) = 4 slots max pour trending.
    DIGEST_TRENDING_TARGET_RATIO = 0.5

    # --- EXPLICIT FEEDBACK LAYER (Like & Bookmark signals) ---

    # Delta applied to user_subtopics.weight when liking/unliking content.
    LIKE_TOPIC_BOOST = 0.15

    # Delta applied to user_subtopics.weight when bookmarking content.
    BOOKMARK_TOPIC_BOOST = 0.05

    # Learning rate applied to UserInterest.weight on like/bookmark.
    LIKE_INTEREST_RATE = 0.03
