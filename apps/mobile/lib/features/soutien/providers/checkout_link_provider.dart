import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/api/api_provider.dart';
import '../soutien_copy.dart';

/// Levée quand Supabase rate-limite l'OTP (~1 envoi/min par email).
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
/// envoie un magic link Supabase dont le redirect est l'URL RevenueCat Web
/// Billing (`POST /api/checkout/send-link`). State = email de destination
/// après le dernier envoi réussi (null tant que rien n'a été envoyé).
final checkoutLinkProvider =
    AsyncNotifierProvider<CheckoutLinkNotifier, String?>(
  CheckoutLinkNotifier.new,
);

class CheckoutLinkNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  /// Envoie (ou renvoie) le lien. Traduit le status HTTP en exception typée :
  /// 429 → [CheckoutRateLimitedException], 401/403 → [CheckoutAuthException],
  /// tout autre non-2xx → [CheckoutServerException] (avec breadcrumb Sentry du
  /// status reçu, pour ne plus « avaler » silencieusement l'échec).
  Future<void> sendLink({bool resend = false}) async {
    state = const AsyncLoading();
    try {
      final response =
          await ref.read(apiClientProvider).dio.post<Map<String, dynamic>>(
        'checkout/send-link',
        data: {'resend': resend},
      );
      final email = response.data?['email'] as String?;
      state = AsyncData(email);
    } on DioException catch (e, st) {
      final status = e.response?.statusCode;
      if (status == 429) {
        state = AsyncError(const CheckoutRateLimitedException(), st);
        throw const CheckoutRateLimitedException();
      }
      unawaited(Sentry.addBreadcrumb(Breadcrumb(
        category: 'checkout',
        message: 'send-link failed',
        level: SentryLevel.warning,
        data: {'status': status, 'error': e.toString()},
      )));
      if (status == 401 || status == 403) {
        state = AsyncError(const CheckoutAuthException(), st);
        throw const CheckoutAuthException();
      }
      final serverError = CheckoutServerException(status);
      state = AsyncError(serverError, st);
      throw serverError;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
