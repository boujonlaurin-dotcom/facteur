class ScoringWeights:
    """
    Configuration centralisée des poids de l'algorithme de recommandation.
    Permet d'ajuster facilement l'équilibre entre Pertinence, Qualité et Habitudes.
    """
    
    # --- CORE LAYER (Pertinence & Habitudes) ---
    
    # Poids accordé à un contenu qui matche un intérêt déclaré de l'utilisateur.
    # C'est le moteur principal du feed.
    THEME_MATCH = 70.0  
    
    # Poids pour une source explicitement suivie par l'utilisateur.
    FOLLOWED_SOURCE = 30.0
    
    # Bonus pour une source non suivie mais "Standard" (vs suivie).
    STANDARD_SOURCE = 10.0
    
    # Base du score de fraîcheur (Recency).
    recency_base = 30.0
    
    
    # --- QUALITY LAYER (FQS - Facteur Quality Score) ---
    
    # Bonus léger pour les sources de haute qualité (FQS > 70).
    # Doit rester inférieur à un intérêt (50.0) pour ne pas polluer le feed.
    # Sert de "tie-breaker" ou de bonus de découverte.
    FQS_HIGH_BONUS = 15.0
    
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
