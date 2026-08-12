import 'models/tour_step.dart';

/// Copies FR du tour guidé (pattern `onboarding_strings.dart` : `const`,
/// regroupées). Ton chaleureux, tutoiement, sans em-dash (règle PO).
class TourStrings {
  TourStrings._();

  static const String skip = 'Passer';
  static const String next = 'Suivant';
  static const String finish = 'Terminer';

  /// Titre du coach card par étape.
  static String title(TourStep step) => switch (step) {
        TourStep.essentielHero => 'Ta Tournée du jour',
        TourStep.descendsCartes => 'Tout ce qui compte aujourd\'hui',
        TourStep.favorisSheet => 'Compose ta Tournée',
        TourStep.flaner => 'Flâner, à ton rythme',
        TourStep.reglages => 'Tes réglages',
        TourStep.courrier => 'Mon courrier',
        TourStep.serein => 'Mode Serein',
        TourStep.done => 'C\'est parti !',
      };

  /// Corps du coach card par étape.
  static String body(TourStep step) => switch (step) {
        TourStep.essentielHero =>
          'Gardes les articles que tu veux vraiment lire aujourd\'hui.',
        TourStep.descendsCartes =>
          'En descendant, tu retrouves tes sujets et tes sources, rangés en sections.',
        TourStep.favorisSheet =>
          'Ici tu choisis et réorganises ce qui compose ta Tournée. Tout reste à toi.',
        TourStep.flaner =>
          'Envie d\'explorer plus large ? L\'onglet Flâner te laisse parcourir l\'actualité à ton rythme.',
        TourStep.reglages =>
          'Depuis ton profil, en haut à droite, tu ajustes tes réglages quand tu veux.',
        TourStep.courrier =>
          'Et toujours depuis ton profil, tu retrouves Mon courrier : tes articles sauvegardés et tes notes.',
        TourStep.serein =>
          'Certains sujets sont durs à lire. Le Mode Serein met de côté les contenus les plus anxiogènes, pour une lecture plus calme. Active-le ici si tu veux, et change d\'avis à tout moment.',
        TourStep.done => 'Tu connais l\'essentiel. À toi de jouer, bonne lecture !',
      };
}
