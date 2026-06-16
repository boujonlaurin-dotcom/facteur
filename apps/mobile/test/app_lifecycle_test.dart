import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/app.dart';

void main() {
  group('shouldRefreshFlanerOnForeground', () {
    test('does not refresh before 30 minutes', () {
      expect(
        shouldRefreshFlanerOnForeground(
          const Duration(minutes: 29, seconds: 59),
        ),
        isFalse,
      );
    });

    test('refreshes at or after 30 minutes', () {
      expect(
        shouldRefreshFlanerOnForeground(const Duration(minutes: 30)),
        isTrue,
      );
      expect(
        shouldRefreshFlanerOnForeground(const Duration(minutes: 45)),
        isTrue,
      );
    });

    test('refreshes when elapsed time is unknown', () {
      expect(shouldRefreshFlanerOnForeground(null), isTrue);
    });
  });
}
