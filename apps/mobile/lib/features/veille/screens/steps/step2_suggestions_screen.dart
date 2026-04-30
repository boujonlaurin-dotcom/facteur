import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_widgets.dart';

class Step2SuggestionsScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

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
                Column(
                  children: [
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
                ),
                const SizedBox(height: 16),
                GhostLink(
                  label: 'Proposer d\'autres angles',
                  icon: PhosphorIcons.arrowsClockwise(),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bientôt — le facteur prépare d\'autres angles.'),
                      ),
                    );
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
