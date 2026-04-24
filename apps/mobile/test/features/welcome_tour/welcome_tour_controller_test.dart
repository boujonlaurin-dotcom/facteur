import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/welcome_tour/controllers/welcome_tour_controller.dart';

void main() {
  group('WelcomeTourController', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('initial state is inactive', () {
      final s = container.read(welcomeTourControllerProvider);
      expect(s.active, isFalse);
      expect(s.currentStep, 0);
    });

    test('start() activates the tour at step 0', () {
      container.read(welcomeTourControllerProvider.notifier).start();
      final s = container.read(welcomeTourControllerProvider);
      expect(s.active, isTrue);
      expect(s.currentStep, 0);
    });

    test('start() is idempotent if already active', () {
      final ctl = container.read(welcomeTourControllerProvider.notifier);
      ctl.start();
      ctl.state = ctl.state.copyWith(currentStep: 1);
      ctl.start(); // no-op
      expect(container.read(welcomeTourControllerProvider).currentStep, 1);
    });

    test('next() advances through steps then finishes with firstDigest', () {
      final ctl = container.read(welcomeTourControllerProvider.notifier);
      ctl.start();
      ctl.next();
      expect(container.read(welcomeTourControllerProvider).currentStep, 1);
      ctl.next();
      expect(container.read(welcomeTourControllerProvider).currentStep, 2);
      ctl.next();
      final s = container.read(welcomeTourControllerProvider);
      expect(s.active, isFalse);
      expect(
        container.read(welcomeTourFinishSignalProvider),
        WelcomeTourFinishSignal.firstDigest,
      );
    });

    test('skip() finishes with plain signal', () {
      final ctl = container.read(welcomeTourControllerProvider.notifier);
      ctl.start();
      ctl.next(); // step 1
      ctl.skip();
      expect(container.read(welcomeTourControllerProvider).active, isFalse);
      expect(
        container.read(welcomeTourFinishSignalProvider),
        WelcomeTourFinishSignal.plain,
      );
    });

    test('next()/skip() are no-op when inactive', () {
      final ctl = container.read(welcomeTourControllerProvider.notifier);
      ctl.next();
      ctl.skip();
      expect(
        container.read(welcomeTourFinishSignalProvider),
        WelcomeTourFinishSignal.none,
      );
    });
  });
}
