import 'package:flutter/material.dart';

/// Map des descriptions courtes pour chaque filtre (1 ligne max)
const Map<String, String> filterDescriptions = {
  'breaking': 'Les actus chaudes des dernières 12h',
  'inspiration': 'Sans thèmes anxiogènes (Politique, Géopolitique...)',
  'deep_dive': 'Des formats longs pour comprendre',
};

/// Descriptions dynamiques pour le filtre "perspectives" selon le biais utilisateur
String getPerspectivesDescription(String? userBias) {
  switch (userBias) {
    case 'left':
    case 'center-left':
      return 'Du contenu à droite, pour changer de prisme (gauche)';
    case 'right':
    case 'center-right':
      return 'Du contenu à gauche, pour changer de prisme (droite)';
    case 'center':
      return 'Du contenu varié, pour changer de prisme (centre)';
    default:
      return 'Changez d\'angle de vue pour enrichir votre opinion.';
  }
}

class FilterBar extends StatefulWidget {
  final String? selectedFilter;
  final ValueChanged<String?> onFilterChanged;
  final String? userBias; // Pour la description dynamique de "perspectives"

  const FilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.userBias,
  });

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _keys = {
    'breaking': GlobalKey(),
    'inspiration': GlobalKey(),
    'perspectives': GlobalKey(),
    'deep_dive': GlobalKey(),
  };

  String? _currentDescription;

  @override
  void initState() {
    super.initState();
    _updateDescription();
  }

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilter != widget.selectedFilter) {
      _updateDescription();
      _scrollToSelected();
    }
  }

  void _updateDescription() {
    setState(() {
      if (widget.selectedFilter == null) {
        _currentDescription = null;
      } else if (widget.selectedFilter == 'perspectives') {
        _currentDescription = getPerspectivesDescription(widget.userBias);
      } else {
        _currentDescription = filterDescriptions[widget.selectedFilter];
      }
    });
  }

  void _scrollToSelected() {
    final key = _keys[widget.selectedFilter];
    if (key?.currentContext == null) return;

    final context = key!.currentContext!;

    // Déterminer l'alignement ciblé :
    // - 0.0 pour le premier item (bord gauche)
    // - 1.0 pour le dernier item (bord droit)
    // - 0.5 pour les items du milieu (centré)
    double alignment = 0.5;
    if (widget.selectedFilter == 'breaking') {
      alignment = 0.0;
    } else if (widget.selectedFilter == 'deep_dive') {
      alignment = 1.0;
    }

    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Calcul de l'alignement strict demandé par l'utilisateur
    Alignment alignment = Alignment.center;
    TextAlign textAlign = TextAlign.center;
    if (widget.selectedFilter == 'breaking') {
      alignment = Alignment.centerLeft;
      textAlign = TextAlign.left;
    } else if (widget.selectedFilter == 'deep_dive') {
      alignment = Alignment.centerRight;
      textAlign = TextAlign.right;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chips scrollables
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              _buildFilterChip(context, 'Dernières news', 'breaking'),
              const SizedBox(width: 8),
              _buildFilterChip(context, 'Rester serein', 'inspiration'),
              const SizedBox(width: 8),
              _buildFilterChip(
                  context, 'Changer de perspective', 'perspectives'),
              const SizedBox(width: 8),
              _buildFilterChip(context, 'Longs formats', 'deep_dive'),
            ],
          ),
        ),
        // Description avec alignement strict (Gauche/Droite/Centre)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            height: _currentDescription != null ? null : 0,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: alignment,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _currentDescription != null
                    ? Text(
                        _currentDescription!,
                        key: ValueKey(_currentDescription),
                        textAlign: textAlign,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    final isSelected = widget.selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectedBg = colorScheme.primary;
    const unselectedBg = Colors.transparent;
    final selectedText = colorScheme.onPrimary;
    final unselectedText = colorScheme.onSurface.withOpacity(0.5);

    return Padding(
      key: _keys[value],
      padding: EdgeInsets.zero,
      child: ChoiceChip(
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
          widget.onFilterChanged(selected ? value : null);
        },
        showCheckmark: false,
        selectedColor: selectedBg,
        backgroundColor: unselectedBg,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
