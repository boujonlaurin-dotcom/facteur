/// Décide si une recherche bredouille doit être remontée à l'analytique.
///
/// Story 30.1 — `search_submitted_empty` doit compter des **recherches**, pas
/// des rendus : un pull-to-refresh, une reprise d'app ou une simple
/// réémission du provider replacent le feed dans le même état vide, pour la
/// même requête. Sans mémoire, le funnel voit plusieurs recherches là où
/// l'utilisateur n'en a fait qu'une.
class EmptySearchReporter {
  String? _lastKey;

  /// Renvoie `true` une seule fois par couple (mot-clé, périmètre) bredouille.
  ///
  /// [itemCount] est `null` tant que le feed n'est pas résolu — on ne conclut
  /// rien d'un chargement en cours.
  bool shouldReport({
    required int? itemCount,
    required String? keyword,
    required bool broadened,
  }) {
    if (itemCount == null) return false;
    final trimmed = keyword?.trim();
    if (itemCount > 0 || trimmed == null || trimmed.isEmpty) {
      // Le feed est reparti : la prochaine bredouille sur la même requête est
      // bien une nouvelle recherche.
      _lastKey = null;
      return false;
    }
    final key = '$trimmed|$broadened';
    if (_lastKey == key) return false;
    _lastKey = key;
    return true;
  }
}
