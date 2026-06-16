import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan, TokenSpan;
import 'package:facteur/features/feed/widgets/diff_title.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _persp(String name, String bias) => Perspective(
      title: 'Titre court avec mot fort',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: bias,
      highlightSpans: const [
        HighlightSpan(start: 18, end: 22, text: 'fort', bias: 'left'),
      ],
      sharedTokens: const [TokenSpan(start: 0, end: 5, text: 'Titre')],
    );

class _Harness extends StatefulWidget {
  final PerspectivesSectionStatus initialStatus;
  const _Harness({required this.initialStatus});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late PerspectivesSectionStatus _status;
  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
  }

  void ready() => setState(() => _status = PerspectivesSectionStatus.ready);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 390,
          child: PerspectivesInlineSection(
            status: _status,
            perspectives: [
              _persp('Source-Gauche', 'left'),
              _persp('Source-Centre', 'center'),
            ],
            biasDistribution: const {'left': 1, 'center': 1},
            keywords: const [],
            contentId: 'test',
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required PerspectivesSectionStatus initialStatus,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: _Harness(initialStatus: initialStatus),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test(
    'kStartDelay must outlast PerspectivesInlineSection AnimatedSize (250 ms)',
    () {
      // Quand la couverture passe en `ready`, l'AnimatedSize grandit en 250 ms.
      // Si DiffTitle démarrait sa cascade avant, les highlights se figeraient
      // pendant que le conteneur grandit encore → perçu comme déjà arrivé.
      expect(
        DiffTitle.kStartDelay.inMilliseconds,
        greaterThan(250),
        reason:
            'kStartDelay must exceed the 250 ms AnimatedSize so the cascade is '
            'visible after the carousel appears.',
      );
    },
  );

  testWidgets('status loading → aucun DiffTitle dans l\'arbre', (tester) async {
    await _pumpHarness(tester, initialStatus: PerspectivesSectionStatus.loading);
    expect(find.byType(DiffTitle), findsNothing);
    // Draine le shimmer répétitif au teardown.
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('transition → ready : les DiffTitle montent (cascade en attente)',
      (tester) async {
    await _pumpHarness(tester, initialStatus: PerspectivesSectionStatus.loading);
    expect(find.byType(DiffTitle), findsNothing);

    tester.state<_HarnessState>(find.byType(_Harness)).ready();
    await tester.pump();

    // Dès l'arrivée des cartes, les DiffTitle existent.
    expect(find.byType(DiffTitle), findsWidgets);

    // Draine les Future.delayed/timers en attente.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DiffTitle), findsWidgets);
  });
}
