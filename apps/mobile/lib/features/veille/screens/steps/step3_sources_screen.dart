import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../models/veille_config.dart';
import '../../models/veille_suggestion.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_suggestions_provider.dart';
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
          );

    final asyncSuggestions = params == null
        ? const AsyncValue<VeilleSourceSuggestionsResponse>.data(
            VeilleSourceSuggestionsResponse(followed: [], niche: []),
          )
        : ref.watch(veilleSourceSuggestionsProvider(params));

    // Hydrate les sources via ref.listen pour éviter une boucle infinie
    // (apply → state change → rebuild → re-apply).
    if (params != null) {
      ref.listen<AsyncValue<VeilleSourceSuggestionsResponse>>(
        veilleSourceSuggestionsProvider(params),
        (_, next) {
          next.whenData((apiResp) {
            if (apiResp.followed.isNotEmpty || apiResp.niche.isNotEmpty) {
              notifier.applySourceSuggestions(apiResp);
            }
          });
        },
      );
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
                const SizedBox(height: 24),
                asyncSuggestions.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) =>
                      _MockSourcesFallback(state: state, notifier: notifier),
                  data: (resp) => _ApiSourceLists(
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
                    if (params != null) {
                      ref
                          .read(veilleSourceSuggestionsProvider(params).notifier)
                          .refreshKeepingChecked(state.nicheSources);
                    }
                  },
                ),
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
            onPressed: notifier.goNext,
          ),
        ),
      ],
    );
  }
}

class _ApiSourceLists extends StatelessWidget {
  final VeilleSourceSuggestionsResponse resp;
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;

  const _ApiSourceLists({
    required this.resp,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    if (resp.followed.isEmpty && resp.niche.isEmpty) {
      return _MockSourcesFallback(state: state, notifier: notifier);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resp.followed.isNotEmpty) ...[
          const VeilleBlockLabel('Tes sources de confiance'),
          for (int i = 0; i < resp.followed.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            VeilleSourceCard(
              source: _toUiSource(resp.followed[i]),
              inVeille: state.followedSources.contains(resp.followed[i].sourceId),
              isNiche: false,
              onToggle: () =>
                  notifier.toggleFollowedSource(resp.followed[i].sourceId),
            ),
          ],
          const SizedBox(height: 24),
        ],
        if (resp.niche.isNotEmpty) ...[
          const VeilleBlockLabel(
            'Sources niches recommandées par le facteur',
          ),
          for (int i = 0; i < resp.niche.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            VeilleSourceCard(
              source: _toUiSource(resp.niche[i]),
              inVeille: state.nicheSources.contains(resp.niche[i].sourceId),
              isNiche: true,
              onToggle: () =>
                  notifier.toggleNicheSource(resp.niche[i].sourceId),
            ),
          ],
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
      logoUrl: 'https://www.google.com/s2/favicons?sz=128&domain=${_domain(s.url)}',
    );
  }

  static String _domain(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? url;
  }
}

class _MockSourcesFallback extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _MockSourcesFallback({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Suggestions indisponibles, conserve ta sélection.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
          ),
        ),
        const VeilleBlockLabel('Tes sources de confiance'),
        for (int i = 0;
            i < VeilleMockData.followedSources.length;
            i++) ...[
          if (i > 0) const SizedBox(height: 6),
          VeilleSourceCard(
            source: VeilleMockData.followedSources[i],
            inVeille: state.followedSources.contains(
              VeilleMockData.followedSources[i].id,
            ),
            isNiche: false,
            onToggle: () => notifier.toggleFollowedSource(
              VeilleMockData.followedSources[i].id,
            ),
          ),
        ],
        const SizedBox(height: 24),
        const VeilleBlockLabel(
          'Sources niches recommandées par le facteur',
        ),
        for (int i = 0;
            i < VeilleMockData.nicheSources.length;
            i++) ...[
          if (i > 0) const SizedBox(height: 6),
          VeilleSourceCard(
            source: VeilleMockData.nicheSources[i],
            inVeille: state.nicheSources.contains(
              VeilleMockData.nicheSources[i].id,
            ),
            isNiche: true,
            onToggle: () => notifier.toggleNicheSource(
              VeilleMockData.nicheSources[i].id,
            ),
          ),
        ],
      ],
    );
  }
}
