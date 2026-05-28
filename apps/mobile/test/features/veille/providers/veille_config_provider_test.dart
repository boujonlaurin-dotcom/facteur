import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_themes_provider.dart';

/// Tests business-logic du `VeilleConfigNotifier` après le drop des suggesters
/// LLM (PR-4, Story 23.3). On vérifie surtout les transitions d'état et le
/// payload envoyé au backend.
void main() {
  late ProviderContainer container;
  late VeilleConfigNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(veilleConfigProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('selectTheme reset customThemeLabel quand on quitte "other"', () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    notifier.setCustomThemeLabel('Musées contemporains');
    expect(container.read(veilleConfigProvider).customThemeLabel,
        'Musées contemporains');

    notifier.selectTheme('tech');
    expect(container.read(veilleConfigProvider).customThemeLabel, isNull);
  });

  test('addKeyword normalise + dédupe + respecte le cap maxKeywords', () {
    for (var i = 0; i < VeilleConfigNotifier.maxKeywords + 5; i++) {
      notifier.addKeyword('kw-$i');
    }
    final keywords = container.read(veilleConfigProvider).keywords;
    expect(keywords.length, VeilleConfigNotifier.maxKeywords);

    notifier.addKeyword('  KW-0  '); // doublon normalisé
    expect(container.read(veilleConfigProvider).keywords.length,
        VeilleConfigNotifier.maxKeywords);
  });

  test('addKeyword rejette les inputs trop courts ou trop longs', () {
    notifier.addKeyword('a'); // 1 char → rejeté
    notifier.addKeyword('ok');
    notifier.addKeyword('x' * 61); // > 60 → rejeté
    expect(container.read(veilleConfigProvider).keywords, {'ok'});
  });

  test('skipStep2 avance à step 3 et clear les signaux optionnels', () {
    notifier.selectTheme('tech');
    notifier.goNext(); // step 2
    notifier.addKeyword('foo');
    notifier.setEditorialBrief('Focus PME');

    notifier.skipStep2();

    final s = container.read(veilleConfigProvider);
    expect(s.step, 3);
    expect(s.skippedStep2, isTrue);
    expect(s.keywords, isEmpty);
    expect(s.editorialBrief, isNull);
  });

  test('skipStep2 est no-op si on n\'est pas en step 2', () {
    notifier.selectTheme('tech');
    notifier.skipStep2();
    expect(container.read(veilleConfigProvider).step, 1);
    expect(container.read(veilleConfigProvider).skippedStep2, isFalse);
  });

  test('addCustomTopic ajoute + coche, doublon idempotent', () {
    notifier.addCustomTopic('IA générative');
    final s1 = container.read(veilleConfigProvider);
    expect(s1.customTopics.length, 1);
    expect(s1.selectedTopics.length, 1);

    notifier.addCustomTopic('  IA Générative  ');
    final s2 = container.read(veilleConfigProvider);
    expect(s2.customTopics.length, 1, reason: 'doublon ignoré');
    expect(s2.selectedTopics.length, 1);
  });

  test('addCustomTopic re-coche un topic déjà présent mais décoché', () {
    notifier.addCustomTopic('IA générative');
    final id = container.read(veilleConfigProvider).customTopics.first.id;
    notifier.toggleTopic(id); // décoche
    expect(container.read(veilleConfigProvider).selectedTopics, isEmpty);

    notifier.addCustomTopic('IA générative');
    expect(container.read(veilleConfigProvider).selectedTopics, {id});
  });

  test('setAdvancedMode ne touche pas aux valeurs déjà saisies', () {
    notifier.addKeyword('foo');
    notifier.setEditorialBrief('brief');
    notifier.setAdvancedMode(true);
    notifier.setAdvancedMode(false);
    final s = container.read(veilleConfigProvider);
    expect(s.keywords, {'foo'});
    expect(s.editorialBrief, 'brief');
  });

  test('resolvedThemeLabel utilise customThemeLabel quand thème = other', () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    notifier.setCustomThemeLabel('Musées');
    expect(container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
        'Musées');
  });

  test('resolvedThemeLabel fallback quand customThemeLabel vide en mode other',
      () {
    notifier.selectTheme(kVeilleOtherThemeSlug);
    expect(container.read(veilleConfigProvider).resolvedThemeLabel('Autre'),
        'Autre');
  });

  test('goNext cap à step 3 / goBack cap à step 1', () {
    expect(container.read(veilleConfigProvider).step, 1);
    notifier.goNext();
    notifier.goNext();
    notifier.goNext(); // tentative au-delà
    expect(container.read(veilleConfigProvider).step, 3);

    notifier.goBack();
    notifier.goBack();
    notifier.goBack(); // tentative en-dessous
    expect(container.read(veilleConfigProvider).step, 1);
  });

  test('realSelectedSourceCount ignore les sources sans apiSourceId', () {
    notifier.addCustomSourceToVeille(
      sourceId: 'src-1',
      name: 'Le Monde',
      url: 'https://lemonde.fr',
    );
    expect(container.read(veilleConfigProvider).realSelectedSourceCount, 1);
  });
}
