import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan, TokenSpan;
import 'package:facteur/features/feed/widgets/article_viewer_modal.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';
import 'package:facteur/widgets/design/facteur_card.dart';

/// Garantit qu'un tap sur une carte/ligne de perspective ouvre le **reader
/// in-app** (`ArticleViewerModal.perspective`) au lieu de basculer vers le
/// navigateur système via `launchUrl`. Le PO veut garder l'utilisateur dans
/// l'app — l'absence de `launchUrl` ici protège ce contrat (les MissingPluginException
/// de `url_launcher` en widget test sont d'ailleurs un signe direct de régression).
Perspective _persp(String name, String bias) => Perspective(
      title: 'Titre court avec mot fort',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '$name.example.com',
      biasStance: bias,
      highlightSpans: const [
        HighlightSpan(start: 18, end: 22, text: 'fort', bias: 'left'),
      ],
      sharedTokens: const [TokenSpan(start: 0, end: 5, text: 'Titre')],
    );

Widget _variantRowHarness() {
  return ProviderScope(
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 390,
            child: PerspectivesInlineSection(
              perspectives: [_persp('Source-Gauche', 'left')],
              biasDistribution: const {'left': 1},
              keywords: const [],
              contentId: 'test',
              externalSelectedSegments: null,
              onSegmentTap: (_) {},
              onClearSegments: () {},
              onToggle: () {},
              isExpanded: true,
              referenceTitle: '',
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _bottomSheetHarness() {
  return ProviderScope(
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => PerspectivesBottomSheet(
                  perspectives: [_persp('Source-Gauche', 'left')],
                  biasDistribution: const {'left': 1},
                  keywords: const [],
                  contentId: 'test',
                ),
              ),
              child: const Text('open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    // FacteurCard.onTap await `HapticFeedback.mediumImpact()` avant de
    // déclencher le callback ; sans handler mocké, le future ne se résout
    // jamais en widget test et le modal ne s'ouvre pas.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      '_VariantRow tap → ouvre ArticleViewerModal in-app (pas de launchUrl)',
      (tester) async {
    await tester.pumpWidget(_variantRowHarness());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ArticleViewerModal), findsNothing,
        reason: 'La modal ne doit pas être présente avant le tap.');

    // Tape sur le DiffTitle (le titre est rendu via RichText, pas Text).
    final tappable = find.byType(DiffTitle);
    expect(tappable, findsWidgets);
    await tester.tap(tappable.first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ArticleViewerModal), findsOneWidget,
        reason:
            'Le tap doit ouvrir ArticleViewerModal.perspective in-app via '
            'showModalBottomSheet — pas launchUrl(externalApplication).');
  });

  testWidgets(
      '_PerspectiveCard tap → ouvre ArticleViewerModal in-app (pas de launchUrl)',
      (tester) async {
    await tester.pumpWidget(_bottomSheetHarness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    expect(find.byType(PerspectivesBottomSheet), findsOneWidget);
    expect(find.byType(ArticleViewerModal), findsNothing);

    // Tape sur la zone titre de la FacteurCard. Le footer interne a un
    // `GestureDetector` opaque (pour le source detail modal) qui absorbe les
    // taps même quand son onTap est null — donc on cible une position en
    // haut de la carte, dans la région du DiffTitle.
    // FacteurCard.onTap await HapticFeedback.mediumImpact() avant de
    // déclencher le callback — on laisse pumpAndSettle absorber le délai.
    final card = find.byType(FacteurCard);
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    await tester.tapAt(Offset(cardRect.center.dx, cardRect.top + 24));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byType(ArticleViewerModal), findsOneWidget,
        reason: 'Le tap sur _PerspectiveCard doit ouvrir ArticleViewerModal '
            'in-app via showModalBottomSheet(useRootNavigator: true).');
  });
}
