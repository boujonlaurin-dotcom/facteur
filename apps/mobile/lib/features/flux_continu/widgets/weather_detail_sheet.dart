import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/weather_snapshot.dart';
import '../providers/weather_location_provider.dart';
import '../providers/weather_provider.dart';
import 'weather_condition_icon.dart';

/// Ouvre la modal météo détaillée (aujourd'hui + prévision 5 jours).
Future<void> showWeatherDetailSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _WeatherDetailSheet(),
  );
}

const List<String> _kWeekdaysShort = [
  'Lun',
  'Mar',
  'Mer',
  'Jeu',
  'Ven',
  'Sam',
  'Dim',
];

const List<String> _kWeekdaysFull = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

const List<String> _kMonthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _weekdayShort(DateTime d) => _kWeekdaysShort[d.weekday - 1];
String _weekdayFull(DateTime d) => _kWeekdaysFull[d.weekday - 1];

String weatherIntroLine(WeatherForecast forecast) {
  final min = forecast.minC;
  final max = forecast.maxC;

  if (max >= 35) {
    return 'Canicule en vue, mieux vaut garder le rythme léger.';
  }
  if (max >= 30) {
    return 'Très chaud aujourd\'hui, pense à chercher l\'ombre.';
  }
  if (max <= 2) {
    return 'Froid vif au programme, la journée demande une couche de plus.';
  }
  if (min <= 0) {
    return 'Matinée glaciale, même si la journée peut s\'adoucir.';
  }

  switch (forecast.condition) {
    case WeatherCondition.sunny:
      if (max <= 9) {
        return 'Beau soleil, mais l\'air reste frais.';
      }
      if (max >= 26) {
        return 'Grand soleil, à savourer plutôt côté fraîcheur.';
      }
      return 'Grand soleil, la journée s\'annonce lumineuse.';
    case WeatherCondition.partlyCloudy:
      if (max >= 22) {
        return 'Éclaircies et douceur, météo facile à vivre.';
      }
      if (max <= 10) {
        return 'Quelques éclaircies, avec un fond d\'air encore frais.';
      }
      return 'Quelques éclaircies devraient rythmer la journée.';
    case WeatherCondition.cloudy:
      if (max >= 19) {
        return 'Ciel couvert mais redoux sensible aujourd\'hui.';
      }
      if (max <= 9) {
        return 'Ciel gris et air frais, ambiance calme aujourd\'hui.';
      }
      return 'Ciel couvert, une journée discrète côté météo.';
    case WeatherCondition.rainy:
      if (max <= 8) {
        return 'Pluie froide aujourd\'hui, mieux vaut sortir couvert.';
      }
      if (max >= 22) {
        return 'Averses possibles malgré la douceur, garde un oeil au ciel.';
      }
      return 'Journée humide, le parapluie mérite sa place.';
    case WeatherCondition.snowy:
      if (max <= 1) {
        return 'Neige et froid installés, ambiance très hivernale.';
      }
      return 'Quelques flocons possibles, avec une météo bien fraîche.';
  }
}

class _WeatherDetailSheet extends ConsumerWidget {
  const _WeatherDetailSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final location = ref.watch(weatherLocationProvider);
    final weather = ref.watch(weatherProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.backgroundPrimary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    FacteurSpacing.space6,
                    FacteurSpacing.space4,
                    FacteurSpacing.space6,
                    FacteurSpacing.space8,
                  ),
                  child: weather.when(
                    data: (forecast) => _Content(
                      forecast: forecast,
                      locationLabel: location.label,
                      isDeviceLocation: location.isDeviceLocation,
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, __) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'Météo indisponible pour le moment.',
                          style: FacteurTypography.bodyMedium(
                            colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Content extends ConsumerWidget {
  final WeatherForecast forecast;
  final String locationLabel;
  final bool isDeviceLocation;

  const _Content({
    required this.forecast,
    required this.locationLabel,
    required this.isDeviceLocation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête : libellé localisation + date du jour.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locationLabel,
                    style: FacteurTypography.serifTitle(colors.textPrimary)
                        .copyWith(fontSize: 24, height: 1.15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_weekdayShort(now)} ${now.day} '
                    '${_kMonthsShort[now.month - 1]}',
                    style: FacteurTypography.bodySmall(colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: FacteurSpacing.space4),

        // Bloc « aujourd'hui ».
        Container(
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.border, width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  WeatherConditionIcon(condition: forecast.condition, size: 84),
                  const SizedBox(width: FacteurSpacing.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${forecast.currentC}°',
                          style: GoogleFonts.fraunces(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ressenti ${forecast.feelsLikeC}°',
                          style:
                              FacteurTypography.bodySmall(colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _TempRange(
                    minC: forecast.minC,
                    maxC: forecast.maxC,
                    fontSize: 17,
                  ),
                ],
              ),
              const SizedBox(height: FacteurSpacing.space3),
              Text(
                weatherIntroLine(forecast),
                style: FacteurTypography.bodySmall(colors.textSecondary)
                    .copyWith(height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),

        // Prévision 5 jours.
        Text(
          'Prévisions',
          style: FacteurTypography.labelLarge(colors.textSecondary),
        ),
        const SizedBox(height: FacteurSpacing.space2),
        for (var i = 0; i < forecast.days.length; i++) ...[
          _DayRow(day: forecast.days[i], isToday: i == 0),
          if (i < forecast.days.length - 1)
            Divider(height: 1, color: colors.border.withValues(alpha: 0.4)),
        ],

        if (!isDeviceLocation) ...[
          const SizedBox(height: FacteurSpacing.space4),
          _ActivateLocationCta(
            onTap: () async {
              final granted = await ref
                  .read(weatherLocationProvider.notifier)
                  .useDeviceLocation();
              if (granted && context.mounted) {
                await Navigator.of(context).maybePop();
              }
            },
          ),
        ],
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final WeatherDay day;
  final bool isToday;

  const _DayRow({required this.day, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space3),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              isToday ? "Aujourd'hui" : _weekdayFull(day.date),
              style: FacteurTypography.bodyMedium(colors.textPrimary).copyWith(
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          WeatherConditionIcon(condition: day.condition, size: 76),
          const Spacer(),
          // Max en gros (WeatherDay n'expose pas de temp « actuelle »), avec la
          // plage min/max conservée dessous (décision PO : « quitte à dupliquer
          // le max »). Calque du « 40° » de la carte du jour, en plus petit.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${day.maxC}°',
                style: GoogleFonts.fraunces(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              _TempRange(minC: day.minC, maxC: day.maxC, fontSize: 14),
            ],
          ),
        ],
      ),
    );
  }
}

/// Affiche « min° / max° » en chiffres monospace (bleu / gris / rouge),
/// partagé entre le bloc du jour et chaque ligne de prévision.
class _TempRange extends StatelessWidget {
  final int minC;
  final int maxC;
  final double fontSize;

  const _TempRange({
    required this.minC,
    required this.maxC,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return RichText(
      text: TextSpan(
        style: GoogleFonts.courierPrime(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: '$minC°', style: TextStyle(color: colors.info)),
          TextSpan(text: ' / ', style: TextStyle(color: colors.textSecondary)),
          TextSpan(text: '$maxC°', style: TextStyle(color: colors.error)),
        ],
      ),
    );
  }
}

class _ActivateLocationCta extends StatelessWidget {
  final VoidCallback onTap;

  const _ActivateLocationCta({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: colors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(FacteurRadius.medium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Icon(Icons.my_location_rounded, size: 18, color: colors.primary),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Text(
                  'Activer ma position',
                  style: FacteurTypography.bodyMedium(colors.primary)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
