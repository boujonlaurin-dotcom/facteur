import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_provider.dart';

/// Levée quand Supabase rate-limite l'OTP (~1 envoi/min par email).
/// L'UI affiche « Patiente une minute avant de renvoyer. ».
class CheckoutRateLimitedException implements Exception {
  const CheckoutRateLimitedException();
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

  /// Envoie (ou renvoie) le lien. Lève [CheckoutRateLimitedException] sur un
  /// 429 Supabase ; toute autre erreur est relancée telle quelle pour que
  /// l'appelant affiche un toast générique.
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
      if (e.response?.statusCode == 429) {
        state = AsyncError(const CheckoutRateLimitedException(), st);
        throw const CheckoutRateLimitedException();
      }
      state = AsyncError(e, st);
      rethrow;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
