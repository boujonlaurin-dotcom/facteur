import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/pepites_carousel.dart';

class _FakePepitesNotifier extends PepitesNotifier {
  _FakePepitesNotifier(this._initial);
  final List<Source> _initial;
  int dismissCalls = 0;

  @override
  Future<List<Source>> build() async => _initial;

  @override
  Future<void> dismiss() async {
    dismissCalls++;
    state = const AsyncValue.data([]);
  }
}

void main() {
  group('PepitesCarousel', () {
    final mockSources = [
      Source(
        id: '1',
        name: 'Le Grand Continent',
        type: SourceType.article,
        theme: 'international',
        followerCount: 340,
      ),
      Source(
        id: '2',
        name: 'Next.ink',
        type: SourceType.article,
        theme: 'tech',
        followerCount: 128,
      ),
    ];

    Widget wrap({required List<Source> sources, _FakePepitesNotifier? notifier}) {
      final fake = notifier ?? _FakePepitesNotifier(sources);
      return ProviderScope(
        overrides: [
          pepitesProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(body: PepitesCarousel()),
        ),
      );
    }

    testWidgets('renders title and source cards when data loaded',
        (tester) async {
      await tester.pumpWidget(wrap(sources: mockSources));
      await tester.pumpAndSettle();

      expect(find.text("Recos. de l'équipe Facteur"), findsOneWidget);
      expect(find.text('Le Grand Continent'), findsOneWidget);
      expect(find.text('Next.ink'), findsOneWidget);
    });

    testWidgets('renders nothing when list is empty', (tester) async {
      await tester.pumpWidget(wrap(sources: const []));
      await tester.pumpAndSettle();

      expect(find.text("Recos. de l'équipe Facteur"), findsNothing);
    });

    testWidgets('dismiss button calls notifier.dismiss', (tester) async {
      final fake = _FakePepitesNotifier(mockSources);
      await tester.pumpWidget(wrap(sources: mockSources, notifier: fake));
      await tester.pumpAndSettle();

      final dismiss = find.bySemanticsLabel('Masquer les recommandations');
      expect(dismiss, findsOneWidget);

      await tester.tap(dismiss);
      await tester.pumpAndSettle();

      expect(fake.dismissCalls, 1);
      expect(find.text('Le Grand Continent'), findsNothing);
    });
  });
}
