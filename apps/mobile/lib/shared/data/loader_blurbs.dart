/// Pool éditorial affiché pendant les chargements prolongés du digest et du feed.
///
/// Ces blurbs incarnent le ton Facteur : sérieux, posé, parfois drôle, jamais
/// corporate. Ils transforment l'attente en moment d'apprentissage léger.
library;

enum LoaderBlurbKind { citation, stat, anecdote, tip }

class LoaderBlurb {
  final LoaderBlurbKind kind;
  final String text;
  final String? attribution;

  const LoaderBlurb({
    required this.kind,
    required this.text,
    this.attribution,
  });

  /// Étiquette courte affichée au-dessus du texte (ton Facteur).
  String get label {
    switch (kind) {
      case LoaderBlurbKind.citation:
        return 'On y pensait';
      case LoaderBlurbKind.stat:
        return 'Le saviez-vous';
      case LoaderBlurbKind.anecdote:
        return 'Petite histoire';
      case LoaderBlurbKind.tip:
        return 'Astuce Facteur';
    }
  }
}

const List<LoaderBlurb> loaderBlurbs = [
  // --- Citations (12) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'Une presse libre peut être bonne ou mauvaise, mais sans liberté la presse ne sera jamais qu\'aigrie.',
    attribution: 'Albert Camus',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text: 'Le journalisme, c\'est le contact et la distance.',
    attribution: 'Hubert Beuve-Méry, fondateur du Monde',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'La connaissance s\'acquiert par l\'expérience, tout le reste n\'est que de l\'information.',
    attribution: 'Albert Einstein',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text: 'Lire le journal du jour, c\'est s\'inscrire dans son époque.',
    attribution: 'Régis Debray',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'La fonction d\'une nouvelle est d\'attirer l\'attention sur un événement.',
    attribution: 'Walter Lippmann, 1922',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text: 'On ne pense pas mieux en pensant plus vite.',
    attribution: 'David Allen',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text: 'Le silence est une source de grande force.',
    attribution: 'Lao Tseu',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'Là où il y avait quelque chose à voir, j\'y suis allé. Là où il y avait quelque chose à entendre, j\'ai écouté.',
    attribution: 'Albert Londres',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'La vérité est rarement pure et jamais simple. La vie moderne serait extrêmement ennuyeuse si elle l\'était.',
    attribution: 'Oscar Wilde',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'L\'urgence n\'est pas l\'information. C\'est la compréhension qui prend du temps.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'S\'informer, c\'est choisir ce à quoi on accepte de donner son attention.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text: 'Le pessimisme est d\'humeur ; l\'optimisme est de volonté.',
    attribution: 'Alain',
  ),

  // --- Stats (10) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        '9 milliardaires français possèdent une grande partie des médias quotidiens nationaux.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: 'Un Français consulte l\'actualité en moyenne 4 fois par jour.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Le cerveau a besoin de 23 minutes pour se reconcentrer après une interruption.',
    attribution: 'Université de Californie, Irvine',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Selon le MIT, les fausses nouvelles se propagent 6 fois plus vite que les vraies.',
    attribution: 'MIT, 2018',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: '70% des Français se disent fatigués par l\'actualité.',
    attribution: 'Reuters Digital News Report 2024',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: '30% des Français évitent activement les actualités.',
    attribution: 'Reuters, 2024',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: 'Une heure d\'information de qualité par jour = 365 heures par an.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: 'Le scroll moyen d\'un fil d\'actu : environ 90 mètres par jour.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        '5 minutes de lecture concentrée valent 30 minutes de scroll distrait.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Un titre négatif a 30% de chances en plus d\'être cliqué qu\'un titre neutre.',
    attribution: 'Nature Human Behaviour, 2023',
  ),

  // --- Anecdotes (10) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Hemingway était journaliste avant d\'être romancier. Il disait avoir tout appris de la concision dans les rédactions.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le Monde a été fondé en 1944 sur décision du général de Gaulle, pour reconstruire l\'opinion d\'après-guerre.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'L\'expression « breaking news » est apparue dans les années 1990 sur CNN. Avant ça, l\'actualité prenait son temps.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le « slow journalism » est né dans les années 2010, en réaction directe au flux continu d\'information.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'La revue XXI, créée en 2008, a démontré qu\'on pouvait vendre du long format en kiosque. Le lecteur lent existe.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le mot « facteur » vient du latin factor : celui qui agit, qui fait. Pas mal pour une app, non ?',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Avant Internet, les journalistes appelaient leurs sources depuis des cabines téléphoniques. Romantique, mais lent.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'En 1631, Théophraste Renaudot lançait La Gazette : le premier journal d\'information périodique en France. 4 pages. Hebdomadaire.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le New York Times a longtemps eu une cloche qui sonnait à chaque scoop. Elle sonne moins qu\'avant.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le mot « journal » vient du latin diurnalis : « ce qui appartient au jour ». Il rythmait la journée, pas l\'inverse.',
  ),

  // --- Astuces (8) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Suivez et recevez des alertes sur vos sujets préférés en les ajoutant dans "Mes intérêts"',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ajoutez n\'importe quel média à Facteur dans l\'onglet "Mes sources de confiance !',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ajoutez n\'importe quel média ou thème dans vos favoris pour le retrouver plus facilement.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Filtrer les sujets qui vous semblent anxiogènes dans les paramètres du mode Serein',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Vos sauvegardes sont rangées dans l\'onglet « Plus tard ». Faites-y un tour régulièrement !',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Restez appuyé sur n\'importe quel média ou thème pour personnaliser votre feed.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ouvrir Facteur chaque jour entretient votre série (flammes en haut de l\'écran).',
  ),
];
