import 'package:flutter/material.dart';

/// Map des descriptions courtes pour chaque filtre (1 ligne max)
const Map<String, String> filterDescriptions = {
  'breaking': 'Les actus de moins de 12h',
  'inspiration': 'Loin des sujets chauds',
  'deep_dive': 'Contenus de plus de 10 min',
  // 'perspectives' est dynamique, géré séparément
};

/// Descriptions dynamiques pour le filtre "perspectives" selon le biais utilisateur
String getPerspectivesDescription(String? userBias) {
  switch (userBias) {
    case 'left':
    case 'center-left':
      return 'Des voix plus à droite de votre ligne';
    case 'right':
    case 'center-right':
      return 'Des voix plus à gauche de votre ligne';
    default:
      return 'Des voix alternatives et variées';
  }
}

class FilterBar extends StatelessWidget {
  final String? selectedFilter;
  final ValueChanged<String?> onFilterChanged;
  final String? userBias; // Pour la description dynamique de "perspectives"

  const FilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.userBias,
  });

  String? get _currentDescription {
    if (selectedFilter == null) return null;
    if (selectedFilter == 'perspectives') {
      return getPerspectivesDescription(userBias);
    }
    return filterDescriptions[selectedFilter];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chips scrollables
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildFilterChip(context, 'Dernières news', 'breaking'),
              const SizedBox(width: 8),
              _buildFilterChip(context, 'Rester serein', 'inspiration'),
              const SizedBox(width: 8),
              _buildFilterChip(context, 'Mes angles morts', 'perspectives'),
              const SizedBox(width: 8),
              _buildFilterChip(context, 'Longs formats', 'deep_dive'),
            ],
          ),
        ),
        // Description animée (fade-in/out)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _currentDescription != null ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: _currentDescription != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      _currentDescription!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
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
    const unselectedBg = Colors.transparent;
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
