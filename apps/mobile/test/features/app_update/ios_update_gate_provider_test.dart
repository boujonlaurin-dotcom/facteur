import 'package:facteur/features/app_update/providers/ios_update_gate_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveIosUpdateLevel', () {
    test('installée < min → gate (prioritaire sur banner)', () {
      expect(
        resolveIosUpdateLevel(
          installed: '1.0.0',
          latest: '1.3.0',
          minSupported: '1.1.0',
        ),
        IosUpdateLevel.gate,
      );
    });

    test('min ≤ installée < latest → banner', () {
      expect(
        resolveIosUpdateLevel(
          installed: '1.1.0',
          latest: '1.3.0',
          minSupported: '1.1.0',
        ),
        IosUpdateLevel.banner,
      );
    });

    test('installée ≥ latest → none', () {
      expect(
        resolveIosUpdateLevel(
          installed: '1.3.0',
          latest: '1.3.0',
          minSupported: '1.1.0',
        ),
        IosUpdateLevel.none,
      );
      expect(
        resolveIosUpdateLevel(
          installed: '2.0.0',
          latest: '1.3.0',
          minSupported: '1.1.0',
        ),
        IosUpdateLevel.none,
      );
    });

    test('comparaison numérique (1.10.0 ≥ 1.9.0 → none)', () {
      expect(
        resolveIosUpdateLevel(installed: '1.10.0', latest: '1.9.0'),
        IosUpdateLevel.none,
      );
    });

    group('fail-open', () {
      test('seuils absents → none', () {
        expect(
          resolveIosUpdateLevel(installed: '1.0.0'),
          IosUpdateLevel.none,
        );
      });

      test('latest malformé → pas de banner', () {
        expect(
          resolveIosUpdateLevel(installed: '1.0.0', latest: 'abc'),
          IosUpdateLevel.none,
        );
      });

      test('min malformé → pas de gate (mais banner si latest valide)', () {
        expect(
          resolveIosUpdateLevel(
            installed: '1.0.0',
            latest: '1.3.0',
            minSupported: 'xx',
          ),
          IosUpdateLevel.banner,
        );
      });

      test('installée malformée → none', () {
        expect(
          resolveIosUpdateLevel(
            installed: '',
            latest: '1.3.0',
            minSupported: '1.1.0',
          ),
          IosUpdateLevel.none,
        );
      });
    });
  });
}
