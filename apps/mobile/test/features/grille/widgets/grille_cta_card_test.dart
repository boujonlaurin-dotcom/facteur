import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/grille/widgets/carte_cta.dart';
import 'package:facteur/features/grille/widgets/grille_cta_card.dart';

/// Repository pilotable : `getToday` peut lever ou rendre une partie.
class _FakeGrilleRepository implements GrilleRepository {
  _FakeGrilleRepository({this.error, this.today});

  final Object? error;
  final GrilleTodayResponse? today;

  @override
  Future<GrilleTodayResponse> getToday() async {
    if (error != null) throw error!;
    return today!;
  }

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) async =>
      throw UnimplementedError();

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() async =>
      throw UnimplementedError();
}

GrilleTodayResponse _todayInProgress() => const GrilleTodayResponse(
      date: '2026-05-31',
      dateAffichee: 'Dimanche 31 mai',
      dateCourt: 'Dim. 31 mai',
      numero: 'N°144',
      longueur: 6,
      essaisMax: 6,
      premiereLettre: 'B',
      indice: 'indice',
      theme: 'theme',
      statut: 'in_progress',
      essais: [],
      nbEssais: 0,
      streak: 0,
      prochainMotDansSec: 1000,
    );

Widget _wrap(_FakeGrilleRepository repo) {
  return ProviderScope(
    overrides: [
      grilleRepositoryProvider.overrideWithValue(repo),
      analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(body: GrilleCtaCard()),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'erreur provider (GrilleNotFoundException) → rien rendu, aucun throw',
    (t) async {
      // Régression docs/bugs/bug-grille-du-jour-crash.md : `.value` re-levait
      // l'exception hors de build() → écran gris. `.valueOrNull` doit absorber.
      await t.pumpWidget(
        _wrap(_FakeGrilleRepository(error: const GrilleNotFoundException())),
      );
      await t.pumpAndSettle();

      expect(t.takeException(), isNull,
          reason: 'aucune exception ne doit fuir de build()');
      expect(find.byType(CarteCta), findsNothing);
    },
  );

  testWidgets('loading → rien rendu (SizedBox.shrink)', (t) async {
    await t.pumpWidget(
      _wrap(_FakeGrilleRepository(today: _todayInProgress())),
    );
    // Premier frame : le build() async n'a pas encore résolu → loading.
    await t.pump();
    expect(find.byType(CarteCta), findsNothing);
  });

  testWidgets('data (partie neuve) → la carte CTA est rendue', (t) async {
    await t.pumpWidget(
      _wrap(_FakeGrilleRepository(today: _todayInProgress())),
    );
    await t.pumpAndSettle();
    expect(find.byType(CarteCta), findsOneWidget);
  });
}
