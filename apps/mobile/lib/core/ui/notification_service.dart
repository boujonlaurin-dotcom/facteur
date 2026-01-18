import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/theme.dart';

/// Service centralisé pour la gestion des notifications (SnackBars)
class NotificationService {
  NotificationService._();

  /// Clé globale pour le ScaffoldMessenger (Indispensable pour MaterialApp.router)
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Clé globale pour le Navigator (Gardée pour compatibilité router)
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Timer de secours pour assurer la disparition si Flutter bloque
  static Timer? _autoHideTimer;

  /// Affiche une notification d'information
  static void showInfo(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
    IconData? icon,
    BuildContext? context,
  }) {
    final state = messengerKey.currentState;
    if (state == null) return;

    // Annuler les timers précédents
    _autoHideTimer?.cancel();

    // Nettoyage immédiat
    state.removeCurrentSnackBar();

    final colors = (context ?? messengerKey.currentContext)?.facteurColors;
    final primaryColor = colors?.primary ?? const Color(0xFFD35400);

    state.showSnackBar(
      SnackBar(
        key: ValueKey('info_${DateTime.now().millisecondsSinceEpoch}'),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                message,
                style: FacteurTypography.bodyMedium(Colors.white)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        action: actionLabel != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.white,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );

    // Timer de secours final (radical)
    _autoHideTimer = Timer(duration + const Duration(milliseconds: 500), () {
      messengerKey.currentState?.hideCurrentSnackBar();
    });
  }

  /// Affiche une notification de succès
  static void showSuccess(String message, {BuildContext? context}) {
    showInfo(
      message,
      icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
      context: context,
    );
  }

  /// Affiche une notification d'erreur
  static void showError(String message, {BuildContext? context}) {
    final state = messengerKey.currentState;
    if (state == null) return;

    _autoHideTimer?.cancel();
    state.removeCurrentSnackBar();

    final colors = (context ?? messengerKey.currentContext)?.facteurColors;
    final errorColor = colors?.error ?? const Color(0xFFC0392B);

    state.showSnackBar(
      SnackBar(
        key: ValueKey('error_${DateTime.now().millisecondsSinceEpoch}'),
        content: Row(
          children: [
            Icon(
              PhosphorIcons.warningCircle(PhosphorIconsStyle.fill),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: FacteurTypography.bodyMedium(Colors.white)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: errorColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    _autoHideTimer = Timer(const Duration(seconds: 5), () {
      messengerKey.currentState?.hideCurrentSnackBar();
    });
  }

  /// Masque la notification actuelle
  static void hide({BuildContext? context}) {
    _autoHideTimer?.cancel();
    messengerKey.currentState?.hideCurrentSnackBar();
    messengerKey.currentState?.clearSnackBars();
  }
}
