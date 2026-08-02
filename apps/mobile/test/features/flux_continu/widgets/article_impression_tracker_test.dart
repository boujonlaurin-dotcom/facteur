import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/flux_continu/widgets/article_impression_tracker.dart';

/// Enregistre les impressions au lieu de les poster. `super.disabled()` :
/// aucune dépendance réseau ni SharedPreferences dans ce test — on mesure le
/// **déclencheur** (seuil de visibilité), pas la dédup (couverte par
/// `analytics_service_impressions_test.dart`).
class _RecordingAnalytics extends AnalyticsService {
  _RecordingAnalytics() : super.disabled();

  final List<Map<String, Object?>> impressions = [];

  @override
  Future<void> trackArticleImpression({
    required String contentId,
    required String sectionKey,
    required String sectionFamily,
    required String surface,
    required String dayKey,
    required int sectionIndex,
    required int positionInSection,
    required int globalPosition,
    double? scoreTotal,
    double? blockScore,
    String? theme,
    String? sourceId,
    bool isSerene = false,
    bool underfilled = false,
  }) async {
    impressions.add({
      'content_id': contentId,
      'section_key': sectionKey,
      'day_key': dayKey,
      'position_in_section': positionInSection,
      'global_position': globalPosition,
      'score_total': scoreTotal,
    });
  }
}

/// Hauteur du viewport de test (défaut `flutter_test`).
const double _viewportHeight = 600;

/// Hauteur de la carte suivie — la fraction visible se lit directement en
/// pixels : 100 px visibles sur 200 = 50 %.
const double _cardHeight = 200;

void main() {
  late _RecordingAnalytics analytics;
  late ScrollController controller;

  setUp(() {
    // Sans intervalle nul, le timer interne du VisibilityDetector reste pendant
    // au teardown et le test échoue sur un timer non purgé.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    analytics = _RecordingAnalytics();
    controller = ScrollController();
  });

  tearDown(() => controller.dispose());

  /// Pose la carte suivie sous le pli : à l'offset 0 elle est hors écran, et
  /// `jumpTo(n)` la fait entrer de `n` pixels.
  Future<void> pumpTracked(
    WidgetTester tester, {
    ArticleImpressionInfo? info,
    bool mounted = true,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [analyticsServiceProvider.overrideWithValue(analytics)],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                const SizedBox(height: _viewportHeight),
                if (mounted)
                  SizedBox(
                    height: _cardHeight,
                    child: ArticleImpressionTracker(
                      dayKey: '2026-08-02',
                      info: info ??
                          const ArticleImpressionInfo(
                            contentId: 'content-1',
                            sectionKey: 'theme:politique',
                            sectionFamily: 'theme',
                            surface: 'tournee',
                            sectionIndex: 2,
                            positionInSection: 1,
                            globalPosition: 7,
                            scoreTotal: 61.5,
                          ),
                      child: const Text('carte'),
                    ),
                  ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('une carte sous le pli ne compte aucune impression',
      (tester) async {
    await pumpTracked(tester);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(analytics.impressions, isEmpty);
  });

  testWidgets('une carte visible à 25 % ne compte pas, même après 3 s',
      (tester) async {
    await pumpTracked(tester);
    controller.jumpTo(50); // 50 px sur 200 = 25 %
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(analytics.impressions, isEmpty);
  });

  testWidgets('50 % pendant 1 s compte exactement une impression',
      (tester) async {
    await pumpTracked(tester);
    controller.jumpTo(100); // 100 px sur 200 = 50 %
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 999));
    expect(
      analytics.impressions,
      isEmpty,
      reason: 'le seuil de durée est 1 s, pas 999 ms',
    );

    await tester.pump(const Duration(milliseconds: 2));
    expect(analytics.impressions, hasLength(1));
    expect(analytics.impressions.single['content_id'], 'content-1');
    expect(analytics.impressions.single['section_key'], 'theme:politique');
    expect(analytics.impressions.single['global_position'], 7);
    expect(analytics.impressions.single['score_total'], 61.5);
  });

  testWidgets('un scroll rapide qui traverse la carte ne compte rien',
      (tester) async {
    await pumpTracked(tester);
    controller.jumpTo(150); // pleinement visible
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    controller.jumpTo(0); // repartie sous le pli avant le seuil de durée
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(analytics.impressions, isEmpty);
  });

  testWidgets('rester visible plus longtemps ne compte pas deux fois',
      (tester) async {
    await pumpTracked(tester);
    controller.jumpTo(150);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(analytics.impressions, hasLength(1));

    // Aller-retour au-dessus/en-dessous du seuil : la carte a déjà été comptée.
    controller.jumpTo(0);
    await tester.pump();
    controller.jumpTo(150);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(analytics.impressions, hasLength(1));
  });

  testWidgets('démonter la carte avant le seuil ne laisse aucun timer pendant',
      (tester) async {
    await pumpTracked(tester);
    controller.jumpTo(150);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Retire la carte de l'arbre : le timer de dwell est encore armé.
    await pumpTracked(tester, mounted: false);
    await tester.pump(const Duration(seconds: 3));

    expect(analytics.impressions, isEmpty);
    // Le test échouerait au teardown sur un timer non annulé.
  });
}
