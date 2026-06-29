import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../providers/edition_read_status_provider.dart';
import '../providers/flux_continu_provider.dart';
import '../providers/selected_edition_date_provider.dart';
import '../utils/morning_ritual_format.dart';

/// EPIC « Lettre du jour » — refonte du sélecteur de date en **timeline overlay**.
///
/// Remplace l'ancien strip horizontal de pills : un bouton « rewind » compact
/// dans l'en-tête de la carte Essentiel ([EditionRewindTrigger]) ouvre cette
/// feuille du bas, qui liste les jours avec une pastille **lu / non-lu**
/// (réutilise la feature streaks via [editionReadStatusProvider]).
class EditionTimelineSheet {
  const EditionTimelineSheet._();

  /// Ouvre la feuille. Calqué sur `manage_favorites_sheet.dart` : fond
  /// transparent, `isScrollControlled`, drag activé, scrim **chaud**. On
  /// n'utilise **pas** `useRootNavigator: true` (même raison z-order que la
  /// feuille favoris : rester dans le navigator de branche).
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      // Scrim chaud (≈ rgba(36,28,18,.42)) plutôt que le noir 0.5.
      barrierColor: const Color(0x6B241C12),
      builder: (_) => const _EditionTimelineContent(),
    );
  }
}

class _EditionTimelineContent extends ConsumerWidget {
  const _EditionTimelineContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final selected = ref.watch(selectedEditionDateProvider);
    final status = ref.watch(editionReadStatusProvider);

    // Compte d'articles d'« Aujourd'hui » s'il est déjà connu (0 réseau : lu
    // depuis le flux préchargé). Omis pour les autres jours afin d'éviter un
    // fetch prématuré (décision plan §1).
    final sections = ref.watch(fluxContinuProvider).valueOrNull?.sections ??
        const <FluxSection>[];
    final todayCount =
        sections.whereType<EssentielSection>().expand((s) => s.articles).length;

    // Ordre d'affichage (le modèle reste inchangé) :
    // Aujourd'hui, Hier, J-2 … J-7, puis « Cette semaine » en dernier.
    final model = editionPillModel();
    final ordered = <EditionSelection>[
      const EditionToday(),
      ...model.whereType<EditionPastDay>(),
      const EditionWeek(),
    ];

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            // Poignée 38×4.
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.rewind(PhosphorIconsStyle.fill),
                        size: 22,
                        color: colors.primary,
                      ),
                      const SizedBox(width: FacteurSpacing.space2),
                      Text(
                        'Remonter le temps',
                        style: GoogleFonts.fraunces(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Rien raté : rattrape les jours précédents quand tu veux, '
                    'à ton rythme.',
                    style: FacteurTypography.bodySmall(colors.textSecondary)
                        .copyWith(height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space3,
                  0,
                  FacteurSpacing.space3,
                  FacteurSpacing.space4,
                ),
                itemCount: ordered.length,
                itemBuilder: (context, i) {
                  final selection = ordered[i];
                  return _DayRow(
                    selection: selection,
                    active: selection == selected,
                    meta: _metaFor(selection, todayCount: todayCount),
                    // Pas de statut quand streaks indisponible (dégradation).
                    statusAvailable: status.available,
                    read: status.available && status.isEditionRead(selection),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(selectedEditionDateProvider.notifier)
                          .state = selection;
                      Navigator.of(context).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Méta secondaire d'une ligne : date longue (jour / today), ou libellé de
  /// fenêtre pour la rétro hebdo. Le compte d'articles n'est ajouté que pour
  /// « Aujourd'hui » (seul cas où il est connu sans fetch).
  String _metaFor(EditionSelection selection, {required int todayCount}) {
    switch (selection) {
      case EditionToday():
        final date = formatFrenchLongDate(editionTodayDate());
        if (todayCount > 0) {
          return '$date · $todayCount article${todayCount > 1 ? 's' : ''}';
        }
        return date;
      case EditionPastDay(:final date):
        return formatFrenchLongDate(date);
      case EditionWeek():
        return 'Les 7 derniers jours';
    }
  }
}

/// Une ligne de jour dans la timeline. [active] surligne la sélection courante ;
/// [statusAvailable] gouverne l'affichage de la pastille lu/non-lu.
class _DayRow extends StatelessWidget {
  final EditionSelection selection;
  final bool active;
  final String meta;
  final bool statusAvailable;
  final bool read;
  final VoidCallback onTap;

  const _DayRow({
    required this.selection,
    required this.active,
    required this.meta,
    required this.statusAvailable,
    required this.read,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final accent = selection is EditionWeek
        ? colors.sectionEssentiel
        : colors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: FacteurSpacing.space2,
          ),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            border: active
                ? Border.all(color: colors.primary, width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(selection), size: 19, color: accent),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      editionPillLabel(selection),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FacteurTypography.labelSmall(colors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (statusAvailable) ...[
                const SizedBox(width: FacteurSpacing.space2),
                _ReadStatusPill(read: read),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(EditionSelection selection) {
    return switch (selection) {
      EditionToday() => PhosphorIcons.sun(PhosphorIconsStyle.fill),
      EditionWeek() => PhosphorIcons.calendarBlank(PhosphorIconsStyle.bold),
      EditionPastDay() =>
        PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.bold),
    };
  }
}

/// Pastille lu / non-lu (anti-FOMO). Non-lu = disque plein ocre + halo +
/// « Non lu » (ocre) ; à jour = coche verte (motif « read » app-wide) + « À
/// jour » (vert success).
class _ReadStatusPill extends StatelessWidget {
  final bool read;

  const _ReadStatusPill({required this.read});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final color = read ? colors.success : colors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // État lu : coche verte (même motif que le badge « read » app-wide).
        // (`_ReadCheckBadge` est privé/dupliqué ailleurs → on inline l'icône
        // plutôt que d'introduire un import croisé.)
        if (read)
          Icon(
            PhosphorIcons.check(PhosphorIconsStyle.bold),
            size: 13,
            color: colors.success,
          )
        else
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary,
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        const SizedBox(width: 5),
        Text(
          read ? 'À jour' : 'Non lu',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Déclencheur « rewind » de l'en-tête de la carte Essentiel : ⏪ ocre + libellé
/// du scope courant (sans cadre). Tap → [onTap] (ouvre [EditionTimelineSheet]).
/// Toujours affiché (today **et** passé).
class EditionRewindTrigger extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const EditionRewindTrigger({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(FacteurRadius.full),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.rewind(PhosphorIconsStyle.fill),
                size: 15,
                color: colors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
