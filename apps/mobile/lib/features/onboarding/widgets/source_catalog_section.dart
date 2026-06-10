import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../sources/models/source_model.dart';
import '../data/source_recommender.dart';
import '../onboarding_strings.dart';
import '../widgets/source_recommendation_card.dart';

/// Catalogue complet des sources groupé par thème, avec recherche.
///
/// Replié par défaut derrière un en-tête « Voir tout le catalogue » ;
/// extrait de l'ancienne page 2 des sources pour être partagé entre les
/// deux variantes de la page sources adaptative.
class SourceCatalogSection extends StatefulWidget {
  final List<RecommendedSource> catalog;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;
  final ValueChanged<Source> onInfoTap;
  final bool initiallyExpanded;

  const SourceCatalogSection({
    super.key,
    required this.catalog,
    required this.selectedIds,
    required this.onToggle,
    required this.onInfoTap,
    this.initiallyExpanded = false,
  });

  @override
  State<SourceCatalogSection> createState() => _SourceCatalogSectionState();
}

class _SourceCatalogSectionState extends State<SourceCatalogSection> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late bool _expanded = widget.initiallyExpanded;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RecommendedSource> get _filteredCatalog {
    if (_searchQuery.isEmpty) return widget.catalog;
    final query = _searchQuery.toLowerCase();
    return widget.catalog
        .where((r) => r.source.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (widget.catalog.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context, colors),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: FacteurSpacing.space3),
                    _buildSearchField(colors),
                    ..._buildCatalogueByTheme(context),
                    if (_searchQuery.isNotEmpty && _filteredCatalog.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: FacteurSpacing.space4,
                        ),
                        child: Text(
                          OnboardingStrings.q9NoMatch,
                          style: TextStyle(color: colors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, FacteurColors colors) {
    return Semantics(
      button: true,
      expanded: _expanded,
      label: OnboardingStrings.sourcesSeeAllCatalog,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space2,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.books(),
                size: 20,
                color: colors.textSecondary,
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Text(
                  OnboardingStrings.sourcesSeeAllCatalog,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  PhosphorIcons.caretDown(),
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: OnboardingStrings.q9SearchHint,
          prefixIcon: Icon(Icons.search, color: colors.textSecondary),
          filled: true,
          fillColor: colors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FacteurRadius.full),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: colors.textSecondary),
        ),
        style: TextStyle(color: colors.textPrimary),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  /// Catalogue groupé par thème avec mini-headers.
  List<Widget> _buildCatalogueByTheme(BuildContext context) {
    final colors = context.facteurColors;
    final filtered = _filteredCatalog;

    final grouped = <String, List<RecommendedSource>>{};
    for (final r in filtered) {
      final theme = r.source.theme ?? 'other';
      grouped.putIfAbsent(theme, () => []).add(r);
    }

    final sortedThemes = grouped.keys.toList()
      ..sort((a, b) {
        final macroA = getTopicMacroTheme(a);
        final macroB = getTopicMacroTheme(b);
        final idxA = macroA != null ? macroThemeOrder.indexOf(macroA) : 999;
        final idxB = macroB != null ? macroThemeOrder.indexOf(macroB) : 999;
        return idxA.compareTo(idxB);
      });

    final widgets = <Widget>[];
    for (final themeSlug in sortedThemes) {
      final sources = grouped[themeSlug]!;
      final macroTheme = getTopicMacroTheme(themeSlug);
      final label = macroTheme ?? getTopicLabel(themeSlug);
      final emoji = macroTheme != null ? getMacroThemeEmoji(macroTheme) : '';

      widgets.add(Padding(
        padding: const EdgeInsets.only(
          top: FacteurSpacing.space4,
          bottom: FacteurSpacing.space2,
        ),
        child: Text(
          '$emoji $label (${sources.length})',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ));

      for (final r in sources) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
          child: SourceRecommendationCard(
            recommendation: r,
            isSelected: widget.selectedIds.contains(r.source.id),
            onToggle: () => widget.onToggle(r.source.id),
            onInfoTap: () => widget.onInfoTap(r.source),
            showReason: false,
          ),
        ));
      }
    }

    return widgets;
  }
}
