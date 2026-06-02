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
  final bool initialExpanded;
  const _Harness({required this.initialExpanded});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late bool _expanded;
  @override
  void initState() {
    super.initState();
    _expanded = widget.initialExpanded;
  }

  void toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 390,
          child: PerspectivesInlineSection(
            perspectives: [
              _persp('Source-Gauche', 'left'),
              _persp('Source-Centre', 'center'),
              _persp('Source-Droite', 'right'),
            ],
            biasDistribution: const {'left': 1, 'center': 1, 'right': 1},
            keywords: const [],
            contentId: 'test',
            externalSelectedSegments: null,
            onSegmentTap: (_) {},
            onClearSegments: () {},
            onToggle: toggle,
            isExpanded: _expanded,
          ),
        ),
      ),
    );
  }
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required bool initialExpanded,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: _Harness(initialExpanded: initialExpanded),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test(
    'kStartDelay must outlast PerspectivesInlineSection AnimatedSize (250 ms)',
    () {
      // The bug the PO reported: when the panel expands, the AnimatedSize
      // takes 250 ms to grow. If DiffTitle starts its cascade before then,
      // the highlights finalize while still hidden behind the growing
      // container and the user perceives them as already there.
      expect(
        DiffTitle.kStartDelay.inMilliseconds,
        greaterThan(250),
        reason:
            'kStartDelay must exceed the 250 ms AnimatedSize duration so the '
            'cascade is visible after the panel finishes expanding.',
      );
    },
  );

  testWidgets('section starts collapsed → no DiffTitle in the tree', (
    tester,
  ) async {
    await _pumpHarness(tester, initialExpanded: false);
    expect(find.byType(DiffTitle), findsNothing);
  });

  testWidgets('tap toggle → DiffTitle mounts and is still pending its anim', (
    tester,
  ) async {
    await _pumpHarness(tester, initialExpanded: false);
    expect(find.byType(DiffTitle), findsNothing);

    tester.state<_HarnessState>(find.byType(_Harness)).toggle();
    await tester.pump();

    // Right after expand, DiffTitle widgets exist in the tree.
    expect(find.byType(DiffTitle), findsWidgets);

    // Drain the pending Future.delayed timers so flutter_test doesn't
    // complain about a pending timer at teardown.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(DiffTitle), findsWidgets);
  });
}
