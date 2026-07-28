import '../ui/notification_service.dart';
import 'widget_service.dart';

/// Point d'entrée unique pour proposer l'épinglage du widget Facteur.
///
/// Le CTA « Ajouter le widget » échouait en silence sur les deux flavors : le
/// plugin ne trouvait jamais le receiver (applicationId ≠ namespace, cf.
/// `WidgetService.androidNamespace`) et l'exception était avalée. L'utilisateur
/// tapait, rien ne se passait, aucun message. Toute surface qui propose
/// l'épinglage passe désormais par ici pour garantir un retour explicite.
class WidgetPinPrompt {
  const WidgetPinPrompt._();

  /// Demande l'épinglage et rend compte à l'utilisateur.
  ///
  /// Succès : silencieux (le launcher affiche déjà sa propre confirmation).
  /// Retourne le résultat pour que l'appelant puisse rafraîchir son état.
  static Future<WidgetPinResult> requestAndReport() async {
    final result = await WidgetService.requestPinWidget();
    switch (result) {
      case WidgetPinResult.requested:
        break;
      case WidgetPinResult.unsupported:
        NotificationService.showInfo(
          'Ton lanceur ne permet pas d\'ajouter le widget automatiquement. '
          'Appuie longuement sur l\'écran d\'accueil, puis choisis Widgets et Facteur.',
          duration: const Duration(seconds: 6),
        );
      case WidgetPinResult.failed:
        NotificationService.showError(
          'Impossible d\'ajouter le widget pour le moment. Réessaie dans un instant.',
        );
    }
    return result;
  }
}
