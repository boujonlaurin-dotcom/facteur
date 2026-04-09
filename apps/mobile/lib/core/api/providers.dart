import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_state.dart';
import 'api_client.dart';
import 'user_api_service.dart';

/// Provider pour le client Supabase
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Provider pour le client API
final apiClientProvider = Provider<ApiClient>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return ApiClient(
    supabase,
    onAuthError: (code) {
      if (code == 401) {
        // Token invalide ou expiré → message friendly + redirect login
        ref.read(authStateProvider.notifier).handleSessionExpired();
      } else if (code == 403) {
        // Email non confirmé (selon Backend) -> Force redirection vers confirmation.
        // N'est appelé QUE si l'ApiClient a déjà tenté un refresh+retry qui a
        // lui-même échoué avec 403 email_not_confirmed — donc ici l'user est
        // réellement non confirmé côté DB.
        ref.read(authStateProvider.notifier).setForceUnconfirmed();
      }
    },
    // Une requête qui aboutit après récupération (refresh JWT) prouve que le
    // backend considère l'user comme confirmé. On clear le flag même si le
    // JWT local est encore stale.
    onAuthRecovered: () {
      ref.read(authStateProvider.notifier).clearForceUnconfirmed();
    },
  );
});

/// Provider pour le service API utilisateurs
final userApiServiceProvider = Provider<UserApiService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UserApiService(apiClient);
});
