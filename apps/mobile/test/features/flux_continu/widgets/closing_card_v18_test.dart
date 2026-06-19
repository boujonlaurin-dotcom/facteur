import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/providers/weather_location_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_provider.dart';
import 'package:facteur/features/flux_continu/utils/closing_activity.dart';
import 'package:facteur/features/flux_continu/widgets/closing_card_v18.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeWeatherNotifier extends WeatherNotifier {
  _FakeWeatherNotifier(this._value);
  final WeatherForecast _value;
  @override
  Future<WeatherForecast> build() async => _value;
}

class _FakeLocationNotifier extends WeatherLocationNotifier {
  @override
  WeatherLocation build() => WeatherLocation.paris;
}

WeatherForecast _forecast(WeatherCondition condition) => WeatherForecast(
      condition: condition,
      currentC: 19,
      feelsLikeC: 18,
      minC: 12,
      maxC: 21,
      fetchedAt: DateTime(2026, 6, 19),
      days: [
        WeatherDay(
          date: DateTime(2026, 6, 19),
          condition: condition,
          minC: 12,
          maxC: 21,
        ),
      ],
    );

Widget _wrap(
  Widget child, {
  WeatherCondition condition = WeatherCondition.sunny,
}) {
  return ProviderScope(
    overrides: [
      weatherProvider
          .overrideWith(() => _FakeWeatherNotifier(_forecast(condition))),
      weatherLocationProvider.overrideWith(_FakeLocationNotifier.new),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ClosingCardV18', () {
    testWidgets('renders the personalized recap line when provided',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(
          articleCount: 6,
          recapLine: 'Tu as lu sur la Tech (4) et la Politique (2).',
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Tu as lu sur la Tech (4) et la Politique (2).'),
        findsOneWidget,
      );
      // Le fallback « X étapes parcourues » ne doit pas s'afficher.
      expect(find.textContaining('étape'), findsNothing);
    });

    testWidgets('falls back to step label when recapLine is null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(articleCount: 3),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3 étapes parcourues'), findsOneWidget);
    });

    testWidgets('always shows three activity prompts under the amorce',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(articleCount: 0),
        condition: WeatherCondition.sunny,
      ));
      await tester.pumpAndSettle();

      // Le micro-libellé d'amorce est toujours présent.
      expect(find.text('Et si tu en profitais pour…'), findsOneWidget);
      // Trois propositions tournées en question (se terminent par « ? »).
      final prompts = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.endsWith('?') ?? false),
      );
      expect(prompts, findsNWidgets(kClosingActivityCount));
    });

    testWidgets('keeps prompts indoor-only when the weather is poor',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(articleCount: 0),
        condition: WeatherCondition.rainy,
      ));
      await tester.pumpAndSettle();

      // Aucune proposition d'extérieur ne doit apparaître par mauvais temps.
      for (final outdoor in kOutdoorActivities) {
        expect(find.text(outdoor.prompt), findsNothing);
      }
    });
  });
}
