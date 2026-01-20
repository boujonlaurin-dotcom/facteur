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
        // Token invalide ou expiré -> Logout immédiat
        ref.read(authStateProvider.notifier).signOut();
      } else if (code == 403) {
        // Email non confirmé (selon Backend) -> Force redirection vers confirmation
        // On ne déconnecte PAS. On change juste le flag pour que le Router redirige.
        ref.read(authStateProvider.notifier).setForceUnconfirmed();
      }
    },
  );
});

/// Provider pour le service API utilisateurs
final userApiServiceProvider = Provider<UserApiService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UserApiService(apiClient);
});
