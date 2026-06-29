import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/edition_essentiel_provider.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/flux_continu/widgets/week_recap_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

EssentielArticle _article(String id, {String title = '', bool isRead = false}) =>
    EssentielArticle(
      contentId: id,
      title: title.isEmpty ? 'Titre $id' : title,
      url: 'https://example.com/$id',
      publishedAt: DateTime(2026, 5, 27),
      sourceName: 'Le Monde',
      sourceLetter: 'L',
      sectionLabel: 'Tech',
      rank: 1,
      isRead: isRead,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpBlock(
    WidgetTester tester, {
    required List<EditionDayGroup> weekDays,
    void Function(EssentielArticle)? onTapArticle,
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeekRecapBlock(
              weekDays: weekDays,
              onTapArticle: onTapArticle ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final day1 = DateTime(2026, 5, 27);
  final day2 = DateTime(2026, 5, 26);

  testWidgets('N en-têtes de jour + N·m lignes d\'article', (tester) async {
    await pumpBlock(tester, weekDays: [
      EditionDayGroup(date: day1, articles: [_article('a'), _article('b')]),
      EditionDayGroup(date: day2, articles: [_article('c')]),
    ]);

    // Un en-tête par jour (date longue FR).
    expect(find.text(formatFrenchLongDate(day1)), findsOneWidget);
    expect(find.text(formatFrenchLongDate(day2)), findsOneWidget);
    // Compteurs (pluriel/singulier).
    expect(find.text('2 articles'), findsOneWidget);
    expect(find.text('1 article'), findsOneWidget);
    // Une ligne par article (3 au total).
    expect(find.text('Titre a'), findsOneWidget);
    expect(find.text('Titre b'), findsOneWidget);
    expect(find.text('Titre c'), findsOneWidget);
  });

  testWidgets('tap d\'un article → onTapArticle(article)', (tester) async {
    EssentielArticle? tapped;
    await pumpBlock(
      tester,
      weekDays: [
        EditionDayGroup(date: day1, articles: [_article('a'), _article('b')]),
      ],
      onTapArticle: (a) => tapped = a,
    );

    await tester.tap(find.text('Titre b'));
    await tester.pump();
    expect(tapped?.contentId, 'b');
  });

  testWidgets('weekDays vide → rien (SizedBox.shrink)', (tester) async {
    await pumpBlock(tester, weekDays: const []);
    expect(find.byType(WeekRecapBlock), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });
}
