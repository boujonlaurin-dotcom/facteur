import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../sources/models/source_model.dart';
import '../../sources/widgets/theme_filter_chips.dart';
import '../data/source_recommender.dart';
import '../widgets/source_carousel.dart';

/// Catalogue des médias à parcourir, filtrable par thème via des chips
/// horizontales — reprend le pattern de la feature « Catalogue de sources » de
/// la page « Ajouter une source » (`CatalogSourcesStrip`), adapté aux
/// `RecommendedSource` de l'onboarding.
///
/// Pas de header / repli propre : la section est déjà encapsulée dans un
/// `OnboardingToggleSection` qui porte le toggle.
class SourceCatalogSection extends StatefulWidget {
  final List<RecommendedSource> catalog;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<Source> onInfoTap;

  const SourceCatalogSection({
    super.key,
    required this.catalog,
    required this.selectedIds,
    required this.onToggle,
    required this.onInfoTap,
  });

  @override
  State<SourceCatalogSection> createState() => _SourceCatalogSectionState();
}

class _SourceCatalogSectionState extends State<SourceCatalogSection> {
  String? _selectedTheme;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (widget.catalog.isEmpty) return const SizedBox.shrink();

    final filtered = _selectedTheme == null
        ? widget.catalog
        : widget.catalog
            .where((r) => r.source.theme?.toLowerCase() == _selectedTheme)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThemeFilterChips(
          selectedTheme: _selectedTheme,
          onSelected: (key) => setState(() => _selectedTheme = key),
        ),
        const SizedBox(height: FacteurSpacing.space3),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space2),
            child: Text(
              'Aucun média dans ce thème.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textTertiary),
            ),
          )
        else
          SourceCarousel(
            // Recrée le carrousel (et son PageController) au changement de
            // filtre pour repartir de la 1ère carte du thème.
            key: ValueKey(_selectedTheme),
            sources: filtered,
            selectedIds: widget.selectedIds,
            onToggle: widget.onToggle,
            onInfoTap: widget.onInfoTap,
            showReason: false,
          ),
      ],
    );
  }
}
