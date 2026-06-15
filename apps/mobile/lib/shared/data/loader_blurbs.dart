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

  const LoaderBlurb({required this.kind, required this.text, this.attribution});

  /// Étiquette courte affichée au-dessus du texte (ton Facteur).
  String get label {
    switch (kind) {
      case LoaderBlurbKind.citation:
        return 'Citation';
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
  // --- Citations (10) — toutes attribuées ---
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
        'Là où il y avait quelque chose à voir, j\'y suis allé. Là où il y avait quelque chose à entendre, j\'ai écouté.',
    attribution: 'Albert Londres',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.citation,
    text:
        'La vérité est rarement pure et jamais simple. La vie moderne serait extrêmement ennuyeuse si elle l\'était.',
    attribution: 'Oscar Wilde',
  ),

  // --- Stats (10) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        '9 milliardaires français possèdent actuellement plus de 80% des quotidiens nationaux.',
    attribution: 'Source : Oxfam France, 2022',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text: 'Un Français consulte l\'actualité en moyenne 4 fois par jour.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Le cerveau a besoin d\'environ 23 minutes pour se reconcentrer après une interruption.',
    attribution: 'Source : Université de Californie, Irvine',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Selon le MIT, les fausses nouvelles se propagent 6 fois plus vite que les vraies.',
    attribution: 'Source : MIT, 2018',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Plus de 70% des Français se décalarent aujourd\'hui fatigués par l\'actualité.',
    attribution: 'Reuters Digital News Report 2024',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Le scroll moyen d\'un fil d\'actu est d\'environ 90 mètres par jour - et reste en constante augmentation depuis 15 ans.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.stat,
    text:
        'Un titre négatif a 30% de chances en plus d\'être cliqué qu\'un titre neutre - et +2,8% pour chaque mot négatif ajouté en plus.',
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
        'L\'expression « breaking news » est apparue pour la première fois dans les années 1990 sur la chaine d\'information américaine CNN.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le « slow journalism » est né dans les années 2010, en réaction au trop-plein d\'info créé par les réseaux sociaux et les chaines d\'information en continu.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Le mot « facteur » vient initialement sdu latin "factor" : celui qui agit, qui fait.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'Avant Internet, les journalistes appelaient leurs sources depuis des cabines téléphoniques. Romantique, mais lent.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.anecdote,
    text:
        'En 1631, Théophraste Renaudot lançait La Gazette : le tout premier journal d\'information périodique paru en France.',
  ),

  // --- Astuces (8) ---
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Suivez et recevez des alertes sur vos sujets préférés en les ajoutant dans "Mes intérêts" ou en créant une veille personnalisée.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ajoutez n\'importe quel média à Facteur via l\'onglet "Mes sources de confiance !',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ajoutez n\'importe quel média ou thème à vos favoris pour ne pas rater vos articles préférés.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Activez le mode serein chaque fois que vous voulez éviter la négativité dans l\'actu. Personnalisez le mode dans "Mes intérêts" pour choisir quels sujets éviters.',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Vos sauvegardes sont rangées dans l\'onglet « Plus tard ». Faites-y un tour régulièrement !',
  ),
  LoaderBlurb(
    kind: LoaderBlurbKind.tip,
    text:
        'Ouvrir Facteur chaque jour entretient votre série (flammes en haut de l\'écran).',
  ),
];
