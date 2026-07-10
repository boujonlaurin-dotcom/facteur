import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/detail/utils/webview_history_tracker.dart';

void main() {
  group('WebViewHistoryTracker', () {
    test('rafale de redirection au boot ne remonte pas la profondeur', () {
      final t = WebViewHistoryTracker();
      t.reset(0);
      // 3 navigations rapprochées (< settle) → redirections consent-wall, AMP…
      t.onNavStart(100);
      t.onNavFinish();
      t.onNavStart(400);
      t.onNavFinish();
      t.onNavStart(900);
      t.onNavFinish();

      expect(t.canClimb, isFalse, reason: 'sortie 1 clic sur l\'article');
      expect(t.depth, 0);
    });

    test('lien suivi après lecture compte comme nav utilisateur', () {
      final t = WebViewHistoryTracker();
      t.reset(0);
      // Boot : rafale de redirections.
      t.onNavStart(200);
      t.onNavFinish();
      // L'utilisateur lit puis suit un lien bien après le settle.
      t.onNavStart(10000);
      t.onNavFinish();

      expect(t.canClimb, isTrue);
      expect(t.depth, 1);

      // Le retour remonte ce cran → retour sur l'article, profondeur nulle.
      t.willGoBack();
      expect(t.depth, 0);
      expect(t.canClimb, isFalse);
    });

    test('notre propre goBack ne réincrémente pas la profondeur', () {
      final t = WebViewHistoryTracker();
      t.reset(0);
      t.onNavStart(10000); // lien utilisateur
      t.onNavFinish();
      expect(t.depth, 1);

      // Retour : willGoBack arme la garde, le onNavStart émis par goBack
      // (même s'il survient bien après le settle) ne doit pas recompter.
      t.willGoBack();
      expect(t.depth, 0);
      t.onNavStart(30000);
      expect(t.depth, 0, reason: 'garde backInProgress active');
      t.onNavFinish();
      expect(t.canClimb, isFalse);
    });

    test('profondeur multi-niveaux : 2 liens → 2 climbs avant sortie', () {
      final t = WebViewHistoryTracker();
      t.reset(0);
      t.onNavStart(5000); // 1er lien
      t.onNavFinish();
      t.onNavStart(10000); // 2e lien
      t.onNavFinish();
      expect(t.depth, 2);

      // 1er retour → remonte au 1er lien.
      t.willGoBack();
      t.onNavStart(15000); // notre goBack, gardé
      t.onNavFinish();
      expect(t.depth, 1);
      expect(t.canClimb, isTrue);

      // 2e retour → remonte à l'article.
      t.willGoBack();
      t.onNavStart(20000);
      t.onNavFinish();
      expect(t.depth, 0);
      expect(t.canClimb, isFalse, reason: 'prochain retour = sortie');
    });

    test('reset remet la profondeur à zéro (rechargement page origine)', () {
      final t = WebViewHistoryTracker();
      t.reset(0);
      t.onNavStart(10000);
      t.onNavFinish();
      expect(t.depth, 1);

      t.reset(50000);
      expect(t.depth, 0);
      expect(t.canClimb, isFalse);
    });
  });
}
