import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../models/veille_config.dart';
import '../../models/veille_suggestion.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_suggestions_provider.dart';
import '../../widgets/veille_widgets.dart';

class Step2SuggestionsScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    final themeId = state.selectedTheme;
    final themeLabel = themeId == null
        ? null
        : VeilleMockData.themes
            .firstWhere(
              (t) => t.id == themeId,
              orElse: () => VeilleMockData.themes.first,
            )
            .label;

    final params = (themeId != null && themeLabel != null)
        ? VeilleTopicsSuggestionParams(
            themeId: themeId,
            themeLabel: themeLabel,
            selectedTopicIds: state.selectedTopics.toList()..sort(),
          )
        : null;

    final asyncSuggestions = params == null
        ? const AsyncValue<List<VeilleTopicSuggestion>>.data([])
        : ref.watch(veilleTopicSuggestionsProvider(params));

    // Hydrate les labels du state UNE fois par nouvelle réponse — ref.listen
    // ne re-tire pas à chaque rebuild (contrairement à whenData inline qui
    // boucle sur la mutation du state).
    if (params != null) {
      ref.listen<AsyncValue<List<VeilleTopicSuggestion>>>(
        veilleTopicSuggestionsProvider(params),
        (_, next) {
          next.whenData((items) {
            if (items.isNotEmpty) {
              notifier.applyTopicSuggestions(items);
            }
          });
        },
      );
    }

    return Column(
      children: [
        VeilleStepHeader(
          step: 2,
          onClose: onClose,
          onBack: notifier.goBack,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleAiEyebrow('Trouvé pour toi'),
                const SizedBox(height: 10),
                const VeilleFlowH1(
                  'Et ces angles auxquels tu n\'aurais peut-être pas pensé ?',
                ),
                const SizedBox(height: 22),
                asyncSuggestions.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => _MockFallback(state: state, notifier: notifier),
                  data: (apiItems) {
                    final items = apiItems.isNotEmpty
                        ? apiItems
                            .map((s) => VeilleTopic(
                                  id: s.topicId,
                                  label: s.label,
                                  reason: s.reason ?? '',
                                ))
                            .toList()
                        : VeilleMockData.suggestedTopics;
                    return Column(
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 6),
                          SuggestionRow(
                            label: items[i].label,
                            reason: items[i].reason,
                            selected: state.selectedSuggestions
                                .contains(items[i].id),
                            onTap: () => notifier.toggleSuggestion(items[i].id),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                GhostLink(
                  label: 'Proposer d\'autres angles',
                  icon: PhosphorIcons.arrowsClockwise(),
                  onTap: () {
                    if (params != null) {
                      ref.invalidate(veilleTopicSuggestionsProvider(params));
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

class _MockFallback extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _MockFallback({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Suggestions indisponibles, conserve ta sélection.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
          ),
        ),
        for (int i = 0;
            i < VeilleMockData.suggestedTopics.length;
            i++) ...[
          if (i > 0) const SizedBox(height: 6),
          SuggestionRow(
            label: VeilleMockData.suggestedTopics[i].label,
            reason: VeilleMockData.suggestedTopics[i].reason,
            selected: state.selectedSuggestions.contains(
              VeilleMockData.suggestedTopics[i].id,
            ),
            onTap: () => notifier.toggleSuggestion(
              VeilleMockData.suggestedTopics[i].id,
            ),
          ),
        ],
      ],
    );
  }
}
