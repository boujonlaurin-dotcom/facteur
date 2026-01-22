import 'package:flutter/material.dart';
import '../providers/personalized_filters_provider.dart';

/// Map des descriptions courtes pour chaque filtre (Fallback)
const Map<String, String> defaultFilterDescriptions = {
  'breaking': 'Les actus chaudes des dernières 12h',
  'inspiration': 'Sans thèmes anxiogènes (Politique, Géopolitique...)',
  'deep_dive': 'Des formats longs pour comprendre',
};

/// Descriptions dynamiques pour le filtre "perspectives" selon le biais utilisateur
String getPerspectivesDescription(String? userBias) {
  switch (userBias) {
    case 'left':
    case 'center-left':
      return 'Du contenu plus à droite, pour changer de prisme';
    case 'right':
    case 'center-right':
      return 'Du contenu plus à gauche, pour changer de prisme';
    case 'center':
      return 'Du contenu plus varié, pour changer de prisme';
    default:
      return 'Changez d\'angle de vue pour enrichir votre opinion.';
  }
}

class FilterBar extends StatefulWidget {
  final String? selectedFilter;
  final ValueChanged<String?> onFilterChanged;
  final String? userBias; // Pour la description dynamique de "perspectives"
  final List<FilterConfig>? availableFilters;

  const FilterBar({
    super.key,
    required this.selectedFilter,
    required this.onFilterChanged,
    this.userBias,
    this.availableFilters,
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

  double _descriptionAlignX = 0;
  String? _currentDescription;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateAlignment);
    _updateDescription();
  }

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilter != widget.selectedFilter ||
        oldWidget.userBias != widget.userBias) {
      _updateDescription();
      _scrollToSelected();
    }
  }

  void _updateDescription() {
    setState(() {
      if (widget.selectedFilter == null) {
        _currentDescription = null;
        _currentDescription = getPerspectivesDescription(widget.userBias);
      } else {
        // Try to find description in availableFilters
        final config = widget.availableFilters
            ?.where((f) => f.key == widget.selectedFilter)
            .firstOrNull;
        if (config != null) {
          _currentDescription = config.description;
        } else {
          _currentDescription =
              defaultFilterDescriptions[widget.selectedFilter];
        }
      }
    });
    // Attendre le prochain frame pour avoir les positions à jour
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateAlignment());
  }

  void _updateAlignment() {
    if (!mounted || widget.selectedFilter == null) return;

    final key = _keys[widget.selectedFilter];
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final parentBox = context.findRenderObject() as RenderBox?;

    if (box != null && parentBox != null) {
      final chipCenter =
          box.localToGlobal(Offset(box.size.width / 2, 0), ancestor: parentBox);
      final parentWidth = parentBox.size.width;

      setState(() {
        // Map 0..parentWidth to -1..1
        _descriptionAlignX = (chipCenter.dx / parentWidth) * 2 - 1;
        // Clamp pour éviter que le texte ne dépasse trop des bords
        _descriptionAlignX = _descriptionAlignX.clamp(-0.85, 0.85);
      });
    }
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
    _scrollController.removeListener(_updateAlignment);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            children: (widget.availableFilters ?? []).isNotEmpty
                ? widget.availableFilters!
                    .where((f) => f.isVisible)
                    .map((f) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildFilterChip(context, f.label, f.key),
                        ))
                    .toList()
                : [
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
        // Description avec alignement dynamique qui suit le chip (anchor)
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: Container(
            height: _currentDescription != null ? null : 0,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment(_descriptionAlignX, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _currentDescription != null
                    ? Text(
                        _currentDescription!,
                        key: ValueKey(_currentDescription),
                        textAlign: TextAlign.center,
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
        // Suppression de visualDensity compact pour éviter la troncation
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
