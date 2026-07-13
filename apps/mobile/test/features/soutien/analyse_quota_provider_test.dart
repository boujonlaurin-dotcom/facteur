import 'package:facteur/features/premium/premium_provider.dart';
import 'package:facteur/features/soutien/providers/analyse_quota_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _todayKey() {
  final now = DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return 'analyse_quota_${now.year}-$m-$d';
}

ProviderContainer _makeContainer({bool isPremium = false}) {
  final container = ProviderContainer(
    overrides: [isPremiumProvider.overrideWithValue(isPremium)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quota libre au premier lancement du jour', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _makeContainer();
    await container.read(analyseQuotaProvider.future);
    expect(container.read(analyseQuotaProvider.notifier).canLaunch, isTrue);
  });

  test('recordUse consomme le quota du jour', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _makeContainer();
    final notifier = container.read(analyseQuotaProvider.notifier);
    await container.read(analyseQuotaProvider.future);

    await notifier.recordUse();

    expect(notifier.canLaunch, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(_todayKey()), isTrue);
  });

  test('rollover : une clé de la veille est purgée et le quota se libère',
      () async {
    SharedPreferences.setMockInitialValues({'analyse_quota_2020-01-01': true});
    final container = _makeContainer();
    final used = await container.read(analyseQuotaProvider.future);

    expect(used, isFalse);
    expect(container.read(analyseQuotaProvider.notifier).canLaunch, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('analyse_quota_2020-01-01'), isNull);
  });

  test('premium : canLaunch reste vrai et recordUse est un no-op', () async {
    SharedPreferences.setMockInitialValues({_todayKey(): true});
    final container = _makeContainer(isPremium: true);
    final notifier = container.read(analyseQuotaProvider.notifier);
    await container.read(analyseQuotaProvider.future);

    expect(notifier.canLaunch, isTrue);

    await notifier.recordUse();
    // Le quota free du jour reste tel quel (déjà true ici), mais un premium
    // ne doit jamais être bloqué.
    expect(notifier.canLaunch, isTrue);
  });
}
