import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/feed/widgets/digest_entry_card.dart';

/// Tests unitaires de la carte d'entrée Essentiel insérée en tête du feed.
void main() {
  Widget makeHost({DigestResponse? digest}) {
    return ProviderScope(
      overrides: [
        digestProvider.overrideWith(() => _FakeDigestNotifier(digest)),
      ],
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(
          body: SafeArea(child: DigestEntryCard()),
        ),
      ),
    );
  }

  group('DigestEntryCard', () {
    testWidgets('affiche les deux cartes Essentiel + Bonnes nouvelles',
        (tester) async {
      await tester.pumpWidget(makeHost());
      await tester.pumpAndSettle();

      expect(find.text("L'essentiel du jour"), findsOneWidget);
      expect(find.text("L'ESSENTIEL"), findsOneWidget);
      expect(find.text('Les bonnes nouvelles'), findsOneWidget);
      expect(find.text('BONNES NOUVELLES'), findsOneWidget);
      // Les deux cartes affichent le sous-titre meta « N articles · date ».
      expect(find.textContaining('articles ·'), findsNWidgets(2));
      // Illustration facteur sur la carte Essentiel.
      final essentielIllustration = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/notifications/facteur_avatar.png',
      );
      expect(essentielIllustration, findsOneWidget);
      // Illustration goodnews sur la carte Bonnes nouvelles.
      final goodNewsIllustration = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/notifications/facteur_goodnews.png',
      );
      expect(goodNewsIllustration, findsOneWidget);
    });

    testWidgets('utilise items.length du digest quand chargé', (tester) async {
      final digest = DigestResponse(
        digestId: 'd1',
        userId: 'u1',
        targetDate: DateTime(2026, 5, 21),
        items: List.generate(7, (i) => _stubItem('c$i')),
        topics: const [],
        formatVersion: 'v3',
        generatedAt: DateTime(2026, 5, 21, 8),
      );
      await tester.pumpWidget(makeHost(digest: digest));
      await tester.pumpAndSettle();

      // Les 2 cartes utilisent le même fallback de count quand la variante
      // serein n'est pas encore en cache.
      expect(find.text('7 articles · 21 mai'), findsNWidgets(2));
    });
  });
}

DigestItem _stubItem(String id) => DigestItem(
      contentId: id,
      title: 'Titre $id',
      url: 'https://example.com/$id',
    );

class _FakeDigestNotifier extends DigestNotifier {
  _FakeDigestNotifier(this._digest);

  final DigestResponse? _digest;

  @override
  Future<DigestResponse?> build() async => _digest;
}
