import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/lettres/models/letter_progress.dart';
import 'package:facteur/features/lettres/providers/letters_provider.dart';
import 'package:facteur/features/settings/providers/user_profile_provider.dart';
import 'package:facteur/features/settings/widgets/settings_sheet.dart';
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
}
