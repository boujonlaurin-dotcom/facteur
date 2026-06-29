import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/selected_edition_date_provider.dart';
import '../utils/morning_ritual_format.dart';

/// EPIC « Lettre du jour » — strip horizontal de pills au-dessus du bloc
/// Essentiel. Tap pour remplacer l'actu du jour par une lettre passée (jusqu'à
/// J-7) ou la rétro « Cette semaine ». Le swipe ±1 jour est reporté après le MVP.
///
/// Réutilise le **langage visuel** du `_Pill` de `time_slot_selector.dart`
/// (Material + InkWell, bord accent + fond teinté à la sélection), réimplémenté
/// ici en variante **compacte** (une ligne, label seul).
class EditionDateStrip extends ConsumerWidget {
  const EditionDateStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedEditionDateProvider);
    final pills = editionPillModel();
    final colors = context.facteurColors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space2,
      ),
      child: Row(
        children: [
          for (var i = 0; i < pills.length; i++) ...[
            if (i > 0) const SizedBox(width: FacteurSpacing.space2),
            _EditionPill(
              label: editionPillLabel(pills[i]),
              selected: pills[i] == selected,
              // Seule « Cette semaine » porte l'accent Essentiel (décision PO) ;
              // les autres pills utilisent l'accent primaire neutre.
              accent: pills[i] is EditionWeek
                  ? colors.sectionEssentiel
                  : colors.primary,
              onTap: () {
                if (pills[i] == selected) return;
                HapticFeedback.selectionClick();
                ref.read(selectedEditionDateProvider.notifier).state = pills[i];
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Libellé d'une pill : « Cette semaine » / « Aujourd'hui » / « Hier » /
/// « mar. 24 ». Pur et testable ; `now` injectable.
String editionPillLabel(EditionSelection selection, {DateTime? now}) {
  switch (selection) {
    case EditionWeek():
      return 'Cette semaine';
    case EditionToday():
      return 'Aujourd’hui';
    case EditionPastDay(:final date):
      final today = editionTodayDate(now: now);
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      if (editionDayKey(date) == editionDayKey(yesterday)) return 'Hier';
      return formatFrenchShortWeekdayDay(date);
  }
}

class _EditionPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _EditionPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: FacteurSpacing.space2,
            horizontal: FacteurSpacing.space4,
          ),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : colors.surface,
            border: Border.all(
              color: selected ? accent : colors.surfaceElevated,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
          ),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
