import 'package:flutter/material.dart';

/// Map des descriptions courtes pour chaque filtre (1 ligne max)
const Map<String, String> filterDescriptions = {
  'breaking': 'Les actus chaudes des dernières 12h',
  'inspiration': 'Une pause respiration loin de l\'agitation',
  'deep_dive': 'Des formats longs pour comprendre',
  // 'perspectives' est dynamique, géré séparément
};

/// Descriptions dynamiques pour le filtre "perspectives" selon le biais utilisateur
String getPerspectivesDescription(String? userBias) {
  switch (userBias) {
    case 'left':
    case 'center-left':
      return 'Vos lectures penchent à gauche. Voici de quoi équilibrer.';
    case 'right':
    case 'center-right':
      return 'Vos lectures penchent à droite. Voici de quoi équilibrer.';
    case 'center':
      return 'Vos lectures sont équilibrées. Voici de quoi explorer ailleurs.';
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

  // LayerLinks pour l'alignement précis
  final Map<String, LayerLink> _layerLinks = {
    'breaking': LayerLink(),
    'inspiration': LayerLink(),
    'perspectives': LayerLink(),
    'deep_dive': LayerLink(),
  };

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si le filtre change, on essaye de scroller vers le nouveau filtre
    if (widget.selectedFilter != oldWidget.selectedFilter &&
        widget.selectedFilter != null) {
      // On attend la fin du frame pour que la taille soit correcte
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
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
    _scrollController.dispose();
    super.dispose();
  }

  String? get _currentDescription {
    if (widget.selectedFilter == null) return null;
    if (widget.selectedFilter == 'perspectives') {
      return getPerspectivesDescription(widget.userBias);
    }
    return filterDescriptions[widget.selectedFilter];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Trouver le LayerLink actif
    final activeLink = widget.selectedFilter != null
        ? _layerLinks[widget.selectedFilter]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment
          .start, // Alignement par défaut, le follower gère la position
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
        // Description alignée précisément avec LayerLink
        if (_currentDescription != null && activeLink != null)
          CompositedTransformFollower(
            link: activeLink,
            showWhenUnlinked: false,
            // Ancrage : le centre haut de la description au centre bas du chip
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 8), // Petit espace vertical
            child: Material(
              // Nécessaire car LayerLink sort du contexte normal
              type: MaterialType.transparency,
              child: AnimatedOpacity(
                opacity: _currentDescription != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  // Largeur max contrainte pour éviter débordement écran
                  constraints: BoxConstraints(
                    maxWidth:
                        MediaQuery.of(context).size.width - 32, // Padding écran
                  ),
                  child: Text(
                    _currentDescription!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.5),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          )
        // Espace réservé pour éviter sauts de layout si besoin,
        // ou widget invisible si on veut garder la place prise par l'ancien AnimatedSize
        else
          const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildFilterChip(BuildContext context, String label, String value) {
    final isSelected = widget.selectedFilter == value;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final link = _layerLinks[value]!;

    final selectedBg = colorScheme.primary;
    const unselectedBg = Colors.transparent;
    final selectedText = colorScheme.onPrimary;
    final unselectedText = colorScheme.onSurface.withOpacity(0.5);

    return CompositedTransformTarget(
      link: link,
      child: Padding(
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
      ),
    );
  }
}
