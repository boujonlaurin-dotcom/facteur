/// Resolves editorial badge codes to display labels.
///
/// Badge codes: actu, pas_de_recul, pepite, coup_de_coeur.
/// Used by FeedCard footer to show the editorial badge inline.
class EditorialBadge {
  EditorialBadge._();

  /// Returns the display label for a badge code, or null if unknown.
  static String? labelFor(String? badge) {
    switch (badge) {
      case 'actu':
        return "L'actu du jour";
      case 'pas_de_recul':
        return 'Le pas de recul';
      case 'pepite':
        return 'Pépite du jour';
      case 'coup_de_coeur':
        return 'Coup de cœur';
      default:
        return null;
    }
  }
}
