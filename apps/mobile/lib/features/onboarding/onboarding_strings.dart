class OnboardingStrings {
  // Common
  static const String continueButton = 'Continuer';
  static const String skipButton = 'Passer cette étape';
  static const String backButtonTooltip = 'Retour';

  // Section Labels
  static const String section1Label = 'Overview';
  static const String section2Label = 'App Preferences';
  static const String section3Label = 'Source Preferences';

  static String sectionCount(int current, int total) =>
      'Section $current/$total';

  // Intro Screen 1
  static const String intro1Title =
      "L'info est devenue un vrai champ de bataille.";
  static const String intro1Subtitle =
      "Certains milliardaires détiennent les médias. \n\nD'autres détiennent les réseaux sociaux.\n\nMais tous se battent pour une seule chose : influencer nos opinions.";

  // Intro Screen 2
  static const String intro2Title =
      'Facteur se veut être un outil de résistance.';
  static const String intro2Subtitle =
      'Une app Open-Source pour reprendre le contrôle de son attention. \nUn espace où la transparence et la qualité de l\'information protègent des \'fake news\'.';
  static const String intro2Button = 'Reprendre le contrôle';

  // Q1: Objective
  static const String q1Title =
      "Commençons par vous. \n\nQu'est-ce qui vous épuise le plus avec l'info ?";
  static const String q1Subtitle = "(Si vous ne deviez en choisir qu'un)";
  static const String q1NoiseLabel = 'Le Bruit';
  static const String q1NoiseSubtitle =
      "Trop d'info. Impossible de bien trier.";
  static const String q1BiasLabel = 'Les Biais';
  static const String q1BiasSubtitle = 'Je doute constamment de la neutralité.';
  static const String q1AnxietyLabel = 'La négativité';
  static const String q1AnxietySubtitle =
      'Le sentiment que le monde devient fou.';

  // Q2: Age
  static const String q2Title = 'Apprenons à se connaitre';
  static const String q2Subtitle = 'Où est-ce que tu te situes ?';
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

  // Q7: Content Recency
  static const String q7Title = 'Vous préférez...';
  static const String q7Subtitle = '';
  static const String q7RecentLabel = 'L\'actu du moment';
  static const String q7RecentSubtitle = 'Ce qui se passe maintenant';
  static const String q7TimelessLabel = 'Des analyses intemporelles';
  static const String q7TimelessSubtitle = 'Des contenus qui durent';

  // Q8: Gamification
  static const String q8Title =
      'Passer du temps à bien s\'informer est difficile. Travaillons-le !';
  static const String q8Subtitle =
      'Facteur t\'aide à progresser et à rester motivé';
  static const String q8StreakTitle = 'Streak quotidien';
  static const String q8StreakDesc = '';
  static const String q8WeeklyTitle = 'Progression hebdomadaire';
  static const String q8WeeklyDesc =
      'Valide que tu retiens vraiment l\'information';
  static const String q8YesLabel = 'Essayons !';
  static const String q8NoLabel = 'Je préfère sans';
  static const String q8NoSubtitle = 'Tu pourras activer ça plus tard';

  // Q8b: Weekly Goal
  static const String q8bTitle = 'Votre objectif hebdo ?';
  static const String q8bSubtitle =
      'Combien de contenus à consulter et s\'approprier chaque semaine ?';
  static const String q8bGoal5Label = '5 contenus';
  static const String q8bGoal5Subtitle = '~20 min / semaine • Découverte';
  static const String q8bGoal10Label = '10 contenus';
  static const String q8bGoal10Subtitle = '~40 min / semaine • Proactif';
  static const String q8bGoal10Recommended = 'Recommandé';
  static const String q8bGoal15Label = '15 contenus';
  static const String q8bGoal15Subtitle = '~1h / semaine • Expert';

  // Q9: Sources
  static const String q9Title = 'Construisons votre front de sources fiables.';
  static const String q9Subtitle =
      'Sélectionnez les sources qui seront privilégiées pour votre flux.';
  static const String q9SearchHint = 'Rechercher une source...';
  static const String q9LoadingError = 'Erreur de chargement des sources';
  static const String q9EmptyList = 'Aucune source disponible';
  static const String q9NoMatch =
      'Aucune source ne correspond à votre recherche';

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

  // Finalize
  static const String finalizeTitle =
      'Ok.\nOn voit maintenant mieux comment aider.';
  static const String finalizeSubtitle = 'Votre flux personnalisé est prêt.';
  static const String finalizeFormatShort = 'Articles courts préférés';
  static const String finalizeFormatLong = 'Articles longs préférés';
  static const String finalizeFormatAudio = 'Podcasts préférés';
  static const String finalizeFormatVideo = 'Vidéos préférées';
  static const String finalizeFormatMixed = 'Format mixte';
  static const String finalizeButton = 'Créer mon flux transparent';

  // Reactions: Objective (Q1)
  static const String r1NoiseTitle = 'Trop de bruit tue le signal.';
  static const String r1NoiseMessage =
      'Facteur vous aidera à vous concentrer sur l\'essentiel, tout en vous laissant le contrôle.';
  static const String r1BiasTitle = 'Voir plus clair.';
  static const String r1BiasMessage =
      'Facteur affichera systématiquement le positionnement des sources.\n\nVous saurez toujours d\'où vient l\'information.';
  static const String r1AnxietyTitle = 'Avoir la vue complète.';
  static const String r1AnxietyMessage =
      'Facteur privilégiera le temps long et l\'analyse.\n\nLe meilleur remède au chaos est d\'en comprendre les racines.';

  // Reactions: Preferences (Section 2)
  static const String r2RecentTitle = 'Ne pas perdre le fil !';
  static const String r2RecentMessage =
      'Facteur priorisera les contenus récents pour vous garder à jour.\n\n';
  static const String r2TimelessTitle = '"L\'Histoire se répète."';
  static const String r2TimelessMessage =
      'Facteur privilégiera les analyses qui traversent le temps.\n\n';
  static const String r2DefaultTitle = 'Préférences bien enregistrées.';
  static const String r2DefaultMessage =
      'Facteur personnalise votre profil.\n\nEncore quelques questions et on y est !';

  // Animated Messages
  static const List<String> conclusionMessages = [
    'Analyse de vos sélections...',
    'Construction de votre profil...',
    'Filtrage de votre bruit...',
    'Création du flux...',
  ];

  // Helper for pluralization (French)
  static String selectedCount(int count) {
    return 'Continuer ($count sélectionné${count > 1 ? 's' : ''})';
  }

  static String finalizeThemeSummary(int count) {
    return '$count thème${count > 1 ? 's' : ''} sélectionné${count > 1 ? 's' : ''}';
  }

  static String finalizeGoalSummary(int goal) {
    return 'Objectif : $goal contenus/semaine';
  }
}
