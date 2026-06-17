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

    # Bonus additionnel appliqué *uniquement dans le digest* (Essentiel +
    # Bonnes Nouvelles) en plus de TRUSTED_SOURCE. Le pool digest inclut déjà
    # les sources suivies en étape 1, mais le ranking + la diversité (1
    # article/source) les évinçaient souvent ; ce bonus garantit qu'un
    # article de source suivie passe devant un curated comparable, sans
    # écraser un curated nettement plus pertinent (trending fort, etc.).
    DIGEST_TRUSTED_SOURCE_BONUS = 60.0

    # Bonus pour une source non suivie mais "Standard" (vs suivie).
    # Augmenté de 10→15 pour encourager les sources secondaires.
    STANDARD_SOURCE = 15.0

    # Bonus pour une source ajoutée manuellement (Custom Source).
    # S'ajoute au bonus TRUSTED_SOURCE. Augmenté de 10→12.
    CUSTOM_SOURCE_BONUS = 12.0

    # Bonus pour une source à laquelle l'utilisateur est abonné (Premium).
    # S'ajoute au bonus TRUSTED_SOURCE. Débloque aussi les articles payants.
    SUBSCRIPTION_BONUS = 20.0

    # Base du score de fraîcheur (Recency).
    # Epic 11: raised from 30→100 so fresh articles compete with personalization.
    recency_base = 100.0

    # --- CUSTOM TOPIC LAYER (Epic 11) ---

    # Base bonus when an article matches a user's custom topic.
    # Top3 thematic selection: bumped 15→25 (B3) — un sujet perso précis est
    # le signal d'intention le plus fort dont on dispose, il doit pouvoir
    # peser autant qu'un TRUSTED_SOURCE (35) à multiplier max 2.0.
    CUSTOM_TOPIC_BASE_BONUS = 25.0

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

    # --- THEMATIC SECTION ADAPTIVE FRESHNESS WINDOW (rareté de contenu) ---
    # Sections thématiques de la Tournée (personalized_theme_mode) : la fenêtre
    # 24h + sources-suivies-seulement peut rendre une section quasi vide pour les
    # thèmes à faible fréquence (ex. science = 4 candidats/24h). On élargit la
    # fenêtre par paliers UNIQUEMENT quand le pool 24h est sous le seuil ; le
    # scoring Fraîcheur continue de privilégier « le plus frais d'abord ».
    THEMATIC_WINDOW_TIERS_HOURS = (24, 48, 72)  # paliers d'élargissement successifs
    THEMATIC_MIN_POOL_SIZE = 8  # sous ce seuil → on tente le palier suivant
    # Plancher absolu de candidats par section thématique. Si le pool des sources
    # suivies reste en dessous (même au palier 72h), on complète avec des sources
    # curées NON-suivies (comme Flâner), marquées « Suivre + » à l'affichage. Le
    # deep-dive (carrousels / Explorer plus / CTA Sujet suivant) reste toujours
    # accessible.
    THEMATIC_HARD_FLOOR = 5

    # Repli « pas d'article récent » pour les sections **source** : si aucune
    # source n'a publié dans la fenêtre adaptative (≤72h), on élargit jusqu'à
    # 30 j (720h) pour afficher des articles plus anciens plutôt qu'un
    # empty-state. Le client est notifié via `no_recent_source` (banner =
    # « Pas d'article récent. »).
    SOURCE_STALE_FALLBACK_HOURS = 720  # 30 j — repli « pas d'article récent » (source)

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

    # --- CONTENT QUALITY LAYER (Lecture in-app) ---

    # Boost pour les articles avec contenu riche (>500 chars texte brut).
    # Favorise les articles lisibles dans le reader natif Facteur.
    CONTENT_QUALITY_FULL_BOOST = 10.0

    # Boost réduit pour les articles avec contenu partiel (100-500 chars).
    CONTENT_QUALITY_PARTIAL_BOOST = 5.0

    # --- ARTICLE TOPIC LAYER (Topics Granulaires) ---

    # Bonus par topic granulaire matchant entre content.topics et user_subtopics.
    # Réduit de 60→45 car content.theme capture déjà le signal broad.
    TOPIC_MATCH = 45.0
    TOPIC_MAX_MATCHES = 2  # Max 90pts (2 x 45)
    SUBTOPIC_POSITION_FACTOR = 0.6
    SUBTOPIC_DECAY = 0.98

    # Bonus de précision : si article a match thème ET sous-thème
    # Réduit de 20→18.
    SUBTOPIC_PRECISION_BONUS = 18.0

    # Malus léger appliqué quand l'article ne matche aucun thème ni sous-thème
    # suivi par l'utilisateur (et que l'user a déclaré des thèmes/sous-thèmes).
    # Calibré à ~16% du bonus THEME_MATCH : assez pour désavantager sans exclure.
    # Ne s'applique pas en cold start (aucun thème/sous-thème suivi).
    THEME_MISMATCH_MALUS = -8.0

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

    # --- DIGEST LOW-PRIORITY (Sport) ---

    # Pénalité appliquée aux articles Sport dans le scoring du digest (2 modes).
    # Renforcée de -40 → -80 (Story 9.4) : la pénalité d'origine était trop
    # faible — un sport avec source suivie (+100) ou trending (+45) la battait
    # systématiquement, d'où plusieurs cas observés en rank 1-3 (UNFP Dembélé,
    # Wembanyama, F1, Ligue des champions). À -80 le sport ne passe en tête
    # que s'il est éditorialement majeur ET suivi par l'user.
    DIGEST_SPORT_PENALTY = -80.0

    # --- ESSENTIEL (top 5 transversal — Story 9.4) ---

    # Slot minimum autorisé pour un article sport dans l'Essentiel (1-indexed).
    # Sport en rank < 5 = exclu via post-processing positionnel.
    ESSENTIEL_SPORT_MIN_SLOT = 5

    # Nombre maximum d'articles sport par Essentiel (5 articles total).
    ESSENTIEL_MAX_SPORT_PER_DIGEST = 1

    # Score perspectives non-linéaire (log2) : `min(CAP, BASE * log2(n))`.
    # 1→0  2→+12  3→+19  4→+24  5→+28  6→+30 (cap)  8+→+30
    # Permet à un sujet relayé par 3+ médias de rivaliser avec un BOOST_BADGE_ACTU
    # (+25) et d'égaler un BOOST_UNE (+30). Un scoop isolé n'a aucun bonus.
    # Source de vérité unique partagée par Essentiel, feed thématique et digest
    # via `helpers/coverage_score.py`.
    COVERAGE_BASE = 12.0
    COVERAGE_CAP = 30.0
    # Anciens noms maintenus pour rétrocompat (essentiel_service avant migration).
    ESSENTIEL_PERSPECTIVE_BASE = COVERAGE_BASE
    ESSENTIEL_PERSPECTIVE_CAP = COVERAGE_CAP

    # --- DIGEST POLARISATION (importance éditoriale — Actus du jour) ---
    # Bonus d'importance pour un sujet où les médias divergent (gauche ET
    # droite représentées). Signal tertiaire derrière couverture (cap 30) et
    # récence (max 30) : il départage les sujets très couverts du jour sans
    # jamais dominer la couverture. `divergence_level` "low"/"none" = 0 (pas
    # de polarisation notable). Cf. bug-actus-du-jour-ranking.md (Partie C).
    POLARIZATION_MEDIUM_BONUS = 6.0
    POLARIZATION_HIGH_BONUS = 12.0

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

    # --- TOPIC SELECTION (Sujets du jour — Epic 10 refonte) ---

    # Bonus pour un topic contenant ≥1 article d'une source suivie par l'user.
    TOPIC_FOLLOWED_SOURCE_BONUS = 40.0

    # Bonus pour un topic trending (couvert par ≥3 sources distinctes).
    # Source de vérité partagée avec Essentiel et feed thématique.
    TOPIC_TRENDING_BONUS = 50.0
    TOPIC_IS_TRENDING_BONUS = TOPIC_TRENDING_BONUS  # alias canonique

    # Bonus pour un topic contenant ≥1 article "À la Une".
    TOPIC_UNE_BONUS = 35.0
    TOPIC_IS_UNE_BONUS = TOPIC_UNE_BONUS  # alias canonique

    # Bonus pour un topic dont le thème dominant matche les intérêts user.
    TOPIC_THEME_MATCH_BONUS = 45.0

    # Garde-fou anti-niche : minimum de topics trending/une dans le digest.
    TOPIC_MIN_TRENDING = 1

    # Nombre maximum d'articles par topic group.
    TOPIC_MAX_ARTICLES = 3

    # Seuil Jaccard pour le clustering universel.
    # 0.45 = articles doivent partager ~45% de tokens pour être groupés.
    # Plus strict que trending (0.4) pour éviter les faux clusters.
    TOPIC_CLUSTER_THRESHOLD = 0.45

    # Minimum de tokens pour qu'un article soit candidat au clustering.
    # Articles avec < 3 tokens après filtrage deviennent des singletons.
    TOPIC_CLUSTER_MIN_TOKENS = 3

    # Maximum de tokens par cluster (évite la dérive par union successive).
    TOPIC_CLUSTER_MAX_TOKENS = 15

    # --- EXPLICIT FEEDBACK LAYER (Like & Bookmark signals) ---

    # Delta applied to user_subtopics.weight when liking/unliking content.
    LIKE_TOPIC_BOOST = 0.15

    # Delta applied to user_subtopics.weight when bookmarking content.
    BOOKMARK_TOPIC_BOOST = 0.05

    # Delta applied to user_subtopics.weight when consuming (reading) content.
    # Weakest signal (implicit) — accumulates over many reads.
    READ_TOPIC_BOOST = 0.03

    # Delta applied to user_subtopics.weight when dismissing (swipe-left) content.
    # ~1 dismissal cancels 1 like. Symmetric signal.
    DISMISS_TOPIC_PENALTY = -0.15

    # Learning rate applied to UserInterest.weight on like/bookmark.
    LIKE_INTEREST_RATE = 0.03

    # --- IMPRESSION LAYER (Feed Refresh) ---
    # Malus temporel par tiers : plus l'article a été affiché récemment, plus le malus est fort.
    # Après 72h, le malus disparaît totalement (l'utilisateur a oublié l'article).

    IMPRESSION_VERY_RECENT = -100.0  # < 1h  — invisible après refresh
    IMPRESSION_RECENT = -70.0  # < 24h — très peu de chances de remonter
    IMPRESSION_DAY = -40.0  # < 48h — remonte si très pertinent
    IMPRESSION_OLD = -20.0  # < 72h — léger handicap
    # > 72h : 0 pts (entièrement récupéré)

    IMPRESSION_MANUAL = -120.0  # "J'ai déjà vu" — malus permanent, pas de decay

    # Fenêtre pendant laquelle un article récemment impressionné est exclu du
    # feed chronologique par défaut (pull-to-refresh). Aligné sur le tier
    # IMPRESSION_VERY_RECENT (<1h = "invisible après refresh").
    IMPRESSION_HIDE_WINDOW_HOURS = 1

    # --- SOURCE AFFINITY (Learned from interactions) ---

    # Maximum bonus for a source with highest engagement.
    # Calibré pour être significatif mais pas dominant vs theme match (50 pts).
    SOURCE_AFFINITY_MAX_BONUS = 25.0

    # --- PILLAR SCORING (v2 Architecture) ---

    # Poids relatifs des piliers (doivent sommer à 1.0).
    PILLAR_WEIGHTS = {
        "pertinence": 0.40,
        "source": 0.25,
        "fraicheur": 0.20,
        "qualite": 0.15,
    }

    # Expected max raw scores per pillar (for 0-100 normalization).
    # Tuned from observed score distributions.
    MAX_PERTINENCE_RAW = 130.0  # theme(50) + 2 subtopics(90) + precision(18) - overlap
    MAX_SOURCE_RAW = (
        95.0  # trusted(35) + custom(12) + subscription(20) + affinity(25) + curated(10)
    )
    MAX_FRAICHEUR_RAW = 115.0  # recency_base(100) + recency_pref(15)
    MAX_QUALITE_RAW = 32.0  # thumbnail(12) + full_text(10) + curated(10)

    # Randomization temperatures (Gumbel noise).
    # 0.0 = deterministic, 0.15 = moderate discovery, 0.3 = high discovery.
    FEED_RANDOMIZATION_TEMPERATURE = 0.15
    DIGEST_RANDOMIZATION_TEMPERATURE = 0.08

    # Scoring engine version: "layers_v1" (legacy) or "pillars_v1" (new).
    SCORING_VERSION = "pillars_v1"

    # --- VEILLE (feed temps-réel curé par score) ---

    # Bonus mots-clés **escaladant** (Story 23.4) : un angle dont N mots-clés
    # distincts matchent (titre/description) rapporte
    # `min(BASE + INCREMENT*(N-1), CAP)`. Remplace l'ancien `+25` plat de
    # `_score_custom_topics` quand l'angle est marqué `is_veille`. Le cap (45)
    # protège `MAX_PERTINENCE_RAW=130` d'un empilement non borné.
    VEILLE_KEYWORD_BASE_BONUS = 18.0
    VEILLE_KEYWORD_INCREMENT = 9.0
    VEILLE_KEYWORD_CAP = 45.0

    # Bonus quand l'article porte le `topic_id` de l'angle dans `Content.topics`
    # (« article labellisé IA ») — le signal canonique le plus fort.
    VEILLE_TOPIC_MATCH_BONUS = 50.0

    # Bonus de combo : topic canonique **ET** ≥1 mot-clé matché (signal on-angle
    # le plus net).
    VEILLE_TOPIC_KEYWORD_COMBO_BONUS = 15.0

    # Bonus source suivie appliqué **dans la pertinence** uniquement si l'article
    # a déjà un topic ou un mot-clé (bonus angle > 0). « La source est un boost,
    # pas un free-pass » : source-seul = 0 contribution de pertinence.
    VEILLE_SOURCE_ON_TOPIC_BONUS = 12.0

    # Seuil de pertinence (score final piliers, échelle ~0-100) en-deçà duquel
    # un article candidat est élagué du feed veille. Relevé 40→48 (Story 23.4)
    # avec la curation v2 : source-seul frais+riche ≈ 44 (< 48, écarté en plus
    # par le floor) ; 1 mot-clé+source ≈ 52-58 ; topic+source ≈ 62-70 ;
    # topic+2kw+source ≈ 75-82. Point de calibration tunable via les logs prod
    # (max_score / pass_count / floor_pruned_count / threshold_pruned_count).
    VEILLE_RELEVANCE_THRESHOLD = 48.0

    # Anti-starvation : si après scoring moins de N articles passent ET que des
    # candidats on-axis ont été coupés par le *seuil* (jamais par le floor), on
    # relâche le seuil d'un cran (max -8, plancher 40).
    VEILLE_MIN_FEED_SIZE = 5

    # Plafond du pool de candidats scorés par fetch (borne le coût ILIKE +
    # scoring sur un feed curé ; offsets au-delà renvoient vide — acceptable).
    VEILLE_CANDIDATE_CAP = 300

    # Fenêtre de récence (heures) du prédicat veille — aligné sur le digest.
    # S'applique au **Bloc B « Couverture élargie »** (topics/mots-clés, sources
    # non configurées).
    VEILLE_RECENCY_HOURS = 168

    # Fenêtre de récence (heures) du **Bloc A « Tes sources »** : 30 j. Les
    # sources niche configurées ont souvent des flux RSS lents/peu fréquents —
    # une fenêtre 7 j les rend invisibles alors qu'elles sont le cœur de la
    # veille. On élargit donc à 30 j *uniquement* pour les sources explicitement
    # ajoutées (laisser-passer), bornées par le cap de diversité ci-dessous.
    VEILLE_CONFIGURED_RECENCY_HOURS = 720

    # Cap de diversité du Bloc A : au plus N articles par source configurée, afin
    # qu'une source bavarde (flux dense) ne monopolise pas le bloc malgré la
    # fenêtre 30 j. Appliqué via `diversify()` après tri par score.
    VEILLE_SOURCE_DIVERSITY_CAP = 3

    # --- TOPIC-AWARE FEED DIVERSIFICATION (Phase 2 — Budget Neutre) ---

    # Floor ratio: minimum fraction of neutral articles kept visible (discovery).
    DISCOVERY_FLOOR_RATIO = 0.30

    # Subtopic weight threshold to consider a subtopic as "followed" (implicit).
    FOLLOWED_SUBTOPIC_THRESHOLD = 1.5

    # Minimum articles in a neutral group to justify a CTA chip.
    MIN_FOR_TOPIC_GROUPING = 8

    # Minimum articles sharing a broad theme to justify a theme CTA chip.
    MIN_FOR_THEME_GROUPING = 10

    # --- KEYWORD REGROUPEMENT (Feed Grouping Rework) ---

    # Minimum articles sharing a keyword to form a keyword CTA group.
    MIN_FOR_KEYWORD_GROUPING = 5

    # Minimum character length for a keyword to be considered.
    KEYWORD_MIN_LENGTH = 4

    # Maximum total CTA groups (entity + keyword + topic) per feed page.
    MAX_TOTAL_CTAS = 7

    # --- ENTITY REGROUPEMENT ---

    # Minimum articles sharing an entity to form an entity CTA group.
    MIN_FOR_ENTITY_GROUPING = 5

    # --- TOURNÉE SMART ARRANGEMENT (Story 22.3 — « Choisie pour vous ») ---
    # Arrangement quotidien intelligent par-dessus la config déclarée : les
    # sections « Choisie pour vous » remplissent les slots restants de la Tournée
    # avec des thèmes/sources suivis-mais-non-épinglés (jamais hors préférences).
    # Curseur « Fidèle » : majoritairement préférences réelles, la « surprise » =
    # variation quotidienne (seed daily + Gumbel basse température), pas découverte.

    # Poids du blend `daily_score` (0–1). Doivent sommer à 1.0.
    #   explicit : 1.0 si le candidat est directement suivi / déclaré à l'onboarding.
    #   measured : poids interest/subtopic appris + affinité source (0–1).
    #   quantity : log-saturé sur le nb d'articles récents (rareté → moins).
    #   quality  : moyenne reliability des sources du thème (signal qualité).
    TOURNEE_SUGGEST_W_EXPLICIT = 0.40
    TOURNEE_SUGGEST_W_MEASURED = 0.30
    TOURNEE_SUGGEST_W_QUANTITY = 0.20
    TOURNEE_SUGGEST_W_QUALITY = 0.10

    # Composante `explicit` d'un candidat issu de l'élargissement doux (source
    # on-thème non directement suivie) : plus faible qu'un suivi direct (1.0).
    TOURNEE_SUGGEST_SOFT_EXPLICIT = 0.5

    # Plancher de contenu : un candidat avec moins de N articles récents (14 j)
    # est écarté (jour pauvre → moins de suggestions, jamais d'empty-state suggéré).
    TOURNEE_SUGGEST_CONTENT_FLOOR = 3

    # Saturation log de la composante `quantity` : au-delà, le nb d'articles
    # n'augmente plus le score (évite qu'un thème bavard domine).
    TOURNEE_SUGGEST_QUANTITY_SATURATION = 60.0

    # Température Gumbel de la variation quotidienne (basse : ordre stable le
    # jour, varié le lendemain, sans réordonner brutalement).
    TOURNEE_SUGGEST_TEMPERATURE = 0.10

    # Plafond de sections « Choisie pour vous » (thèmes + sources confondus).
    TOURNEE_SUGGEST_SUBCAP = 4

    # Fenêtre de récence (jours) du comptage d'articles par candidat (aligné
    # sur le filtre 14 j du fallback `get_top_themes`).
    TOURNEE_SUGGEST_RECENCY_DAYS = 14
