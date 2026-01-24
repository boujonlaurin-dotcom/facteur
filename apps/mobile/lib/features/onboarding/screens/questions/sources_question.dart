import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../data/theme_to_sources_mapping.dart';
import '../../providers/onboarding_provider.dart';
import '../../onboarding_strings.dart';

/// Q10 : "Vos sources préférées ?" (après thèmes)
/// Sélection de sources fiables depuis la base de données.
/// Les sources sélectionnées seront marquées comme "de confiance".
///
/// Nouvelle fonctionnalité: Pré-sélection automatique basée sur les thèmes choisis.
class SourcesQuestion extends ConsumerStatefulWidget {
  const SourcesQuestion({super.key});

  @override
  ConsumerState<SourcesQuestion> createState() => _SourcesQuestionState();
}

class _SourcesQuestionState extends ConsumerState<SourcesQuestion> {
  Set<String> _selectedSourceIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _hasAppliedPreselection = false;

  @override
  void initState() {
    super.initState();
    // Charger les sources préférées existantes (reprise d'onboarding ou back navigation)
    final existingAnswers = ref.read(onboardingProvider).answers;
    final existingSources = existingAnswers.preferredSources;
    if (existingSources != null && existingSources.isNotEmpty) {
      // L'utilisateur a déjà fait des sélections → les restaurer
      _selectedSourceIds = existingSources.toSet();
      _hasAppliedPreselection = true; // Ne pas écraser avec la pré-sélection
    }

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  /// Applique la pré-sélection automatique basée sur les thèmes choisis
  void _applyPreselection(List<Source> allSources) {
    if (_hasAppliedPreselection) return;
    _hasAppliedPreselection = true;

    final existingAnswers = ref.read(onboardingProvider).answers;
    final selectedThemes = existingAnswers.themes ?? [];
    final selectedSubtopics = existingAnswers.subtopics ?? [];

    if (selectedThemes.isEmpty) return;

    // Calculer les noms de sources recommandées
    final recommendedNames = ThemeToSourcesMapping.computeRecommendedSources(
      selectedThemes: selectedThemes,
      selectedSubtopics: selectedSubtopics,
    );

    // Convertir les noms en IDs
    final recommendedIds = _convertSourceNamesToIds(
      recommendedNames.toList(),
      allSources,
    );

    if (recommendedIds.isNotEmpty) {
      setState(() {
        _selectedSourceIds = recommendedIds;
      });
    }
  }

  /// Convertit les noms de sources en IDs UUID
  Set<String> _convertSourceNamesToIds(
    List<String> sourceNames,
    List<Source> allSources,
  ) {
    final Set<String> ids = {};

    for (final name in sourceNames) {
      final source = allSources.cast<Source?>().firstWhere(
            (s) => s?.name.toLowerCase() == name.toLowerCase(),
            orElse: () => null,
          );
      if (source != null) {
        ids.add(source.id);
      }
    }

    return ids;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSource(String sourceId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedSourceIds.contains(sourceId)) {
        _selectedSourceIds.remove(sourceId);
      } else {
        _selectedSourceIds.add(sourceId);
      }
    });
  }

  void _continue() {
    // Sauvegarder les IDs des sources sélectionnées
    ref
        .read(onboardingProvider.notifier)
        .selectSources(_selectedSourceIds.toList());
  }

  /// Vérifie si des thèmes ont été sélectionnés (pour afficher le message)
  bool get _hasSelectedThemes {
    final existingAnswers = ref.read(onboardingProvider).answers;
    final selectedThemes = existingAnswers.themes ?? [];
    return selectedThemes.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),

          // Titre
          Text(
            OnboardingStrings.q9Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.q9Subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Message de pré-sélection (si des thèmes ont été sélectionnés)
          if (_hasSelectedThemes && _selectedSourceIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4,
                vertical: FacteurSpacing.space3,
              ),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    OnboardingStrings.q9PreselectionTitle,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    OnboardingStrings.q9PreselectionSubtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          const SizedBox(height: FacteurSpacing.space4),

          // Barre de recherche
          TextField(
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

          const SizedBox(height: FacteurSpacing.space4),

          // Chips de sources
          Expanded(
            child: sourcesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  OnboardingStrings.q9LoadingError,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
              data: (sources) {
                // Appliquer la pré-sélection automatique (une seule fois)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _applyPreselection(sources);
                });

                // Filtrer pour n'afficher que les sources curées
                var filteredSources =
                    sources.where((s) => s.isCurated).toList();

                // Trier par ordre alphabétique
                filteredSources.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

                // Appliquer la recherche
                if (_searchQuery.isNotEmpty) {
                  filteredSources = filteredSources
                      .where(
                        (s) => s.name.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();
                }

                if (filteredSources.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? OnboardingStrings.q9EmptyList
                          : OnboardingStrings.q9NoMatch,
                      style: TextStyle(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return SingleChildScrollView(
                  child: Wrap(
                    spacing: FacteurSpacing.space2,
                    runSpacing: FacteurSpacing.space2,
                    alignment: WrapAlignment.center,
                    children: filteredSources.map((source) {
                      final isSelected = _selectedSourceIds.contains(source.id);
                      return _SourceChip(
                        source: source,
                        isSelected: isSelected,
                        onTap: () => _toggleSource(source.id),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Bouton continuer
          ElevatedButton(
            onPressed: _continue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _selectedSourceIds.isEmpty
                  ? OnboardingStrings.skipButton
                  : OnboardingStrings.selectedCount(_selectedSourceIds.length),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  final Source source;
  final bool isSelected;
  final VoidCallback onTap;

  const _SourceChip({
    required this.source,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space3,
          vertical: FacteurSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.15)
              : colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
          border: Border.all(
            color: isSelected ? colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo miniature
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                  ? Image.network(
                      source.logoUrl!,
                      width: 20,
                      height: 20,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 20,
                        height: 20,
                        color: colors.surface,
                        child: Icon(
                          Icons.public,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  : Container(
                      width: 20,
                      height: 20,
                      color: colors.surface,
                      child: Icon(
                        Icons.public,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                    ),
            ),
            const SizedBox(width: FacteurSpacing.space2),
            // Nom de la source
            Text(
              source.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? colors.primary : colors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
            // Indicateur de biais politique
            if (source.biasStance != 'unknown' &&
                source.biasStance != 'neutral') ...[
              const SizedBox(width: FacteurSpacing.space2),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: source.getBiasColor(),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
