import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/widgets/grille_result_view.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

GrilleTodayResponse _today({
  String? hybridField,
  String? hybridSnippet,
  String? hybridMatch,
  String? featuredExcerpt,
  String? featuredUrl,
  String? featuredSource,
  String? pourquoi = 'phrase de repli',
}) {
  return GrilleTodayResponse(
    date: '2026-06-13',
    dateAffichee: 'Vendredi 13 juin',
    dateCourt: 'Ven. 13 juin',
    numero: 'N°1',
    longueur: 6,
    essaisMax: 6,
    premiereLettre: 'C',
    indice: 'indice',
    theme: 'Environnement',
    statut: 'solved',
    essais: const [
      GrilleEssai(
        mot: 'CLIMAT',
        etats: ['place', 'place', 'place', 'place', 'place', 'place'],
      ),
    ],
    nbEssais: 1,
    mot: 'CLIMAT',
    pourquoi: pourquoi,
    streak: 1,
    prochainMotDansSec: 100,
    hybridField: hybridField,
    hybridSnippet: hybridSnippet,
    hybridMatch: hybridMatch,
    featuredExcerpt: featuredExcerpt,
    featuredUrl: featuredUrl,
    featuredSource: featuredSource,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('hybride : badge titre + snippet + source + lien', (t) async {
    await t.pumpWidget(_wrap(GrilleResultView(
      today: _today(
        hybridField: 'title',
        hybridSnippet: 'Nouvel espoir pour le climat à Belém',
        hybridMatch: 'climat',
        featuredSource: 'Le Monde',
        featuredUrl: 'https://exemple.fr/a',
      ),
    )));
    await t.pumpAndSettle();

    expect(find.text('caché dans le titre'), findsOneWidget);
    expect(find.text('Le Monde'), findsOneWidget);
    expect(find.text('Lire l\'article'), findsOneWidget);
    // Le snippet est rendu (via Text.rich) et la phrase de repli est absente.
    expect(find.textContaining('Belém', findRichText: true), findsOneWidget);
    expect(find.textContaining('phrase de repli'), findsNothing);
  });

  testWidgets('hybride : badge description', (t) async {
    await t.pumpWidget(_wrap(GrilleResultView(
      today: _today(
        hybridField: 'description',
        hybridSnippet: '…le sommet européen s\'achève…',
        hybridMatch: 'sommet',
      ),
    )));
    await t.pumpAndSettle();
    expect(find.text('caché dans la description'), findsOneWidget);
  });

  testWidgets('fallback : pas de hybride → phrase pourquoi', (t) async {
    await t.pumpWidget(_wrap(GrilleResultView(today: _today())));
    await t.pumpAndSettle();
    expect(find.textContaining('phrase de repli'), findsOneWidget);
    expect(find.text('caché dans le titre'), findsNothing);
  });
}
