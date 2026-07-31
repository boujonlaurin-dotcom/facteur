/// Copy de l'invitation « un café en visio » (Epic 13, story 13.3).
///
/// Centralisée ici, sur le modèle de `SoutienCopy`, pour que le PO n'ait qu'un
/// seul fichier à relire. Ton « Nous soutenir » : honnête, direct, signé par les
/// deux fondateurs. Pas d'em-dash dans la copy user-facing (règle projet).
class FeedbackCallCopy {
  FeedbackCallCopy._();

  // ─── Entrée inline (dans le flux, quelques blocs avant la fin) ───
  static const entryLine = "Django & Laurin aimeraient t'entendre 5 minutes.";
  // Le CTA de l'entrée inline est volontairement le même libellé que celui de
  // la modale : voir `ctaBook` plus bas.

  // ─── Modale ───
  static const stamp = 'TON AVIS COMPTE';
  static const title = 'On peut te prendre 5 minutes ?';

  /// Corps segment `active` (lecteur régulier).
  static const bodyActive =
      "Tu lis Facteur régulièrement, et c'est déjà énorme pour nous. On "
      "aimerait t'entendre en vrai : ce qui te plaît, ou ce que tu aimes moins.";

  /// Corps segments `low_active` et `returning` (ouvertures espacées).
  static const bodyOccasional =
      "Tu ouvres parfois Facteur, et c'est déjà énorme pour nous. On aimerait "
      "t'entendre en vrai : ce qui te plaît, ou ce que tu aimes moins.";

  /// L'ask, commun à tous les segments.
  static const ask =
      "Un café en visio, 5 minutes, à l'horaire que tu choisis. Rien à "
      'préparer.';

  static const signature = 'Django & Laurin, tes facteurs';

  // ─── Sorties ───
  static const ctaBook = 'Prendre un café';
  static const ctaLater = 'Plus tard';
  static const ctaAlreadyDone = "On l'a déjà fait";

  /// Corps de la modale selon le segment renvoyé par le backend
  /// ("active" | "low_active" | "returning"). Segment inconnu ou absent :
  /// on retombe sur `active`, jamais sur un constat d'inactivité à tort.
  static String bodyForSegment(String? segment) =>
      segment == 'low_active' || segment == 'returning'
          ? bodyOccasional
          : bodyActive;
}
