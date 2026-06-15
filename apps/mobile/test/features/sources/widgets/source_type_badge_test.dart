import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/widgets/source_type_badge.dart';

void main() {
  Source mk(SourceType type) => Source(
        id: 'src-${type.name}',
        name: 'Source ${type.name}',
        type: type,
      );

  Widget wrap(Widget child) => MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      );

  group('Source.getTypeIcon', () {
    test('null pour article (format implicite, jamais badgé)', () {
      expect(mk(SourceType.article).getTypeIcon(), isNull);
    });

    test('non-null pour les formats non-article', () {
      for (final t in [
        SourceType.youtube,
        SourceType.podcast,
        SourceType.video,
        SourceType.reddit,
      ]) {
        expect(mk(t).getTypeIcon(), isNotNull, reason: 'icône attendue pour $t');
      }
    });
  });

  group('SourceTypeBadge', () {
    testWidgets('ne rend rien pour un article', (tester) async {
      await tester.pumpWidget(wrap(SourceTypeBadge(source: mk(SourceType.article))));

      expect(find.byType(Icon), findsNothing);
      expect(find.text('Article'), findsNothing);
    });

    testWidgets('rend icône + libellé pour un podcast', (tester) async {
      await tester.pumpWidget(wrap(SourceTypeBadge(source: mk(SourceType.podcast))));

      expect(find.byIcon(Icons.podcasts_outlined), findsOneWidget);
      expect(find.text('Podcast'), findsOneWidget);
    });

    testWidgets('rend le libellé vidéo pour une source vidéo', (tester) async {
      await tester.pumpWidget(wrap(SourceTypeBadge(source: mk(SourceType.video))));

      expect(find.text('Vidéo'), findsOneWidget);
    });
  });
}
