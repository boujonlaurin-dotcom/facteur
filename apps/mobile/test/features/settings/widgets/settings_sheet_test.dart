import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/lettres/models/letter_progress.dart';
import 'package:facteur/features/lettres/providers/letters_provider.dart';
import 'package:facteur/features/settings/providers/user_profile_provider.dart';
import 'package:facteur/features/settings/widgets/settings_sheet.dart';
import 'package:facteur/features/premium/premium_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/soutien/providers/premium_gate_provider.dart';
import 'package:facteur/features/soutien/soutien_copy.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProfileNotifier extends StateNotifier<UserProfile>
    implements UserProfileNotifier {
  _FakeProfileNotifier() : super(const UserProfile(displayName: 'Laurin'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSereinNotifier extends StateNotifier<SereinToggleState>
    implements SereinToggleNotifier {
  _FakeSereinNotifier()
      : super(const SereinToggleState(enabled: false, isLoading: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLettersNotifier extends LettersNotifier {
  @override
  Future<LetterProgressState> build() async =>
      const LetterProgressState.empty();
}

class _FakeVeilleNotifier extends VeilleActiveConfigNotifier {
  @override
  Future<VeilleConfigDto?> build() async => null;
}

class _FakeSourcesNotifier extends UserSourcesNotifier {
  _FakeSourcesNotifier(this.count);

  final int count;

  @override
  Future<List<Source>> build() async => List.generate(
        count,
        (i) => Source(
          id: 'src-$i',
          name: 'Source $i',
          type: SourceType.article,
        ),
      );
}

Widget _buildSheet({required bool isPremium, int sourceCount = 12}) {
  return ProviderScope(
    overrides: [
      userProfileProvider.overrideWith((ref) => _FakeProfileNotifier()),
      sereinToggleProvider.overrideWith((ref) => _FakeSereinNotifier()),
      lettersProvider.overrideWith(() => _FakeLettersNotifier()),
      veilleActiveConfigProvider.overrideWith(() => _FakeVeilleNotifier()),
      isPremiumProvider.overrideWithValue(isPremium),
      premiumSinceProvider.overrideWithValue(
        isPremium ? DateTime(2026, 7, 1) : null,
      ),
      userSourcesProvider.overrideWith(() => _FakeSourcesNotifier(sourceCount)),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(body: SettingsSheet()),
    ),
  );
}

void main() {
  testWidgets('global settings no longer duplicates Progression',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => _FakeProfileNotifier()),
          sereinToggleProvider.overrideWith((ref) => _FakeSereinNotifier()),
          lettersProvider.overrideWith(() => _FakeLettersNotifier()),
          veilleActiveConfigProvider.overrideWith(() => _FakeVeilleNotifier()),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(body: SettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mes sources'), findsOneWidget);
    expect(find.text('Mes intérêts'), findsOneWidget);
    expect(find.text('Progression'), findsNothing);
  });

  testWidgets('état free : tuile Nous soutenir, badge N/30, stamp PREMIUM',
      (tester) async {
    await tester.pumpWidget(_buildSheet(isPremium: false, sourceCount: 12));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.soutienTileFreeTitle), findsOneWidget);
    expect(find.text(SoutienCopy.soutienTileFreeSubtitle), findsOneWidget);
    expect(find.text('12/30'), findsOneWidget);
    expect(find.text(SoutienCopy.veillePremiumStamp), findsOneWidget);
    expect(find.text(SoutienCopy.sereinCustomizeLabel), findsOneWidget);
    expect(find.text(SoutienCopy.premiumStamp), findsNothing);
  });

  testWidgets(
      'état premium : stamp Fact·eur·isse + depuis, Ton soutien, pas de badge',
      (tester) async {
    await tester.pumpWidget(_buildSheet(isPremium: true, sourceCount: 45));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.premiumStamp), findsOneWidget);
    expect(find.text('depuis juillet 2026'), findsOneWidget);
    expect(find.text(SoutienCopy.soutienTilePremiumTitle), findsOneWidget);
    expect(find.text(SoutienCopy.soutienTilePremiumSubtitle), findsOneWidget);
    expect(find.text('45/30'), findsNothing);
    expect(find.text(SoutienCopy.veillePremiumStamp), findsNothing);
  });
}
