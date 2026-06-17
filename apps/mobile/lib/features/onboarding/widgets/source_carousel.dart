import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../sources/models/source_model.dart';
import '../data/source_recommender.dart';
import 'source_carousel_card.dart';

/// Carrousel horizontal de sources recommandées : un `PageView` de
/// [SourceCarouselCard] à hauteur fixe, `viewportFraction` < 1 pour laisser
/// entrevoir la carte suivante (peek) et inviter au swipe latéral.
///
/// Remplace les longues listes verticales des suggestions / du catalogue dans
/// la page « Tes médias, sur mesure » : plus lisible, hiérarchie claire.
class SourceCarousel extends StatefulWidget {
  final List<RecommendedSource> sources;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<Source> onInfoTap;

  /// Affiche les tags/raison de match sur chaque carte (faux pour le catalogue).
  final bool showReason;

  /// Hauteur fixe du carrousel (cartes bornées et lisibles).
  final double height;

  const SourceCarousel({
    super.key,
    required this.sources,
    required this.selectedIds,
    required this.onToggle,
    required this.onInfoTap,
    this.showReason = true,
    this.height = 188,
  });

  @override
  State<SourceCarousel> createState() => _SourceCarouselState();
}

class _SourceCarouselState extends State<SourceCarousel> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    // ~1,2 carte visible : la suivante dépasse (peek) pour signaler le swipe.
    _controller = PageController(viewportFraction: 0.82);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sources.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _controller,
        padEnds: false,
        itemCount: widget.sources.length,
        itemBuilder: (context, index) {
          final r = widget.sources[index];
          return Padding(
            padding: const EdgeInsets.only(right: FacteurSpacing.space3),
            child: SourceCarouselCard(
              recommendation: r,
              isSelected: widget.selectedIds.contains(r.source.id),
              onToggle: () => widget.onToggle(r.source.id),
              onInfoTap: () => widget.onInfoTap(r.source),
              showReason: widget.showReason,
            ),
          );
        },
      ),
    );
  }
}
