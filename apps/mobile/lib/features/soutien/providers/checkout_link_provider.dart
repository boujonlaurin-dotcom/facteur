import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/api/api_provider.dart';
import '../soutien_copy.dart';

/// Levée quand le serveur protège la boîte mail contre les renvois rapprochés.
/// L'UI affiche « Patiente une minute avant de renvoyer. ».
class CheckoutRateLimitedException implements Exception {
  const CheckoutRateLimitedException();
}

/// Levée sur un 401/403 : la session n'est plus valide côté backend.
/// L'UI invite à se reconnecter.
class CheckoutAuthException implements Exception {
  const CheckoutAuthException();
}

/// Levée sur toute autre erreur serveur (404/502/503/…) : souci côté backend,
/// remonté à Sentry. L'UI affiche un message générique rassurant.
class CheckoutServerException implements Exception {
  const CheckoutServerException(this.statusCode);
  final int? statusCode;
}

/// État de livraison observable de l'enveloppe de soutien.
class CheckoutLinkDelivery {
  const CheckoutLinkDelivery({
    required this.id,
    required this.status,
    required this.canResend,
  });

  factory CheckoutLinkDelivery.fromJson(Map<String, dynamic> json) {
    return CheckoutLinkDelivery(
      id: json['delivery_id'] as String,
      status: json['status'] as String,
      canResend: json['can_resend'] as bool? ?? false,
    );
  }

  final String id;
  final String status;
  final bool canResend;

  bool get isTerminal =>
      status == 'delivered' ||
      status == 'failed' ||
      status == 'bounced' ||
      status == 'suppressed';
}

/// Copy user-facing pour un échec d'envoi de lien, mappée depuis l'exception
/// typée. Centralisée ici (à côté des exceptions) pour que les surfaces qui
/// appellent [CheckoutLinkNotifier.sendLink] restent synchronisées : ajouter un
/// cas se fait en un seul endroit.
String checkoutErrorMessage(Object error) {
  if (error is CheckoutRateLimitedException) {
    return SoutienCopy.linkSentRateLimited;
  }
  if (error is CheckoutAuthException) {
    return SoutienCopy.sendLinkAuthError;
  }
  return SoutienCopy.sendLinkError;
}

/// Envoi du lien de checkout « Fact·eur·isse » par email.
///
/// Le CTA n'ouvre jamais un paiement in-app (règles stores) : le backend
/// demande une enveloppe Resend suivie jusqu'à sa remise
/// (`POST /api/checkout/send-link`).
final checkoutLinkProvider =
    AsyncNotifierProvider<CheckoutLinkNotifier, CheckoutLinkDelivery?>(
      CheckoutLinkNotifier.new,
    );

class CheckoutLinkNotifier extends AsyncNotifier<CheckoutLinkDelivery?> {
  @override
  Future<CheckoutLinkDelivery?> build() async => null;

  /// Envoie (ou renvoie) le lien. Traduit le status HTTP en exception typée :
  /// 429 → [CheckoutRateLimitedException], 401/403 → [CheckoutAuthException],
  /// tout autre non-2xx → [CheckoutServerException] (avec breadcrumb Sentry du
  /// status reçu, pour ne plus « avaler » silencieusement l'échec).
  Future<CheckoutLinkDelivery> sendLink({bool resend = false}) async {
    final previous = state.valueOrNull;
    state = const AsyncLoading();
    // Un envoi raté ne doit pas effacer une enveloppe déjà acceptée : on garde
    // l'erreur seulement si l'écran n'affichait encore rien.
    void restore(Object error, StackTrace st) {
      state = previous == null ? AsyncError(error, st) : AsyncData(previous);
    }

    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .post<Map<String, dynamic>>(
            'checkout/send-link',
            data: {'resend': resend},
          );
      final delivery = CheckoutLinkDelivery.fromJson(response.data!);
      state = AsyncData(delivery);
      return delivery;
    } on DioException catch (e, st) {
      final status = e.response?.statusCode;
      if (status == 429) {
        restore(const CheckoutRateLimitedException(), st);
        throw const CheckoutRateLimitedException();
      }
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'checkout',
            message: 'send-link failed',
            level: SentryLevel.warning,
            data: {'status': status, 'error': e.toString()},
          ),
        ),
      );
      if (status == 401 || status == 403) {
        restore(const CheckoutAuthException(), st);
        throw const CheckoutAuthException();
      }
      final serverError = CheckoutServerException(status);
      restore(serverError, st);
      throw serverError;
    } catch (e, st) {
      restore(e, st);
      rethrow;
    }
  }

  /// Rafraîchit le statut sans faire clignoter l'écran de confirmation.
  Future<void> refreshStatus() async {
    final delivery = state.valueOrNull;
    if (delivery == null || delivery.isTerminal) return;
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('checkout/send-link/${delivery.id}');
      state = AsyncData(CheckoutLinkDelivery.fromJson(response.data!));
    } on DioException catch (e) {
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            category: 'checkout',
            message: 'support link status refresh failed',
            level: SentryLevel.warning,
            data: {'status': e.response?.statusCode},
          ),
        ),
      );
      // Le dernier statut valable reste affiché : une sonde réseau ratée ne
      // doit pas transformer une enveloppe acceptée en erreur utilisateur.
      state = AsyncData(delivery);
    }
  }
}
