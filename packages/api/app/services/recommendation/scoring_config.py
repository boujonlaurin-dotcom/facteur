class ScoringWeights:
    """
    Configuration centralisée des poids de l'algorithme de recommandation.
    Permet d'ajuster facilement l'équilibre entre Pertinence, Qualité et Habitudes.
    """
    
    # --- CORE LAYER (Pertinence & Habitudes) ---
    
    # Poids accordé à un contenu qui matche un intérêt déclaré de l'utilisateur.
    # C'est le moteur principal du feed.
    THEME_MATCH = 70.0  
    
    # Poids pour une source de confiance (explicitement suivie par l'utilisateur).
    TRUSTED_SOURCE = 40.0
    
    # Bonus pour une source non suivie mais "Standard" (vs suivie).
    STANDARD_SOURCE = 10.0
    
    # Bonus pour une source ajoutée manuellement (Custom Source).
    # S'ajoute au bonus TRUSTED_SOURCE.
    CUSTOM_SOURCE_BONUS = 10.0
    
    # Base du score de fraîcheur (Recency).
    recency_base = 30.0
    
    # --- DIGEST RECENCY BONUSES (Tiered) ---
    # Bonus de fraîcheur hiérarchisés pour l'algorithme de digest
    # Permet d'ajuster les articles plus anciens des sources suivies
    
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
    # Doit rester inférieur aux sources de confiance (user-followed).
    CURATED_SOURCE = 10.0
    
    # Pénalité pour les sources de basse qualité/fiabilité.
    # Sert de filtre d'"hygiène".
    FQS_LOW_MALUS = -30.0
    
    
    # --- BEHAVIORAL LAYER (Engagement) ---
    
    # Multiplicateur appliqué au poids de l'intérêt si l'utilisateur consomme beaucoup ce thème.
    INTEREST_BOOST_FACTOR = 1.2

    # --- VISUAL LAYER (Attractivité) ---

    # Boost pour les contenus possédant une image de couverture.
    # Aide à rendre le feed plus engageant visuellement.
    IMAGE_BOOST = 10.0
    
    # --- ARTICLE TOPIC LAYER (Topics Granulaires) ---
    
    # Bonus par topic granulaire matchant entre content.topics et user_subtopics.
    # Score = TOPIC_MATCH * min(matches, TOPIC_MAX_MATCHES)
    TOPIC_MATCH = 60.0
    TOPIC_MAX_MATCHES = 2  # Max 120pts (2 x 60)
    
    # Bonus de précision : si article a match thème ET sous-thème
    # Récompense la granularité (ex: Tech + IA > Tech seul)
    SUBTOPIC_PRECISION_BONUS = 20.0
