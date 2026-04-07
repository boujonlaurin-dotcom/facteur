class OnboardingStrings {
  // Common
  static const String continueButton = 'Continuer';
  static const String skipButton = 'Passer cette étape';
  static const String backButtonTooltip = 'Retour';

  // Section Labels
  static const String section1Label = 'Vue d\'ensemble';
  static const String section2Label = 'Préférences';
  static const String section3Label = 'Intérêts et sources';

  static String sectionCount(int current, int total) =>
      'Section $current/$total';

  // Welcome Screen (ex-Intro 1)
  static const String welcomeTitle = 'Bienvenue sur Facteur !';
  static const String welcomeSubtitle =
      "L'information devrait vous aider à comprendre le monde.\nPas nous submerger.";
  static const String welcomeManifestoButton = 'Lire notre Manifeste';
  static const String welcomeStartButton = 'Commencer';

  // Intro Screen 2
  static const String intro2Title = 'Votre hub d\'infos fiables';
  static const String intro2SubtitlePart1 =
      'Facteur est une app Open-Source pour ';
  static const String intro2SubtitleBold1 =
      'retrouver le plaisir de s\'informer';
  static const String intro2SubtitlePart2 = '. Un espace de ';
  static const String intro2SubtitleBold2 = 'confiance';
  static const String intro2SubtitlePart3 = ', qui mêle ';
  static const String intro2SubtitleBold3 = 'transparence';
  static const String intro2SubtitlePart4 = ', ';
  static const String intro2SubtitleBold4 = 'contrôle';
  static const String intro2SubtitlePart5 = ' et ';
  static const String intro2SubtitleBold5 = 'sources de qualité';
  static const String intro2SubtitlePart6 = '.';
  static const String intro2Button = 'Découvrir Facteur';

  // Media Concentration
  static const String mediaConcentrationTitle =
      'Savez-vous qui possède vos médias ?';
  static const String mediaConcentrationTextPart1 =
      'Cette carte reflète la concentration des médias en France.\nFacteur vous aide à comprendre comment se positionnent les médias pour mieux ';
  static const String mediaConcentrationTextBold1 = 'diversifier vos sources';
  static const String mediaConcentrationTextPart2 = '.';
  static const String mediaConcentrationButton = 'Continuer';

  // Q1: Objective (multi-select)
  static const String q1Title = 'Commençons par vous';
  static const String q1Subtitle =
      "Qu'est-ce qui vous épuise le plus avec l'info ?";
  static const String q1NoiseLabel = 'Le Bruit';
  static const String q1NoiseSubtitle =
      "Trop d'info. Impossible de bien trier";
  static const String q1BiasLabel = 'Les Biais';
  static const String q1BiasSubtitle = 'Je doute constamment de la neutralité';
  static const String q1AnxietyLabel = 'La négativité';
  static const String q1AnxietySubtitle =
      'Le sentiment que le monde devient fou';

  // Q2: Age
  static const String q2Title = 'Apprenons à se connaitre';
  static const String q2Subtitle = 'Où est-ce que vous vous situez ?';
  static const String q2Option18_24 = '18 - 24 ans';
  static const String q2Option25_34 = '25 - 34 ans';
  static const String q2Option35_44 = '35 - 44 ans';
  static const String q2Option45_plus = '45 ans et plus';

  // Q4: Approach
  static const String q4Title = 'Vous préférez...';
  static const String q4Subtitle = '';
  static const String q4DirectLabel = 'Aller droit au but';
  static const String q4DirectSubtitle = 'L\'essentiel, rapidement';
  static const String q4DetailedLabel = 'Prendre le temps';
  static const String q4DetailedSubtitle = 'Explorer en profondeur';

  // Q5: Perspective
  static const String q5Title = 'Vous préférez avoir...';
  static const String q5Subtitle = '';
  static const String q5BigPictureLabel = 'La vue d\'ensemble';
  static const String q5BigPictureSubtitle = 'Comprendre les grandes lignes';
  static const String q5DetailsLabel = 'Dans le détail';
  static const String q5DetailsSubtitle = 'Aller en profondeur';

  // Q6: Response Style
  static const String q6Title = 'Quand vous lisez, vous aimez...';
  static const String q6Subtitle = '';
  static const String q6DecisiveLabel = 'Des avis tranchés';
  static const String q6DecisiveSubtitle = 'Pour des opinions claires';
  static const String q6NuancedLabel = 'Toutes les perspectives';
  static const String q6NuancedSubtitle = 'Voir tous les angles';

  // Q8: Gamification
  static const String q8Title = 'Bien s\'informer, ça se travaille !';
  static const String q8SubtitlePart1 = 'Facteur vous accompagne avec une ';
  static const String q8SubtitleBold1 = '🔥 streak quotidienne';
  static const String q8SubtitlePart2 = ' pour garder le rythme, et une ';
  static const String q8SubtitleBold2 = '📊 progression hebdomadaire';
  static const String q8SubtitlePart3 =
      ' pour valider que vous retenez vraiment l\'info.';
  static const String q8YesLabel = 'Essayons !';
  static const String q8NoLabel = 'Je préfère sans';
  static const String q8NoSubtitle = 'Vous pourrez activer ça plus tard';

  // Article Count (replaces Weekly Goal)
  static const String articleCountTitle = 'Combien d\'articles par jour ?';
  static const String articleCountSubtitle =
      'Facteur prépare votre sélection quotidienne.';
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
      'Quel mode de récap quotidien préférez-vous ?';
  static const String digestModeSubtitle =
      'Vous pourrez changer à tout moment.';

  // Digest Mode — Rester serein (rich subtitle parts)
  static const String digestModeSereinPart1 =
      'Certains sujets peuvent être difficiles à lire. Activez le ';
  static const String digestModeSereinBold1 = 'mode serein';
  static const String digestModeSereinPart2 = ' pour ';
  static const String digestModeSereinBold2 =
      'filtrer les contenus anxiogènes';
  static const String digestModeSereinPart3 = '.\nVous pourrez ';
  static const String digestModeSereinBold3 =
      'changer d\'avis à tout moment';
  static const String digestModeSereinPart4 =
      ' grâce au bouton dédié en haut de votre essentiel et du flux.';

  // Q9: Sources
  static const String q9Title = 'Vos sources, sur mesure';
  static const String q9Subtitle =
      'Basé sur vos réponses, voici les médias que Facteur vous recommande.';
  static const String q9HelperText =
      'Ajoutez vos sources ! Jetez un oeil à vos feeds et boîtes mails préférées.'; // kept for reference but no longer shown in onboarding
  static const String q9SearchHint = 'Rechercher une source...';
  static const String q9LoadingError = 'Erreur de chargement des sources';
  static const String q9EmptyList = 'Aucune source disponible';
  static const String q9NoMatch =
      'Aucune source ne correspond à votre recherche';

  // Message de pré-sélection automatique
  static const String q9PreselectionTitle =
      'Modifiez cette liste à tout moment.';

  // Sources Page 2
  static const String sourcesPage2Title = 'Allez plus loin';
  static const String sourcesPage2Subtitle =
      'Explorez le catalogue complet et ajoutez vos propres sources.';
  static const String addAnySourceButton = 'Ajouter n\'importe quelle source';
  static const String premiumSubscriptionsButton =
      'Ajouter vos abonnements presse';
  static const String premiumSheetTitle = 'Vos abonnements presse';
  static const String premiumSheetSubtitle =
      'Si vous êtes abonné à un média payant (Le Monde, Mediapart...), '
      'indiquez-le ici.\n\n'
      'Facteur vous redirigera directement vers le site du média '
      'pour lire les articles en entier, et inclura leurs contenus '
      'payants dans votre sélection quotidienne.';
  static const String premiumSheetDone = 'Valider';

  // Q10: Themes
  static const String q10Title = 'Quels sont vos centres d\'intérêt ?';
  static const String q10Subtitle =
      'Sélectionnez les thèmes qui vous importent pour personnaliser votre flux.';

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

  // Restart Welcome (v3 re-trigger)
  static const String restartWelcomeTitle = '✨ Facteur fait peau neuve !';
  static const String restartWelcomeSubtitle =
      'Reprenons l\'onboarding pour intégrer plus de sources et sujets pertinents pour vous.';
  static const String restartStartButton = 'C\'est parti !';

  // Subtopics Screen (Screen B)
  static const String subtopicsTitle = 'Affinez vos centres d\'intérêt';
  static const String subtopicsSubtitle =
      'Indiquez quels sujets vous voulez le plus voir apparaitre dans votre flux.';
  static const String addCustomTopicHint = 'Ajouter un sujet';
  static const String maxCustomTopicsReached = 'Maximum 3 sujets par thème';

  // Sources Reaction (after source selection)
  static const String sourcesReactionTitle = 'Vos sources, votre contrôle';
  static const String sourcesReactionMessage =
      'Modifiez ou ajoutez n\'importe quelle autre source à Facteur (newsletters, sites web, etc) depuis vos paramètres.\n\nFacteur est fait pour s\'adapter à vous.';
  static const String addSourceButton = 'Ajouter une source';

  // Finalize
  static const String finalizeTitle = 'Votre essentiel est prêt';
  static const String finalizeSubtitle = 'Voici un résumé de vos choix.';
  static const String finalizeButton = 'Créer mon essentiel';

  // Reactions: Objective (Q1)
  static const String r1NoiseTitle = 'Trop de bruit tue le signal';
  static const String r1NoiseMessage =
      'Facteur vous aidera à vous concentrer sur l\'essentiel, tout en vous laissant le contrôle.';
  static const String r1BiasTitle = 'Voir plus clair';
  static const String r1BiasMessage =
      'Facteur affichera systématiquement le positionnement des sources.\n\nVous saurez toujours d\'où vient l\'information.';
  static const String r1AnxietyTitle = 'Respirer face au chaos';
  static const String r1AnxietyMessage =
      'Facteur mettra en avant les solutions, l\'analyse et le recul.\n\nPour retrouver une information qui éclaire sans angoisser.';
  static const String r1MultiTitle = 'Difficile de choisir';
  static const String r1MultiMessage =
      'Facteur adresse chacun de ces points. Votre récap quotidien vise à répondre à ces préoccupations.';

  // Animated Messages
  static const List<String> conclusionMessages = [
    'Analyse de vos sélections...',
    'Construction de votre profil...',
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
    return '$count source${count > 1 ? 's' : ''} sélectionnée${count > 1 ? 's' : ''}';
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
