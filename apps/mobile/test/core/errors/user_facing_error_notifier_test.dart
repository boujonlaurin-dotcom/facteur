import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/errors/user_facing_error_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime clock;

  UserFacingErrorNotifier makeNotifier({bool enabled = true}) {
    return UserFacingErrorNotifier.forTesting(
      prefs: SharedPreferences.getInstance,
      now: () => clock,
      enabled: enabled,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 7, 10, 12, 0, 0);
  });

  test('publie un évènement au premier signalement', () async {
    final notifier = makeNotifier();
    var notified = 0;
    notifier.addListener(() => notified++);

    await notifier.report(
      source: UserErrorSource.http5xx,
      signature: 'http_5xx|500|/api/x',
      route: '/api/x',
    );

    expect(notifier.pendingEvent, isNotNull);
    expect(notifier.pendingEvent!.source, UserErrorSource.http5xx);
    expect(notifier.pendingEvent!.shortAck, isFalse);
    expect(notified, 1);
  });

  test('kill-switch off → aucun évènement', () async {
    final notifier = makeNotifier(enabled: false);
    await notifier.report(
      source: UserErrorSource.http5xx,
      signature: 'http_5xx|500|/api/x',
    );
    expect(notifier.pendingEvent, isNull);
  });

  test('cooldown global 5 min : 2e souci (autre signature) muet', () async {
    final notifier = makeNotifier();

    await notifier.report(source: UserErrorSource.http5xx, signature: 'a');
    notifier.clear();

    clock = clock.add(const Duration(minutes: 3));
    await notifier.report(source: UserErrorSource.timeout, signature: 'b');
    expect(notifier.pendingEvent, isNull);

    clock = clock.add(const Duration(minutes: 3)); // > 5 min cumulés
    await notifier.report(source: UserErrorSource.timeout, signature: 'c');
    expect(notifier.pendingEvent, isNotNull);
  });

  test('cooldown par-signature 30 min : même signature muette', () async {
    final notifier = makeNotifier();

    await notifier.report(source: UserErrorSource.http5xx, signature: 'sig');
    notifier.clear();

    // Au-delà du global (5 min) mais sous le per-signature (30 min).
    clock = clock.add(const Duration(minutes: 10));
    await notifier.report(source: UserErrorSource.http5xx, signature: 'sig');
    expect(notifier.pendingEvent, isNull);

    clock = clock.add(const Duration(minutes: 25)); // > 30 min
    await notifier.report(source: UserErrorSource.http5xx, signature: 'sig');
    expect(notifier.pendingEvent, isNotNull);
  });

  test('markReported → variante shortAck sous 24h', () async {
    final notifier = makeNotifier();
    await notifier.markReported();

    clock = clock.add(const Duration(hours: 2));
    await notifier.report(source: UserErrorSource.timeout, signature: 'x');
    expect(notifier.pendingEvent!.shortAck, isTrue);
  });

  test('au-delà de 24h → variante standard', () async {
    final notifier = makeNotifier();
    await notifier.markReported();

    clock = clock.add(const Duration(hours: 25));
    await notifier.report(source: UserErrorSource.timeout, signature: 'x');
    expect(notifier.pendingEvent!.shortAck, isFalse);
  });
}
