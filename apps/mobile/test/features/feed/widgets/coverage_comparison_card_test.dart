import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:facteur/core/utils/fr_compact_messages.dart';
import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan, TokenSpan;
import 'package:facteur/features/feed/widgets/coverage_comparison_card.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _persp({
  String name = 'Libération',
  String bias = 'left',
  String? publishedAt,
}) =>
    Perspective(
      title: 'Trump revendique la mort du chef',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '$name.example.com',
      biasStance: bias,
      publishedAt: publishedAt,
      highlightSpans: const [
        HighlightSpan(start: 6, end: 16, text: 'revendique', bias: 'left'),
      ],
      sharedTokens: const [TokenSpan(start: 0, end: 5, text: 'Trump')],
    );

Perspective? _routed;
const _marker = Key('ext-reader');

GoRouter _router(Widget home) => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => home),
        GoRoute(
          path: RoutePaths.contentExternal,
          name: RouteNames.contentExternal,
          builder: (_, state) {
            _routed = state.extra as Perspective?;
            return const Scaffold(body: SizedBox(key: _marker));
          },
        ),
      ],
    );

/// Hôte à hauteur bornée : la carte épingle son footer en bas via `Expanded`,
/// elle exige donc une hauteur bornée (le carrousel la fournit en prod).
Widget _host(Perspective p) => Center(
      child: SizedBox(
        height: 168,
        child: CoverageComparisonCard(perspective: p),
      ),
    );

Widget _app(Widget home) => MaterialApp.router(
      theme: FacteurTheme.lightTheme,
      routerConfig: _router(home),
    );

void main() {
  final clock = PhosphorIcons.clock(PhosphorIconsStyle.regular);

  setUp(() {
    _routed = null;
    // Locale compacte `fr_short` (enregistrée dans main.dart en prod) → temps
    // relatif court ("3 h") plutôt que le fallback anglais verbeux qui ferait
    // déborder le footer.
    timeago.setLocaleMessages('fr_short', FrCompactMessages());
    TestWidgetsFlutterBinding.ensureInitialized();
    // FacteurCard.onTap await `HapticFeedback.mediumImpact()` avant de router.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('DiffTitle est AU-DESSUS du footer (source)', (tester) async {
    await tester.pumpWidget(_app(_host(_persp())));
    await tester.pump(const Duration(seconds: 1));

    final titleY = tester.getTopLeft(find.byType(DiffTitle)).dy;
    final sourceY = tester.getTopLeft(find.text('Libération')).dy;
    expect(titleY, lessThan(sourceY));
  });

  testWidgets('chip biais en MAJUSCULES', (tester) async {
    await tester.pumpWidget(_app(_host(_persp(bias: 'left'))));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('GAUCHE'), findsOneWidget);
  });

  testWidgets('temps relatif rendu quand publishedAt présent', (tester) async {
    // Date relative à maintenant → "3 h" en fr_short (court, déterministe).
    final threeHoursAgo =
        DateTime.now().subtract(const Duration(hours: 3)).toIso8601String();
    await tester.pumpWidget(
      _app(_host(_persp(publishedAt: threeHoursAgo))),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(clock), findsOneWidget);
  });

  testWidgets('slot temps masqué quand publishedAt absent', (tester) async {
    await tester.pumpWidget(_app(_host(_persp(publishedAt: null))));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(clock), findsNothing);
  });

  testWidgets('slot temps masqué quand publishedAt non parsable',
      (tester) async {
    await tester.pumpWidget(_app(_host(_persp(publishedAt: 'pas-une-date'))));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byIcon(clock), findsNothing);
  });

  testWidgets('tap → route content-external avec la perspective', (tester) async {
    await tester.pumpWidget(_app(_host(_persp())));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(_marker), findsNothing);
    await tester.tap(find.byType(DiffTitle), warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byKey(_marker), findsOneWidget);
    expect(_routed?.url, 'https://example.com/Libération');
  });
}
