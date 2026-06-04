import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../shared/widgets/loaders/facteur_loader.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../models/veille_config_dto.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_source_suggestions_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_add_source_sheet.dart';
import '../../widgets/veille_source_card.dart';
import '../../widgets/veille_widgets.dart';

/// Step 3 — choix des sources pour la veille.
///
/// Les sources catalogue déjà appliquées gardent leurs exemples récents.
/// Les sources LLM sont présélectionnées puis résolues en arrière-plan pour
/// obtenir un `source_id` avant le submit.
class Step3SourcesScreen extends ConsumerWidget {
  final VoidCallback onClose;
  final Future<void> Function() onSubmit;

  const Step3SourcesScreen({
    super.key,
    required this.onClose,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final query = state.sourceSuggestionsRequested
        ? buildSuggestionQuery(state)
        : null;
    final VoidCallback? onRetry = query == null
        ? null
        : () => ref.invalidate(veilleSourceSuggestionsProvider(query));
    final suggestionsAsync = query == null
        ? const AsyncValue<List<VeilleSourceSuggestionDto>>.data(
            <VeilleSourceSuggestionDto>[],
          )
        : ref.watch(veilleSourceSuggestionsProvider(query));

    if (state.hasPendingSelectedSources && !state.isResolvingSources) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.resolvePendingSources();
      });
    }

    final canSubmit =
        state.realSelectedSourceCount > 0 &&
        !state.isSubmitting &&
        !state.isResolvingSources;

    // Sources déjà en state : existantes d'abord, puis suggestions/pending.
    final sourceMetas = <VeilleSourceMeta>[];
    final seen = <String>{};
    for (final id in state.selectedSourceIds) {
      final meta = state.sourcesMeta[id];
      if (meta == null || !seen.add(id)) continue;
      sourceMetas.add(meta);
    }
    for (final entry in state.sourcesMeta.entries) {
      if (state.selectedSourceIds.contains(entry.key)) continue;
      if (!seen.add(entry.key)) continue;
      sourceMetas.add(entry.value);
    }

    return Column(
      children: [
        VeilleStepHeader(step: 3, onClose: onClose, onBack: notifier.goBack),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1('Quelles sources veux-tu suivre ?'),
                const SizedBox(height: 8),
                Text(
                  sourceMetas.isEmpty
                      ? 'Ajoute une source par URL pour démarrer ta veille — '
                            'un blog niche, un flux RSS, etc.'
                      : 'Décoche celles que tu ne veux pas suivre, ou ajoute '
                            'une source par URL via la configuration avancée.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                if (sourceMetas.isNotEmpty) ...[
                  Column(
                    children: [
                      for (int i = 0; i < sourceMetas.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        VeilleSourceCard(
                          source: _metaToUiSource(sourceMetas[i]),
                          inVeille: state.selectedSourceIds.contains(
                            sourceMetas[i].slug,
                          ),
                          isAlreadyFollowed: false,
                          showExamples:
                              sourceMetas[i].connectionStatus ==
                                  VeilleSourceConnectionStatus.connected &&
                              sourceMetas[i].apiSourceId != null,
                          exampleSourceId: sourceMetas[i].apiSourceId,
                          connectionStatus: sourceMetas[i].connectionStatus,
                          failureReason: sourceMetas[i].failureReason,
                          onToggle: () =>
                              sourceMetas[i].connectionStatus ==
                                  VeilleSourceConnectionStatus.failed
                              ? notifier.removeSource(sourceMetas[i].slug)
                              : notifier.toggleSource(sourceMetas[i].slug),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
                if (!state.sourceSuggestionsRequested)
                  _LoadMoreSourcesButton(onTap: notifier.requestMoreSources)
                else
                  suggestionsAsync.when(
                    loading: () => const _SourceSuggestionsLoading(),
                    error: (_, __) => _SourceSuggestionsEmpty(
                      onRetry: onRetry,
                      isError: true,
                    ),
                    data: (suggestions) {
                      if (suggestions.isEmpty) {
                        return _SourceSuggestionsEmpty(onRetry: onRetry);
                      }
                      final hasNewSuggestion = suggestions.any((s) {
                        if (!_isValidHttpUrl(s.url)) return false;
                        final slug = VeilleConfigNotifier.sourceSuggestionSlug(
                          s.name,
                          s.url,
                        );
                        return !state.sourcesMeta.containsKey(slug);
                      });
                      if (hasNewSuggestion) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          notifier.registerSuggestedSources(suggestions);
                        });
                      }
                      return _LoadMoreSourcesButton(onTap: onRetry);
                    },
                  ),
                const SizedBox(height: 24),
                _AdvancedToggle(
                  expanded: state.advancedMode,
                  onTap: () => notifier.setAdvancedMode(!state.advancedMode),
                ),
                if (state.advancedMode) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Ajoute une source par URL — un blog niche, un flux RSS '
                    'spécialisé, etc.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF5D5B5A),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AddSourceButton(
                    onTap: () => _openAddSheet(context, notifier),
                  ),
                ],
                if (!canSubmit && !state.isSubmitting) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.isResolvingSources || state.hasPendingSelectedSources
                        ? 'Vérification des sources en cours.'
                        : 'Sélectionne au moins une source prête pour continuer.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF8B7E63),
                    ),
                  ),
                ],
                if (state.lastError != null) ...[
                  const SizedBox(height: 12),
                  _InlineSourceStatusBanner(
                    message: state.lastError!,
                    onRetry: state.hasPendingSelectedSources
                        ? () => notifier.resolvePendingSources(force: true)
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: FacteurColors.veilleLineSoft),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VeilleCtaButton(
                label: state.isSubmitting
                    ? 'Enregistrement…'
                    : 'Créer ma veille',
                trailingIcon: PhosphorIcons.check(),
                onPressed: canSubmit ? () => onSubmit() : null,
              ),
              if (state.isSubmitting || state.isResolvingSources) ...[
                const SizedBox(height: 8),
                Text(
                  state.isSubmitting
                      ? 'Enregistrement en cours. Tes choix restent affichés.'
                      : 'Vérification des sources en arrière-plan.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: const Color(0xFF8B7E63),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openAddSheet(BuildContext context, VeilleConfigNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => VeilleAddSourceSheet(
        onSourceAdded: (SmartSearchResult result) {
          final id = result.sourceId;
          if (id != null && id.isNotEmpty && id != 'null') {
            notifier.addCustomSourceToVeille(
              sourceId: id,
              name: result.name,
              url: result.url,
              why: result.description,
            );
          } else {
            final url = result.feedUrl.trim().isNotEmpty
                ? result.feedUrl
                : result.url;
            if (_isValidHttpUrl(url)) {
              notifier.addUrlSourceToVeille(
                name: result.name,
                url: url,
                why: result.description,
              );
            }
          }
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  static VeilleSource _metaToUiSource(VeilleSourceMeta meta) {
    final letter = meta.name.isNotEmpty ? meta.name[0].toUpperCase() : '?';
    return VeilleSource(
      id: meta.slug,
      letter: letter,
      name: meta.name,
      meta: meta.kind == 'niche' ? 'Source niche' : 'Source curée',
      why: meta.why,
      logoUrl: meta.logoUrl,
    );
  }
}

@visibleForTesting
VeilleSourceSuggestionsQuery? buildSuggestionQuery(VeilleConfigState state) {
  final theme = state.selectedTheme;
  if (theme == null) return null;
  final themeLabel = state.resolvedThemeLabel(veilleThemeLabelForSlug(theme));
  final angleLabels = <String>[];
  if (state.mainTopicSlug != null) {
    angleLabels.add(
      state.mainTopicLabel ??
          state.topicLabels[state.mainTopicSlug!] ??
          state.mainTopicSlug!,
    );
  }
  for (final slug in state.selectedSuggestions) {
    final label = state.topicLabels[slug];
    if (label != null && label.trim().isNotEmpty) angleLabels.add(label);
  }

  final keywords = <String>{...state.keywords};
  final selectedTopicSlugs = <String>{
    if (state.mainTopicSlug != null) state.mainTopicSlug!,
    ...state.selectedSuggestions,
  };
  for (final slug in selectedTopicSlugs) {
    keywords.addAll(state.angleKeywords[slug] ?? const <String>[]);
  }

  return (
    themeId: theme,
    themeLabel: themeLabel,
    brief: state.editorialBrief ?? '',
    anglesKey: angleLabels
        .take(VeilleConfigNotifier.maxSuggestAngles)
        .join('|'),
    keywordsKey: keywords
        .take(VeilleConfigNotifier.maxSuggestKeywords)
        .join('|'),
  );
}

class _LoadMoreSourcesButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _LoadMoreSourcesButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(PhosphorIcons.plus(), size: 15),
      label: const Text('Charger plus'),
    );
  }
}

class _InlineSourceStatusBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _InlineSourceStatusBanner({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FacteurColors.veilleLineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIcons.warningCircle(),
            size: 16,
            color: const Color(0xFF8B7E63),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                height: 1.35,
                color: const Color(0xFF5D5B5A),
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ],
      ),
    );
  }
}

class _SourceSuggestionsLoading extends StatelessWidget {
  const _SourceSuggestionsLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const FacteurLoader(width: 64, height: 64),
            const SizedBox(height: 8),
            Text(
              'Recherche de sources pour ta veille…',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 12.5,
                color: const Color(0xFF8B7E63),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSuggestionsEmpty extends StatelessWidget {
  final VoidCallback? onRetry;
  final bool isError;
  const _SourceSuggestionsEmpty({required this.onRetry, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veilleLineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isError
                ? 'Impossible de proposer des sources pour l\'instant.'
                : 'Aucune source proposée pour l\'instant.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2C2A29),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: Icon(PhosphorIcons.arrowsClockwise(), size: 15),
            label: Text(isError ? 'Réessayer' : 'Proposer plus de sources'),
          ),
        ],
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  final bool expanded;
  final VoidCallback onTap;
  const _AdvancedToggle({required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              expanded ? PhosphorIcons.caretDown() : PhosphorIcons.caretRight(),
              size: 16,
              color: const Color(0xFF5D5B5A),
            ),
            const SizedBox(width: 6),
            Text(
              'Configuration avancée',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF5D5B5A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSourceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSourceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FacteurColors.veilleLine, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: FacteurColors.veille,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ajouter une source par URL',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FacteurColors.veille,
                  ),
                ),
              ),
              Icon(
                PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                size: 14,
                color: FacteurColors.veille,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _isValidHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty;
}
