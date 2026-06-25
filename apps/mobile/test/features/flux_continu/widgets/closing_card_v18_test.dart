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
    testWidgets('renders the heading without a recap description',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tu es à jour'), findsOneWidget);
      // La ligne de récap « Tu as lu… » a été retirée.
      expect(find.textContaining('Tu as lu'), findsNothing);
      expect(find.textContaining('étape'), findsNothing);
    });

    testWidgets('always shows three activity prompts under the amorce',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ClosingCardV18(),
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
        const ClosingCardV18(),
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
