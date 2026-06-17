import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/source_theme_filters.dart';

/// Chips horizontales de filtre par thème de source (liste partagée
/// [sourceThemeFilters]). Émet le `key` du thème choisi (null = « Toutes »).
///
/// Partagé entre le catalogue de la page « Ajouter une source »
/// (`CatalogSourcesStrip`) et le catalogue de l'onboarding
/// (`SourceCatalogSection`).
class ThemeFilterChips extends StatelessWidget {
  final String? selectedTheme;
  final ValueChanged<String?> onSelected;

  const ThemeFilterChips({
    super.key,
    required this.selectedTheme,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sourceThemeFilters.map((filter) {
          final selected = selectedTheme == filter.key;
          return Padding(
            padding: const EdgeInsets.only(right: FacteurSpacing.space2),
            child: ChoiceChip(
              label: Text(filter.label),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onSelected(filter.key),
              selectedColor: colors.primary,
              backgroundColor: colors.backgroundSecondary,
              labelStyle: TextStyle(
                color: selected ? colors.surface : colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: selected ? colors.primary : colors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
