class OnboardingStrings {
  // Common
  static const String continueButton = 'Continuer';
  static const String nextButton = 'Suivant';
  static const String skipButton = 'Passer cette étape';
  static const String backButtonTooltip = 'Retour';

  // Section Labels
  static const String section1Label = 'Overview';
  static const String section2Label = 'App Preferences';
  static const String section3Label = 'Source Preferences';

  static String sectionCount(int current, int total) =>
      'Section $current/$total';

  // Welcome Screen (ex-Intro 1)
  static const String welcomeTitle = 'Bienvenue sur Facteur !';
  static const String welcomeSubtitle =
      "L'information devrait t'aider à comprendre le monde.\n\nPas nous submerger.";
  static const String welcomeManifestoButton = 'Lire notre Manifeste';
  static const String welcomeStartButton = 'Commencer';

  // Intro Screen 2
  static const String intro2Title = 'Ton hub d\'infos fiables.';
  static const String intro2Subtitle =
      'Facteur est une app Open-Source pour retrouver le plaisir de s\'informer.\n\nUn espace de confiance, qui mêle transparence, contrôle et médias de qualité.';
  static const String intro2SubtitlePart1 = 'Facteur est une app Open-Source pour ';
  static const String intro2SubtitleBold1 = 'retrouver le plaisir de s\'informer';
  static const String intro2SubtitlePart2 = '. Un espace de ';
  static const String intro2SubtitleBold2 = 'confiance';
  static const String intro2SubtitlePart3 = ', qui mêle ';
  static const String intro2SubtitleBold3 = 'transparence';
  static const String intro2SubtitlePart4 = ', ';
  static const String intro2SubtitleBold4 = 'contrôle';
  static const String intro2SubtitlePart5 = ' et ';
  static const String intro2SubtitleBold5 = 'médias de qualité';
  static const String intro2SubtitlePart6 = '.';
  static const String intro2Button = 'Découvrir Facteur';

  // Media Concentration
  static const String mediaConcentrationTitle =
      'Sais-tu qui possède tes médias ?';
  static const String mediaConcentrationText =
      'Cette carte reflète la concentration des médias en France. \n\nFacteur t\'aide à comprendre comment se positionnent les médias pour mieux diversifier tes médias.';
  static const String mediaConcentrationTextPart1 =
      'Cette carte reflète la concentration des médias en France.\nFacteur t\'aide à comprendre comment se positionnent les médias pour mieux ';
  static const String mediaConcentrationTextBold1 = 'diversifier tes médias';
  static const String mediaConcentrationTextPart2 = '.';
  static const String mediaConcentrationButton = 'Continuer';

  // Q1: Objective (multi-select)
  static const String q1Title =
      "Commençons par toi. \n\nQu'est-ce qui t'épuise le plus avec l'info ?";
  static const String q1Subtitle = '';
  static const String q1NoiseLabel = 'Le Bruit';
  static const String q1NoiseSubtitle = "Trop d'info. Impossible de bien trier";
  static const String q1BiasLabel = 'Les Biais';
  static const String q1BiasSubtitle = 'Je doute constamment de la neutralité';
  static const String q1AnxietyLabel = 'La négativité';
  static const String q1AnxietySubtitle =
      'Le sentiment que le monde devient fou';

  // Q2: Age
  static const String q2Title = 'Apprenons à se connaitre';
  static const String q2Subtitle = 'Où est-ce que tu te situes ?';
  static const String q2Option18_24 = '18 - 24 ans';
  static const String q2Option25_34 = '25 - 34 ans';
  static const String q2Option35_44 = '35 - 44 ans';
  static const String q2Option45_plus = '45 ans et plus';

  // Q4: Approach → axe "Profondeur" (ré-aiguillé v6).
  // Cible la profondeur des SOURCES, pas seulement la longueur d'un article.
  // Valeurs inchangées : direct / detailed.
  static const String q4Title = 'Tu préfères des médias qui...';
  static const String q4Subtitle = '';
  static const String q4DirectLabel = 'Vont à l\'essentiel';
  static const String q4DirectSubtitle = 'L\'actu, claire et rapide';
  static const String q4DetailedLabel = 'Creusent le sujet';
  static const String q4DetailedSubtitle = 'Analyses et enquêtes de fond';

  // Q5b: Indépendance (nouvelle question v6). Cadrée comme un GOÛT de sourcing,
  // pas un jugement de fiabilité. Valeurs : established / independent.
  static const String qIndependenceTitle = 'Côté médias, tu penches pour...';
  static const String qIndependenceSubtitle = '';
  static const String qIndependenceEstablishedLabel =
      'Les grands médias institutionnels';
  static const String qIndependenceEstablishedSubtitle =
      'Installés, connus de tous';
  static const String qIndependenceIndependentLabel =
      'Des médias plus spécialisés';
  static const String qIndependenceIndependentSubtitle =
      'Moins connus, souvent indépendants';

  // Q5: Perspective
  static const String q5Title = 'Tu préfères avoir...';
  static const String q5Subtitle = '';
  static const String q5BigPictureLabel = 'La vue d\'ensemble';
  static const String q5BigPictureSubtitle = 'Comprendre les grandes lignes';
  static const String q5DetailsLabel = 'Dans le détail';
  static const String q5DetailsSubtitle = 'Aller en profondeur';

  // Swipe désambiguateur (Q9c bis, v6) : quelques sources étalées sur les axes
  // (profondeur, indépendance, perspective) que l'utilisateur trie d'un geste.
  // Glisser à droite = ça m'intéresse ; gauche = pas pour moi. (Le titre statique
  // a été remplacé par des en-têtes dynamiques par groupe, cf. swipeGroup*.)
  static const String swipeSubtitle =
      'Glisse à droite ceux qui te parlent, à gauche les autres. '
      'On ajuste tes suggestions en direct.';
  static const String swipeLikeHint = 'Ça m\'intéresse';
  static const String swipeSkipHint = 'Pas pour moi';
  static const String swipeUndoLabel = 'Revenir au dernier média';
  static const String swipeDoneButton = 'Voir mes médias';
  // Compteur humanisé à 3 paliers selon l'avancement (current/total). Plus
  // présent qu'un sec « Carte X sur Y », sans em-dash (règle PO).
  static const String swipeProgressStart = 'Premières cartes (%d/%d)';
  static const String swipeProgressMiddle = 'On affine (%d/%d)';
  static const String swipeProgressEnd = 'Encore quelques-unes (%d/%d)';
  // Nudge discret sur la 1ère carte (disparaît au 1er geste).
  static const String swipeTapHint = 'Touche pour ouvrir le média';

  // En-têtes dynamiques par groupe de cartes (mix type + thème). Le libellé
  // affiché suit le groupe de la carte du dessus et change d'un bloc à l'autre.
  // Tournure douce/humaine, sans em-dash (règle PO). « %s » = libellé de thème.
  static const String swipeGroupThemedDeep = 'Pour creuser %s…';
  static const String swipeGroupThemedDefault = 'Un peu de %s…';
  static const String swipeGroupDeep = 'Pour aller au fond…';
  static const String swipeGroupIndependent = 'Des médias indépendants';
  static const String swipeGroupEstablished = 'Quelques médias traditionnels';
  static const String swipeGroupMainstream = 'L\'actu au quotidien';
  static const String swipeGroupPerspective = 'Un autre point de vue';
  // Profil révélé en direct, en phrase inline sous le deck (remplace les chips
  // du haut). Suivi des libellés de pôles nets-positifs joints par virgules.
  static const String swipeProfileInline = 'On retient pour ta sélection : ';

  // Étiquettes "pôle" affichées sur les cartes de swipe (1 à 2 tags max).
  static const String swipePoleDeep = 'Analyse de fond';
  static const String swipePoleMainstream = 'Actu en continu';
  static const String swipePoleIndependent = 'Indépendant';
  static const String swipePoleEstablished = 'Référence';
  static const String swipePolePerspective = 'Autre angle';

  // Bloc d'infos intrinsèques sur la carte (Tendance + Fiabilité).
  static const String swipeBiasPrefix = 'Tendance : ';
  static const String swipeReliabilityPrefix = 'Fiabilité : ';
  static const String swipeReliabilityHigh = 'Élevée';
  static const String swipeReliabilityMedium = 'Moyenne';
  static const String swipeReliabilityLow = 'Limitée';
  static const String swipeReliabilityUnknown = 'Non évaluée';

  // Moment de calibration en fin de tri + micro-indice pendant les swipes.
  static const String swipeRefiningTitle = 'On affine tes médias…';
  static const String swipeRefiningSubtitle =
      'On ajuste les suggestions à tes goûts.';
  static const String swipeCalibratingHint = 'On affine…';

  // Q8: Gamification
  static const String q8Title =
      'Passer du temps à bien s\'informer est difficile. Travaillons-le !';
  static const String q8Subtitle =
      'Facteur t\'aide à progresser et à rester motivé';
  static const String q8SubtitlePart1 = 'Facteur t\'accompagne avec une ';
  static const String q8SubtitleBold1 = '🔥 streak quotidienne';
  static const String q8SubtitlePart2 = ' pour garder le rythme, et une ';
  static const String q8SubtitleBold2 = '📊 progression hebdomadaire';
  static const String q8SubtitlePart3 =
      ' pour valider que tu retiens vraiment l\'info.';
  static const String q8StreakTitle = 'Streak quotidien';
  static const String q8StreakDesc = '';
  static const String q8WeeklyTitle = 'Progression hebdomadaire';
  static const String q8WeeklyDesc =
      'Valide que tu retiens vraiment l\'information';
  static const String q8YesLabel = 'Essayons !';
  static const String q8NoLabel = 'Je préfère sans';
  static const String q8NoSubtitle = 'Tu pourras activer ça plus tard';

  // Article Count (replaces Weekly Goal)
  static const String articleCountTitle = 'Combien d\'articles par jour ?';
  static const String articleCountSubtitle =
      'Facteur prépare ta sélection quotidienne.';
  static const String articleCount3Label = '3 articles';
  static const String articleCount3Subtitle = 'L\'essentiel immanquable';
  static const String articleCount5Label = '5 articles';
  static const String articleCount5Subtitle =
      'Mix d\'infos importantes & personnalisées';
  static const String articleCount5Recommended = 'Recommandé';
  static const String articleCount7Label = '7 articles';
  static const String articleCount7Subtitle = 'Pour aller plus loin';

  // Digest Mode
  static const String digestModeTitle =
      'Quel mode de récap quotidien préfères-tu ?';
  static const String digestModeSubtitle =
      'Tu pourras changer à tout moment.';

  // Digest Mode — Rester serein (rich subtitle parts)
  static const String digestModeSereinPart1 =
      'Certains sujets peuvent être difficiles à lire. Active le ';
  static const String digestModeSereinBold1 = 'mode serein';
  static const String digestModeSereinPart2 = ' pour ';
  static const String digestModeSereinBold2 = 'filtrer les contenus anxiogènes';
  static const String digestModeSereinPart3 = '.\nTu pourras ';
  static const String digestModeSereinBold3 = 'changer d\'avis à tout moment';
  static const String digestModeSereinPart4 =
      ' grâce au bouton dédié en haut de ton essentiel et du flux.';

  // Réassurance affichée sous les choix du mode serein (sans tiret em).
  static const String digestModeAnytimeNote =
      'Tu pourras activer ou désactiver le mode serein à tout moment depuis Mes intérêts.';

  // Personalised serein CTA (shown on the DigestMode question).
  static const String personalizeSereinCta = 'Personnaliser mon mode serein';

  // Q10: Page sources « sur mesure »
  static const String sourcesSuggestionsTitle = 'Nos suggestions pour toi';
  static const String sourcesAlreadyFollowTitle =
      'Tu suis déjà un média ?';
  static const String sourcesSeeAllCatalog = 'Voir tout le catalogue';

  // Q10: en-têtes des 4 blocs « sur mesure » (①②③④).
  static const String sourcesBlockSuggestionsTitle = 'Tes suggestions';
  static const String sourcesBlockSuggestionsDesc =
      'Des médias à te faire découvrir, sélectionnés pour toi sur la base de '
      'tes réponses. Modifie cette liste à tout moment.';
  static const String sourcesBlockHabitualTitle = 'Tes médias habituels';
  static const String sourcesBlockHabitualSubtitle =
      'Ajoute les médias que tu suis déjà.';
  static const String sourcesBlockHabitualDesc =
      'Les médias que tu connais déjà et aimerais retrouver dans '
      'l\'application. On part les chercher pour toi, s\'ils sont disponibles '
      'publiquement.';
  static const String sourcesBlockCatalogTitle = 'Explorer le catalogue';
  static const String sourcesBlockCatalogSubtitle =
      'Parcours tous les médias disponibles.';
  static const String sourcesBlockCatalogDesc =
      'Curieux de voir d\'autres médias par thématique ? Voici une sélection '
      'que la communauté Facteur a déjà ajoutée.';
  static const String sourcesBlockSubscriptionsTitle = 'Tes abonnements presse';
  static const String sourcesBlockSubscriptionsSubtitle =
      'Connecte tes abonnements payants pour lire les articles en entier.';
  static const String sourcesBlockSubscriptionsDesc =
      'Tu es abonné à un média payant ? Connecte tes abonnements pour lire les '
      'articles en entier, directement dans Facteur.';

  // Preuve instantanée à l'ajout (Wow #1)
  static const String sourceProofConnected = 'Connecté';
  static const String sourceProofEmptyFallback =
      'Ses prochains articles arrivent dans ta tournée.';

  // Conclusion vivante (Wow #2)
  static String conclusionLiveCounter(int articles, int sources) {
    return '$articles article${articles > 1 ? 's' : ''} récupéré${articles > 1 ? 's' : ''} '
        'depuis tes $sources média${sources > 1 ? 's' : ''}';
  }

  // Q9: Sources
  static const String q9Title = 'Tes médias, sur mesure.';
  static const String q9Subtitle =
      'Basé sur tes réponses, voici les médias que Facteur te recommande.';
  static const String q9SearchHint = 'Rechercher un média...';
  static const String q9LoadingError = 'Erreur de chargement des médias';
  static const String q9EmptyList = 'Aucun média disponible';
  static const String q9NoMatch =
      'Aucun média ne correspond à ta recherche';

  // Message de pré-sélection automatique
  static const String q9PreselectionTitle =
      'Modifie cette liste à tout moment.';

  // Sources : abonnements presse
  static const String premiumSubscriptionsButton =
      'Ajouter tes abonnements presse';

  // Carte d'ajout d'abonnement (style CTA Essentiel) sur la page sources.
  static const String addSubscriptionCardTitle = 'Abonné à un média payant ?';
  static const String addSubscriptionCardSubtitle =
      'Le Monde, Mediapart, L\'Équipe... Connecte tes abonnements pour lire '
      'les articles en entier, directement dans Facteur.';
  static const String addSubscriptionCardButton = 'Ajouter mes abonnements';
  static const String premiumSheetTitle = 'Tes abonnements presse';
  static const String premiumSheetSubtitle =
      'Si tu es abonné à un média payant (Le Monde, Mediapart...), '
      'indique-le ici.\n\n'
      'Facteur te redirigera directement vers le site du média '
      'pour lire les articles en entier, et inclura leurs contenus '
      'payants dans ta sélection quotidienne.';
  static const String premiumSheetDone = 'Valider';

  // Q10: Themes
  static const String q10Title = 'Quels sont tes centres d\'intérêt ?';
  static const String q10Subtitle =
      'Sélectionne les thèmes qui t\'importent pour personnaliser ton flux.';

  // Theme Labels
  static const String themeTech = 'Tech';
  static const String themeInternational = 'International';
  static const String themeScience = 'Science';
  static const String themeCulture = 'Culture';
  static const String themePolitics = 'Politique';
  static const String themeSociety = 'Société';
  static const String themeEnvironment = 'Environnement';
  static const String themeEconomy = 'Économie';
  static const String themeSport = 'Sport';

  // Subtopics Screen (Screen B)
  static const String subtopicsTitle = 'Affine tes centres d\'intérêt';
  static const String subtopicsSubtitle =
      'Indique quels sujets tu veux le plus voir apparaitre dans ton feed.';
  static const String addCustomTopicHint = 'Ajouter un sujet';
  static const String maxCustomTopicsReached = 'Maximum 3 sujets par thème';

  // Finalize
  static const String finalizeTitle = 'Ton essentiel est prêt.';
  static const String finalizeSubtitle = 'Voici un résumé de tes choix.';
  static const String finalizeButton = 'Créer mon essentiel';

  // Reactions: Objective (Q1)
  static const String r1NoiseTitle = 'Trop de bruit tue le signal.';
  static const String r1NoiseMessage =
      'Facteur t\'aidera à te concentrer sur l\'essentiel, tout en te laissant le contrôle.';
  static const String r1BiasTitle = 'Voir plus clair.';
  static const String r1BiasMessage =
      'Facteur affichera systématiquement le positionnement des médias.\n\nTu sauras toujours d\'où vient l\'information.';
  static const String r1AnxietyTitle = 'Respirer face au chaos.';
  static const String r1AnxietyMessage =
      'Facteur mettra en avant les solutions, l\'analyse et le recul.\n\nPour retrouver une information qui éclaire sans angoisser.';
  static const String r1MultiTitle = 'Difficile de choisir.';
  static const String r1MultiMessage =
      'Facteur adresse chacun de ces points. Ton récap quotidien vise à répondre à ces préoccupations.';

  // Animated Messages
  static const List<String> conclusionMessages = [
    'Analyse de tes sélections...',
    'Construction de ton profil...',
    'Filtrage du bruit...',
    'Création du flux...',
  ];

  // Helper for pluralization (French)
  static String selectedCount(int count) {
    return 'Continuer ($count sélectionné${count > 1 ? 's' : ''})';
  }

  static String finalizeThemeSummary(int count) {
    return '$count thème${count > 1 ? 's' : ''} sélectionné${count > 1 ? 's' : ''}';
  }

  static String finalizeSourcesSummary(int count) {
    return '$count média${count > 1 ? 's' : ''} sélectionné${count > 1 ? 's' : ''}';
  }

  static String finalizeArticleCountSummary(int count) {
    return '$count article${count > 1 ? 's' : ''} / jour';
  }

  // Manifesto content
  static const String manifestoTitle = 'Notre Manifeste';
  static const String manifestoSection1Title = 'Le Projet';
  static const String manifestoSection1Content =
      'Facteur est un projet open-source visant à créer un espace où l\'information redevient un bien commun, accessible et fiable.';
  static const String manifestoSection2Title = 'Notre Mission';
  static const String manifestoSection2Content =
      'Redonner de la qualité, de l\'indépendance et de la pluralité à l\'information. Trier le signal du bruit pour informer en profondeur.';
  static const String manifestoSection3Title = 'Notre Approche';
  static const String manifestoSection3Content =
      'La technologie doit servir l\'humain. Nous avançons pas-à-pas, avec transparence et avec notre communauté.';
  static const String manifestoCombatsTitle = 'Ce contre quoi nous luttons :';
  static const List<String> manifestoCombatTags = [
    'Concentration des médias',
    'Biais cognitifs',
    'Algorithmes opaques',
    'Addiction numérique',
    'Polarisations extrêmes',
  ];
}
