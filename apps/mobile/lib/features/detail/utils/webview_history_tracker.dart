/// Suit la profondeur de navigation **utilisateur** dans le WebView du reader
/// pour décider si un retour doit remonter l'historique (`goBack`) ou quitter le
/// WebView (`_exitWebViewMode`).
///
/// Problème résolu : `canGoBack()` renvoie quasi toujours `true` sur la page
/// d'origine d'un article, car le chargement initial empile des entrées
/// d'historique fantômes (redirections consent-wall/CMP, `http→https`, AMP,
/// sauts de tracking, `location.replace`…). S'y fier imposait **2 clics** pour
/// sortir d'un article.
///
/// Heuristique : une navigation ne compte comme « utilisateur » que si elle
/// survient **après un temps de repos** ([redirectSettleMs]) depuis la dernière
/// navigation. Les rafales de redirection du boot s'enchaînent en < ~1,2 s sans
/// interaction → elles n'incrémentent pas la profondeur.
///
/// Logique pure : `nowMs` est injecté à chaque appel (aucune dépendance à
/// `DateTime.now()` interne), donc entièrement testable en unitaire.
class WebViewHistoryTracker {
  WebViewHistoryTracker({this.redirectSettleMs = 1200});

  /// Délai minimal (ms) entre deux navigations main-frame pour qu'une nav
  /// compte comme « utilisateur » et non comme une rafale de redirection.
  final int redirectSettleMs;

  /// Profondeur de navigation utilisateur (nombre de crans remontables).
  int _depth = 0;

  /// Horodatage de la dernière navigation observée.
  int _lastNavAtMs = 0;

  /// Vrai entre notre `willGoBack()` et le prochain `onNavFinish()` : la
  /// navigation en cours est notre propre `goBack`, elle ne doit pas compter.
  bool _backInProgress = false;

  /// Appelé quand le contrôleur (re)charge la page d'origine.
  void reset(int nowMs) {
    _depth = 0;
    _lastNavAtMs = nowMs;
    _backInProgress = false;
  }

  /// Début de navigation main-frame (`onPageStarted` / `onLoadStart`).
  void onNavStart(int nowMs) {
    final elapsed = nowMs - _lastNavAtMs;
    _lastNavAtMs = nowMs;
    // Notre propre goBack : ne compte pas comme une nav utilisateur.
    if (_backInProgress) return;
    // Vraie nav utilisateur uniquement après un temps de repos ; sinon rafale
    // de redirection au chargement → ignorée.
    if (elapsed >= redirectSettleMs) {
      _depth++;
    }
  }

  /// Fin de navigation (`onPageFinished` / `onLoadStop`) : lève la garde.
  void onNavFinish() {
    _backInProgress = false;
  }

  /// Vrai s'il reste au moins un cran d'historique utilisateur à remonter.
  bool get canClimb => _depth > 0;

  /// Avant notre `goBack` : décrémente la profondeur et arme la garde pour que
  /// le `onNavStart` déclenché par ce `goBack` ne recompte pas.
  void willGoBack() {
    if (_depth > 0) _depth--;
    _backInProgress = true;
  }

  /// Profondeur courante (exposée pour les tests).
  int get depth => _depth;
}
