import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';

/// Story 9.8 « L'Essentiel dynamique au retour » — la mécanique anti-refresh
/// intempestif. Inspirée d'Instagram / LinkedIn : cooldown + gate « en haut du
/// feed » pour ne jamais recharger sous les yeux d'un utilisateur en pleine
/// lecture (perte du fil de progression).
void main() {
  group('shouldRefreshEssentielOnForeground', () {
    const cooldown = essentielForegroundRefreshCooldown;

    test('ne rafraîchit pas si l\'utilisateur n\'est pas en haut du feed', () {
      // Même après une longue absence : rafraîchir mid-scroll décalerait le
      // contenu et ferait perdre le fil → interdit.
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: false,
          backgroundedFor: cooldown * 3,
          sinceLastRefresh: null,
        ),
        isFalse,
      );
    });

    test('ne rafraîchit pas sur une bascule éclair (< cooldown)', () {
      // Lire une notif / copier un lien : retour quasi immédiat → pas de reload.
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: true,
          backgroundedFor: cooldown - const Duration(seconds: 1),
          sinceLastRefresh: null,
        ),
        isFalse,
      );
    });

    test('ne rafraîchit pas si la durée d\'arrière-plan est inconnue', () {
      // Contrairement au widget Flâner (elapsed null → refresh), on préfère ici
      // un faux négatif silencieux à un rechargement injustifié.
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: true,
          backgroundedFor: null,
          sinceLastRefresh: null,
        ),
        isFalse,
      );
    });

    test('rafraîchit après un vrai passage en arrière-plan, en haut du feed', () {
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: true,
          backgroundedFor: cooldown,
          sinceLastRefresh: null,
        ),
        isTrue,
      );
    });

    test('respecte le cooldown entre deux refresh rapprochés', () {
      // Deux cycles background/foreground successifs : le second reste bloqué
      // tant que le cooldown depuis le dernier refresh n'est pas écoulé.
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: true,
          backgroundedFor: cooldown * 2,
          sinceLastRefresh: cooldown - const Duration(seconds: 1),
        ),
        isFalse,
      );
      expect(
        shouldRefreshEssentielOnForeground(
          atTop: true,
          backgroundedFor: cooldown * 2,
          sinceLastRefresh: cooldown,
        ),
        isTrue,
      );
    });
  });
}
