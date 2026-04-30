import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_widgets.dart';

class Step4FrequencyScreen extends ConsumerWidget {
  final VoidCallback onClose;
  final Future<void> Function() onSubmit;
  const Step4FrequencyScreen({
    super.key,
    required this.onClose,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final scheduleText = _scheduleText(state.frequency, state.day);

    return Column(
      children: [
        VeilleStepHeader(
          step: 4,
          onClose: onClose,
          onBack: notifier.goBack,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1('À quel rythme veux-tu la recevoir ?'),
                const SizedBox(height: 22),
                Column(
                  children: [
                    for (int i = 0;
                        i < VeilleFrequency.values.length;
                        i++) ...[
                      if (i > 0) const SizedBox(height: 6),
                      FrequencyRow(
                        freq: VeilleFrequency.values[i],
                        selected:
                            state.frequency == VeilleFrequency.values[i],
                        onTap: () =>
                            notifier.setFrequency(VeilleFrequency.values[i]),
                      ),
                    ],
                  ],
                ),
                if (state.frequency != VeilleFrequency.monthly) ...[
                  const SizedBox(height: 24),
                  const VeilleBlockLabel('Quel jour ?'),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 7,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                    children: [
                      for (final d in VeilleDay.values)
                        DayPill(
                          label: d.label,
                          selected: state.day == d,
                          onTap: () => notifier.setDay(d),
                        ),
                    ],
                  ),
                ],
                FinalRecapCard(
                  title: VeilleMockData.recapTitle,
                  schedule: scheduleText,
                  angles: state.totalSelectedAngles,
                  sources: state.totalSelectedSources,
                  topics: state.totalSelectedTopics,
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
            label: 'Lancer ma veille',
            leadingIcon: PhosphorIcons.check(),
            onPressed: () async {
              await notifier.submit();
              await onSubmit();
            },
          ),
        ),
      ],
    );
  }

  String _scheduleText(VeilleFrequency f, VeilleDay d) {
    if (f == VeilleFrequency.monthly) return 'mois';
    final dayLabel = _fullDay(d);
    if (f == VeilleFrequency.biweekly) {
      return '${dayLabel}s (1 sur 2) matin';
    }
    return '${dayLabel}s matin';
  }

  String _fullDay(VeilleDay d) {
    switch (d) {
      case VeilleDay.mon:
        return 'lundi';
      case VeilleDay.tue:
        return 'mardi';
      case VeilleDay.wed:
        return 'mercredi';
      case VeilleDay.thu:
        return 'jeudi';
      case VeilleDay.fri:
        return 'vendredi';
      case VeilleDay.sat:
        return 'samedi';
      case VeilleDay.sun:
        return 'dimanche';
    }
  }
}
