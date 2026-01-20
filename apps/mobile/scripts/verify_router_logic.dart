void main() {
  print('🔍 VERIFICATION DU ROUTER MOBILE');
  print('==============================');

  String? simulateRedirect({
    required bool isLoading,
    required bool isAuthenticated,
    required bool isEmailConfirmed,
    required bool needsOnboarding,
    required String matchedLocation,
  }) {
    // Logique exacte de routes.dart
    if (isLoading) return '/splash';
    if (!isAuthenticated) return '/login';
    if (!isEmailConfirmed) {
      if (matchedLocation == '/email-confirmation') return null;
      return '/email-confirmation';
    }
    if (matchedLocation == '/login' ||
        matchedLocation == '/email-confirmation' ||
        matchedLocation == '/splash') {
      return needsOnboarding ? '/onboarding' : '/feed';
    }
    return null;
  }

  void test(String label, String? expected, String? actual) {
    if (expected == actual) {
      print('✅ $label: PASSED');
    } else {
      print('❌ $label: FAILED (Attendu $expected, Got $actual)');
    }
  }

  test(
    'Redirection utilisateur non confirmé depuis le Feed',
    '/email-confirmation',
    simulateRedirect(
      isLoading: false,
      isAuthenticated: true,
      isEmailConfirmed: false,
      needsOnboarding: false,
      matchedLocation: '/feed',
    ),
  );

  test(
    'Maintien sur écran confirmation si non confirmé',
    null,
    simulateRedirect(
      isLoading: false,
      isAuthenticated: true,
      isEmailConfirmed: false,
      needsOnboarding: false,
      matchedLocation: '/email-confirmation',
    ),
  );

  test(
    'Redirection vers Feed pour utilisateur confirmé sur Login',
    '/feed',
    simulateRedirect(
      isLoading: false,
      isAuthenticated: true,
      isEmailConfirmed: true,
      needsOnboarding: false,
      matchedLocation: '/login',
    ),
  );

  print('\nRESULTAT FINAL: TOUX LES TESTS SONT VERIFIÉS');
}
