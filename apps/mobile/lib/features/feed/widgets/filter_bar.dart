import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
      final parentWidth = parentBox.size.width;
      // Padding du Container parent (16px de chaque côté)
      const containerPadding = 16.0;
      final containerWidth = parentWidth - (2 * containerPadding);
      
      // Pour "breaking" (Dernières news), aligner à gauche
      // Pour les autres, utiliser le centre du chip
      Offset anchorPoint;
      if (widget.selectedFilter == 'breaking') {
        // Utiliser le bord gauche du chip
        anchorPoint = box.localToGlobal(Offset.zero, ancestor: parentBox);
      } else {
        // Utiliser le centre du chip
        anchorPoint = box.localToGlobal(Offset(box.size.width / 2, 0), ancestor: parentBox);
      }

      setState(() {
        // Ajuster pour tenir compte du padding du conteneur
        // Le chip est à anchorPoint.dx du bord gauche de l'écran
        // Le texte doit être à la même position relative au conteneur avec padding
        final relativeX = anchorPoint.dx - containerPadding;
        // Map 0..containerWidth to -1..1 pour l'alignement dans le Container avec padding
        _descriptionAlignX = (relativeX / containerWidth) * 2 - 1;
        // Clamp pour éviter que le texte ne dépasse trop des bords
        // Pour "breaking", on veut être proche de -1 (gauche), donc on clamp moins strictement
        if (widget.selectedFilter == 'breaking') {
          _descriptionAlignX = _descriptionAlignX.clamp(-1.0, 0.85);
        } else {
          _descriptionAlignX = _descriptionAlignX.clamp(-0.85, 0.85);
        }
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

  void _showFilteredKeywords(List<String> keywords) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle de drag
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Contenu scrollable
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          PhosphorIcons.shieldCheck(PhosphorIconsStyle.bold),
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Mots-clés filtrés',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'En mode "Rester serein", Facteur filtre automatiquement les contenus contenant ces mots-clés pour vous offrir une expérience plus apaisée.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: keywords
                          .map((word) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  word,
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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

    final selectedConfig = widget.availableFilters
        ?.where((f) => f.key == widget.selectedFilter)
        .firstOrNull;

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
                    ? GestureDetector(
                        onTap: selectedConfig?.filteredKeywords != null
                            ? () => _showFilteredKeywords(
                                selectedConfig!.filteredKeywords!)
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentDescription!,
                              key: ValueKey(_currentDescription),
                              textAlign: widget.selectedFilter == 'breaking' 
                                  ? TextAlign.left 
                                  : TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color:
                                    colorScheme.onSurface.withValues(alpha: 0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            if (selectedConfig?.filteredKeywords != null) ...[
                              const SizedBox(width: 6),
                              Icon(
                                PhosphorIcons.info(PhosphorIconsStyle.regular),
                                size: 14,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ],
                          ],
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
    final unselectedText = colorScheme.onSurface.withValues(alpha: 0.5);

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
