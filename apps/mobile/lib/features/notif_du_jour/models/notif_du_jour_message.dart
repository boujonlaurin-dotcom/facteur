import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../flux_continu/providers/geoloc_prompt_provider.dart';
import '../../flux_continu/providers/weather_location_provider.dart';
import '../../flux_continu/widgets/tournee_composer_sheet.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../well_informed/providers/well_informed_prompt_provider.dart';
import '../widgets/well_informed_inline_body.dart';

/// Teinte du carré icône + du CTA d'un message de la file.
enum NotifTint { ocre, green, steel }

/// Un message de la « Notif du jour » : une ligne unique en tête de feed.
///
/// Le modèle porte le rendu (icône, teinte, titre, CTA) et les callbacks de
/// cycle de vie. `onTap`/`onDismissed` reçoivent `ref` pour lire l'état live
/// et muter les providers sans que le widget connaisse chaque feature.
class NotifDuJourMessage {
  final String id;
  final IconData icon;
  final NotifTint tint;
  final String title;

  final String? ctaLabel;
  final bool ctaIsGreen;

  /// Action du tap carte/CTA. Exécutée avant le repli ; la consommation du
  /// jour est gérée par le widget (day store).
  final Future<void> Function(BuildContext context, WidgetRef ref)? onTap;

  /// Effets de bord du dismiss (croix) : avancer les caps existants des
  /// nudges absorbés (renudge/géoloc/well-informed) + tracking.
  final Future<void> Function(WidgetRef ref)? onDismissed;

  /// Rendu custom remplaçant la zone CTA/barre (ex. mini-form NPS).
  /// `consume` replie la carte et consomme le message du jour.
  final Widget Function(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() consume,
  )? customBodyBuilder;

  const NotifDuJourMessage({
    required this.id,
    required this.icon,
    required this.tint,
    required this.title,
    this.ctaLabel,
    this.ctaIsGreen = false,
    this.onTap,
    this.onDismissed,
    this.customBodyBuilder,
  });
}

/// Ids stables du catalogue (clés de persistance du day store — ne pas
/// renommer sans migration des prefs).
abstract final class NotifDuJourIds {
  static const serein = 'serein';
  static const source = 'source';
  static const tournee = 'tournee';
  static const veille = 'veille';
  static const premium = 'premium';
  static const recommencer = 'recommencer';
  static const notifRenudge = 'notif_renudge';
  static const geoloc = 'geoloc';
  static const wellInformed = 'well_informed';
}

/// Catalogue : construit le message affichable pour un id de la file.
/// Retourne `null` pour un id inconnu (id persisté d'une version passée).
NotifDuJourMessage? buildNotifDuJourMessage(String id) {
  switch (id) {
    case NotifDuJourIds.serein:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.leaf(),
        tint: NotifTint.green,
        title: 'Pas dans le mood pour l\'actu chaude ?',
        ctaLabel: 'Activer le mode Serein',
        ctaIsGreen: true,
        onTap: (context, ref) async {
          // Bascule in-place : pas de navigation, la carte se replie et
          // laisse apparaître le prochain message éligible.
          await ref.read(sereinToggleProvider.notifier).toggle();
        },
      );
    case NotifDuJourIds.source:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.newspaper(),
        tint: NotifTint.ocre,
        title: 'Tes médias préférés manquent à l\'appel ?',
        ctaLabel: 'Ajouter un média',
        onTap: (context, ref) async {
          unawaited(context.pushNamed(RouteNames.addSource));
        },
      );
    case NotifDuJourIds.tournee:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.path(),
        tint: NotifTint.steel,
        title: 'Ton flux ne te ressemble pas encore ?',
        ctaLabel: 'Composer ma Tournée',
        onTap: (context, ref) async {
          await showTourneeComposerSheet(context);
        },
      );
    case NotifDuJourIds.veille:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.binoculars(),
        tint: NotifTint.steel,
        title: 'Du mal à suivre un sujet précis ?',
        ctaLabel: 'Configurer ma veille',
        onTap: (context, ref) async {
          unawaited(context.pushNamed(RouteNames.veilleConfig));
        },
      );
    case NotifDuJourIds.premium:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.crownSimple(),
        tint: NotifTint.ocre,
        title: 'Abonné à un média ? Ajoute-le ici',
        ctaLabel: 'Lier mon abonnement',
        onTap: (context, ref) async {
          // `add=1` auto-ouvre la feuille d'ajout (cf. subscriptions_screen).
          unawaited(
            context.pushNamed(
              RouteNames.subscriptions,
              queryParameters: {'add': '1'},
            ),
          );
        },
      );
    case NotifDuJourIds.recommencer:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.arrowCounterClockwise(),
        tint: NotifTint.steel,
        title: 'Envie de repartir de zéro ?',
        ctaLabel: 'Refaire mon parcours',
        onTap: (context, ref) async {
          ref.read(onboardingProvider.notifier).restartOnboarding();
          unawaited(
            ref.read(authStateProvider.notifier).setNeedsOnboarding(true),
          );
        },
      );
    case NotifDuJourIds.notifRenudge:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.bell(),
        tint: NotifTint.ocre,
        title: 'Ton Facteur peut passer chaque matin',
        ctaLabel: 'Activer la notification',
        onTap: (context, ref) async {
          final notifier = ref.read(notificationsSettingsProvider.notifier);
          await notifier.recordRenudgeShown();
          unawaited(
            ref.read(analyticsServiceProvider).trackRenudgeConfirmed(),
          );
          if (!context.mounted) return;
          await showNotificationActivationModal(
            context,
            ref,
            trigger: ActivationTrigger.renudge,
          );
        },
        onDismissed: (ref) async {
          await ref
              .read(notificationsSettingsProvider.notifier)
              .recordRenudgeShown();
          unawaited(
            ref.read(analyticsServiceProvider).trackRenudgeDismissed(),
          );
        },
      );
    case NotifDuJourIds.geoloc:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.mapPin(),
        tint: NotifTint.steel,
        title: 'La météo de ta ville dans ton édition',
        ctaLabel: 'Activer ma position',
        onTap: (context, ref) async {
          await ref.read(geolocPromptControllerProvider).recordShown();
          final granted = await ref
              .read(weatherLocationProvider.notifier)
              .useDeviceLocation();
          unawaited(
            ref
                .read(analyticsServiceProvider)
                .trackGeolocPromptActivated(granted: granted),
          );
        },
        onDismissed: (ref) async {
          await ref.read(geolocPromptControllerProvider).recordShown();
          unawaited(
            ref.read(analyticsServiceProvider).trackGeolocPromptDismissed(),
          );
        },
      );
    case NotifDuJourIds.wellInformed:
      return NotifDuJourMessage(
        id: id,
        icon: PhosphorIcons.chartBar(),
        tint: NotifTint.steel,
        title: 'Te sens-tu bien informé·e en ce moment ?',
        customBodyBuilder: (context, ref, consume) =>
            WellInformedInlineBody(consume: consume),
        onDismissed: (ref) async {
          await ref.read(wellInformedPromptControllerProvider).skip();
          unawaited(
            ref
                .read(analyticsServiceProvider)
                .trackWellInformedPromptSkipped(context: 'notif_du_jour'),
          );
        },
      );
  }
  return null;
}

/// Pertinence dynamique du message « premium » : plus l'utilisateur suit de
/// sources payantes non liées, plus le message monte.
double premiumRelevance(int eligibleUnlinkedCount) =>
    math.min(1, eligibleUnlinkedCount / 3);

/// Pertinence dynamique du message « source » : 1.0 à 0 source de confiance,
/// décroît jusqu'au seuil de 3.
double sourceRelevance(int trustedCount) =>
    ((3 - trustedCount) / 3).clamp(0.0, 1.0);
