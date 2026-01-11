import 'package:flutter/material.dart';

class FilterBar extends StatelessWidget {
  final String? selectedFilter;
  final ValueChanged<String?> onFilterChanged;

  const FilterBar({
    Key? key,
    required this.selectedFilter,
    required this.onFilterChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          _buildFilterChip(context, 'Tous', null),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'À lire', 'article'),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'À écouter', 'podcast'),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'À voir', 'youtube'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String? value) {
    final isSelected = selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          onFilterChanged(value);
        } else {
          // Optionnel : Si l'utilisateur décoche le filtre actif, revenir à "Tous" ?
          // Comportement standard : ChoiceChip souvent nécessite une selection.
          // Ici si on clique sur celui déjà sélectionné, on ne fait rien ou on reset ?
          // Si on veut permettre "désélectionner pour revenir à tous", on passerait null.
          if (value != null) {
            onFilterChanged(null);
          }
        }
      },
      selectedColor: colorScheme.primary,
      backgroundColor: colorScheme.surfaceVariant,
      labelStyle: TextStyle(
        color:
            isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      checkmarkColor: colorScheme.onPrimary,
      // Supprimer le checkmark pour un look plus "Tab" si désiré, ou le garder.
      // showCheckmark: false,
    );
  }
}
