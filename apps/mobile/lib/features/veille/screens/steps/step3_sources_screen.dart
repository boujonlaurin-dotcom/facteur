import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_source_card.dart';
import '../../widgets/veille_widgets.dart';

class Step3SourcesScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step3SourcesScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

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
                const VeilleBlockLabel('Tes sources de confiance'),
                Column(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 24),
                const VeilleBlockLabel(
                  'Sources niches recommandées par le facteur',
                ),
                Column(
                  children: [
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
                ),
                const SizedBox(height: 16),
                GhostLink(
                  label: 'Proposer plus de sources',
                  icon: PhosphorIcons.arrowsClockwise(),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Bientôt — le facteur cherche d\'autres sources niches.',
                        ),
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
