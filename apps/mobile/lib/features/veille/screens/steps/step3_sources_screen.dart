import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../models/veille_config.dart';
import '../../models/veille_suggestion.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_suggestions_provider.dart';
import '../../widgets/veille_add_source_sheet.dart';
import '../../widgets/veille_source_card.dart';
import '../../widgets/veille_widgets.dart';

class Step3SourcesScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step3SourcesScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    final themeId = state.selectedTheme;
    final topicLabels = <String>[
      ...state.selectedTopics.map((id) => state.topicLabels[id] ?? id),
      ...state.selectedSuggestions.map((id) => state.topicLabels[id] ?? id),
    ];

    final params = themeId == null
        ? null
        : VeilleSourcesSuggestionParams(
            themeId: themeId,
            topicLabels: topicLabels,
            purpose: state.purpose,
            purposeOther: state.purposeOther,
            editorialBrief: state.editorialBrief,
          );

    final asyncSuggestions = params == null
        ? const AsyncValue<VeilleSourceSuggestionsResponse>.data(
            VeilleSourceSuggestionsResponse(sources: []),
          )
        : ref.watch(veilleSourceSuggestionsProvider(params));

    if (params != null) {
      ref.listen<AsyncValue<VeilleSourceSuggestionsResponse>>(
        veilleSourceSuggestionsProvider(params),
        (_, next) {
          next.whenData((apiResp) {
            if (apiResp.sources.isNotEmpty) {
              notifier.applySourceSuggestions(apiResp);
            }
          });
        },
      );
    }

    final hasRealSource = state.realSelectedSourceCount > 0;

    void retrySuggestions() {
      if (params == null) return;
      ref
          .read(veilleSourceSuggestionsProvider(params).notifier)
          .refreshKeepingChecked(state.selectedSourceIds);
    }

    return Column(
      children: [
        VeilleStepHeader(
          step: 3,
          onClose: onClose,
          onBack: notifier.goBack,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleAiEyebrow('Sélection du facteur'),
                const SizedBox(height: 10),
                const VeilleFlowH1(
                  'Les sources qui couvriront le mieux tes angles',
                ),
                const SizedBox(height: 8),
                Text(
                  'Classées par pertinence pour ta veille.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8B7E63),
                      ),
                ),
                const SizedBox(height: 24),
                asyncSuggestions.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => _SuggestionsUnavailable(
                    onRetry: params == null ? null : retrySuggestions,
                  ),
                  data: (resp) => resp.sources.isEmpty
                      ? _SuggestionsUnavailable(
                          onRetry: params == null ? null : retrySuggestions,
                        )
                      : _ApiSourceList(
                          resp: resp,
                          state: state,
                          notifier: notifier,
                        ),
                ),
                const SizedBox(height: 16),
                GhostLink(
                  label: 'Proposer plus de sources',
                  icon: PhosphorIcons.arrowsClockwise(),
                  onTap: () {
                    if (params != null) retrySuggestions();
                  },
                ),
                const SizedBox(height: 12),
                _AddSourceButton(
                  onTap: () => _openAddSheet(context, ref, notifier),
                ),
                if (!hasRealSource) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Sélectionne au moins une source pour continuer.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8B7E63),
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE6E1D6))),
          ),
          child: VeilleCtaButton(
            label: 'Continuer',
            trailingIcon: PhosphorIcons.arrowRight(),
            onPressed: hasRealSource ? notifier.goNext : null,
          ),
        ),
      ],
    );
  }

  void _openAddSheet(
    BuildContext context,
    WidgetRef ref,
    VeilleConfigNotifier notifier,
  ) {
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
            );
          }
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

class _ApiSourceList extends StatelessWidget {
  final VeilleSourceSuggestionsResponse resp;
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;

  const _ApiSourceList({
    required this.resp,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < resp.sources.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          VeilleSourceCard(
            source: _toUiSource(resp.sources[i]),
            inVeille:
                state.selectedSourceIds.contains(resp.sources[i].sourceId),
            isAlreadyFollowed: resp.sources[i].isAlreadyFollowed,
            onToggle: () => notifier.toggleSource(resp.sources[i].sourceId),
          ),
        ],
      ],
    );
  }

  static VeilleSource _toUiSource(VeilleSourceSuggestion s) {
    final letter = s.name.isNotEmpty ? s.name[0].toUpperCase() : '?';
    return VeilleSource(
      id: s.sourceId,
      letter: letter,
      name: s.name,
      meta: 'Source suggérée',
      why: s.why,
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=${_domain(s.url)}',
    );
  }

  static String _domain(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? url;
  }
}

/// Affiché quand l'API `/suggestions/sources` est en erreur ou retourne `[]`.
/// Plus aucune liste mock cliquable (les mocks n'avaient pas d'`apiSourceId`
/// et étaient systématiquement jetés au submit — piège UX).
class _SuggestionsUnavailable extends StatelessWidget {
  final VoidCallback? onRetry;
  const _SuggestionsUnavailable({this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veilleLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'On n\'a pas pu charger les suggestions.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2A2419),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Réessaie ou ajoute une source manuellement.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8B7E63),
                ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: Icon(PhosphorIcons.arrowClockwise(), size: 16),
                label: const Text('Réessayer'),
                style: TextButton.styleFrom(
                  foregroundColor: FacteurColors.veille,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ],
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
            border: Border.all(
              color: FacteurColors.veilleLine,
              width: 1.5,
            ),
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
                  'Ajouter une source',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
