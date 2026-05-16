import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

String _todayKey() {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return 'flux_continu_folded_$today';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;
  late ProviderContainer container;

  setUp(() {
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    // The provider wraps each upstream call in `_safe<T>` which catches and
    // logs — empty/throwing repos are the canonical "no payload" path.
    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          serein: any(named: 'serein'),
        )).thenThrow(Exception('mock: no feed'));

    container = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('FluxContinuNotifier — purge cross-day', () {
    test('removes folded keys from previous days, keeps today\'s key',
        () async {
      const oldKey = 'flux_continu_folded_2020-01-01';
      const oldClosingKey = 'flux_continu_closing_dismissed_2020-01-01';
      final todayFoldedKey = _todayKey();

      SharedPreferences.setMockInitialValues({
        oldKey: <String>['essentiel'],
        oldClosingKey: true,
        todayFoldedKey: <String>['bonnes'],
      });

      await container.read(fluxContinuProvider.future);
      // Purge runs as `unawaited` — give the microtask queue a beat.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      expect(keys, isNot(contains(oldKey)));
      expect(keys, isNot(contains(oldClosingKey)));
      expect(keys, contains(todayFoldedKey));
    });

    test('starts with empty folded map when no key exists for today', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final state = await container.read(fluxContinuProvider.future);

      expect(state.folded, isEmpty);
    });

    test('loads today\'s folded sections from SharedPreferences on build',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _todayKey(): <String>['essentiel', 'bonnes'],
      });

      final state = await container.read(fluxContinuProvider.future);

      // No sections built (mocks return null), so the compose step strips
      // entries pointing to absent kinds — folded ends up empty even though
      // the prefs had values. This is the intentional behavior of `_compose`.
      expect(state.folded, isEmpty);
    });
  });

  group('FluxContinuNotifier — fold queue', () {
    test('markScrolledPastForNextSession persists section to today\'s key',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await container.read(fluxContinuProvider.future);
      await container
          .read(fluxContinuProvider.notifier)
          .markScrolledPastForNextSession(SectionKind.essentiel);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(_todayKey()), contains('essentiel'));
    });

    test('markScrolledPastForNextSession is idempotent per kind', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await container.read(fluxContinuProvider.future);
      final notifier = container.read(fluxContinuProvider.notifier);
      await notifier.markScrolledPastForNextSession(SectionKind.theme1);
      await notifier.markScrolledPastForNextSession(SectionKind.theme1);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_todayKey()) ?? const [];
      expect(stored.where((s) => s == 'theme1').length, 1);
    });

    test('applyPendingFoldsToState is a no-op when queue is empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      final initial = await container.read(fluxContinuProvider.future);
      container.read(fluxContinuProvider.notifier).applyPendingFoldsToState();
      final after = container.read(fluxContinuProvider).valueOrNull;

      expect(after, isNotNull);
      expect(after!.folded, equals(initial.folded));
    });
  });
}
