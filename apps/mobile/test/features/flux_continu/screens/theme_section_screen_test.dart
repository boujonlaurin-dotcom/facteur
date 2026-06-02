import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/theme_discovery_provider.dart';
import 'package:facteur/features/flux_continu/screens/theme_section_screen.dart';
import 'package:facteur/features/flux_continu/widgets/theme_detail_footer.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Both top-level AsyncNotifiers stay in `loading` forever so the screen renders
/// from `initialSection` and `valueOrNull` is null — exactly the slide-in state
/// where the footer/carousels/discovery used to be hidden behind `scrollExhausted`.
class _LoadingFluxNotifier extends FluxContinuNotifier {
  @override
  Future<FluxContinuState> build() => Completer<FluxContinuState>().future;
}

class _LoadingFeedNotifier extends FeedNotifier {
  @override
  Future<FeedState> build() => Completer<FeedState>().future;
}

Content _content(String id, {bool followed = false}) {
  return Content(
    id: id,
    title: 'title-$id',
    url: 'https://x.test/$id',
    contentType: ContentType.article,
    publishedAt: DateTime(2026, 1, 1),
    source: Source(id: 's-$id', name: 'S', type: SourceType.article),
    isFollowedSource: followed,
  );
}

FeedThemeSection _themeSection({required bool hasMore}) {
  return FeedThemeSection(
    kind: SectionKind.theme,
    label: 'Tech',
    accent: const Color(0xFF2C3E50),
    coreVisibleCount: 3,
    themeSlug: 'tech',
    items: [_content('c0'), _content('c1')],
    hasMore: hasMore,
  );
}

Widget _wrap(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: child,
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
      'ThemeDetailFooter + discovery render even when section.hasMore is true '
      '(no scroll exhaustion required)', (tester) async {
    await tester.pumpWidget(_wrap(
      ThemeSectionScreen(
        sectionKeyValue: 'theme:tech',
        initialSection: _themeSection(hasMore: true),
      ),
      overrides: [
        fluxContinuProvider.overrideWith(_LoadingFluxNotifier.new),
        feedProvider.overrideWith(_LoadingFeedNotifier.new),
        // A non-followed discovery item not already shown → the "Explorer de
        // nouvelles sources" block must render despite hasMore == true.
        themeDiscoveryProvider('tech').overrideWith(
          (ref) async => [_content('d0', followed: false)],
        ),
      ],
    ));
    // Pump frames without settling (the two notifiers never complete).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Footer is always present now — it carries the "Sujet suivant" / "Retour
    // à la Tournée" CTA, the whole point of the fix.
    expect(find.byType(ThemeDetailFooter), findsOneWidget);
    // No next section resolvable (provider still loading) → graceful fallback.
    expect(find.text('Retour à la Tournée'), findsWidgets);
    // Discovery block surfaced below the loaded list without scroll exhaustion.
    expect(find.text('Explorer de nouvelles sources'), findsOneWidget);
  });
}
