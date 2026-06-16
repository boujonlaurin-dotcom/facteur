import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/geoloc_prompt_provider.dart';
import '../providers/weather_location_provider.dart';

/// Bannière in-feed (format « notif de progression ») proposant d'activer la
/// géolocalisation pour afficher la météo de la ville de l'utilisateur.
///
/// Miroir de `NotificationRenudgeBanner` : un seul nudge par session
/// (anti-stacking via `nudgeConsumedThisSessionProvider`), cap dur persisté en
/// Hive (`geoloc_prompt_shown_count`), dismiss de session sur « Pas maintenant ».
class GeolocPromptBanner extends ConsumerStatefulWidget {
  const GeolocPromptBanner({super.key});

  @override
  ConsumerState<GeolocPromptBanner> createState() => _GeolocPromptBannerState();
}

class _GeolocPromptBannerState extends ConsumerState<GeolocPromptBanner> {
  /// Tracking analytics + incrément du cap au premier affichage.
  bool _recordedShown = false;

  /// Dismiss session-only : tant que l'écran vit, on ne ré-affiche pas après un
  /// « Pas maintenant ». Au cold start suivant, le cap dur prend le relais.
  bool _dismissedThisSession = false;

  Future<void> _onActivate() async {
    final granted =
        await ref.read(weatherLocationProvider.notifier).useDeviceLocation();
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .trackGeolocPromptActivated(granted: granted),
    );
    if (!mounted) return;
    setState(() => _dismissedThisSession = true);
  }

  void _onDismiss() {
    unawaited(ref.read(analyticsServiceProvider).trackGeolocPromptDismissed());
    setState(() => _dismissedThisSession = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) return const SizedBox.shrink();
    final shouldShow =
        ref.watch(geolocPromptShouldShowProvider).valueOrNull ?? false;
    if (!shouldShow) return const SizedBox.shrink();

    if (!_recordedShown) {
      _recordedShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Marque le slot nudge comme consommé pour la session (anti-stacking).
        ref.read(nudgeConsumedThisSessionProvider.notifier).state = true;
        final displayCount =
            await ref.read(geolocPromptControllerProvider).recordShown();
        // Re-garde après l'await : la bannière peut s'être démontée pendant
        // l'écriture Hive (recompose Essentiel / auto-dismiss) → ne jamais
        // toucher `ref` sur un widget disposé (cf. bug-modal-ref-disposed).
        if (!mounted) return;
        unawaited(
          ref
              .read(analyticsServiceProvider)
              .trackGeolocPromptShown(displayCount: displayCount),
        );
      });
    }

    final colors = context.facteurColors;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3,
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  PhosphorIcons.mapPin(PhosphorIconsStyle.fill),
                  color: colors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active ta position pour la météo de ta ville',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'On garde Paris par défaut. Ta position reste sur ton '
                      'appareil.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _onActivate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.medium),
                    ),
                  ),
                  child: const Text('Activer'),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              TextButton(
                onPressed: _onDismiss,
                child: Text(
                  'Pas maintenant',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
