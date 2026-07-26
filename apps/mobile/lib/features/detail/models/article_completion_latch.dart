import '../../feed/services/read_sync_service.dart' show CompletionSource;

/// Sépare l'**état** « cet article est lu jusqu'au bout » de l'**événement**
/// « il vient de l'être dans cette session ».
///
/// Sans cette distinction, rouvrir un article terminé et re-scroller jusqu'en
/// bas rejouait l'haptique, le POST de complétion et surtout `article_finished`
/// — l'événement même qui doit servir à calibrer l'objectif journalier. Le
/// compteur était donc gonflé par les relectures.
///
/// [seed] est appelé aux trois sources d'amorçage de l'écran (contenu passé au
/// montage, registre local des complétions, réponse du fetch). Elle ne fait que
/// *bloquer* : elle est monotone, donc un amorçage tardif ne peut jamais
/// rouvrir un latch déjà fermé, et une source qui répond « non » après une
/// source qui a répondu « oui » ne peut pas la contredire.
///
/// Classe Dart pure et non logique inline dans l'écran : `ContentDetailScreen`
/// fait 4 800 lignes, monte une WebView et Supabase, et aucun test ne le monte.
/// Inline, cette règle resterait non testée.
class ArticleCompletionLatch {
  bool _prior = false;
  CompletionSource? _source;

  /// L'article était déjà terminé à l'ouverture.
  bool get priorCompleted => _prior;

  /// État affichable : terminé, quelle que soit la session qui l'a produit.
  /// `_source != null` *est* le drapeau de session — [latch] est son seul
  /// écrivain et pose les deux ensemble, donc un booléen séparé ne serait
  /// qu'un doublon à tenir synchronisé.
  bool get completed => _prior || _source != null;

  /// Source de la complétion **de cette session**, `null` s'il n'y en a pas eu.
  CompletionSource? get source => _source;

  void seed({required bool prior}) {
    if (prior) _prior = true;
  }

  /// Tente de fermer le latch. Retourne `true` uniquement si l'appelant doit
  /// émettre l'événement (haptique + POST + analytics).
  ///
  /// Le test `priorCompleted` sort **en tête** : c'est ce qui ferme la course,
  /// plutôt qu'un drapeau de suppression consulté plus tard dans le listener.
  bool latch(CompletionSource source, {bool isExternal = false}) {
    if (_prior || _source != null || isExternal) return false;
    _source = source;
    return true;
  }
}
