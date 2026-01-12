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
          _buildFilterChip(context, "Dernières news", 'breaking'),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'Rester serein', 'inspiration'),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'Mes angles morts', 'perspectives'),
          const SizedBox(width: 8),
          _buildFilterChip(context, 'Longs formats', 'deep_dive'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String? value) {
    final isSelected = selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Design System Alignment:
    // Selected: Primary Orange (Highly visible)
    // Unselected: "Ghost" state (Low-opacity text, no background/border)
    final selectedBg = colorScheme.primary;
    final unselectedBg = Colors.transparent;
    final selectedText = colorScheme.onPrimary;
    final unselectedText = colorScheme.onSurface.withOpacity(0.5);

    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? selectedText : unselectedText,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 14,
        ),
      ),
      selected: isSelected,
      onSelected: (bool selected) {
        onFilterChanged(selected ? value : null);
      },
      showCheckmark: false,
      selectedColor: selectedBg,
      backgroundColor: unselectedBg,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
