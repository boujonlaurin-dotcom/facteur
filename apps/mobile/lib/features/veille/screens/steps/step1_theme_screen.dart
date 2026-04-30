import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/veille_mock_data.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_widgets.dart';

class Step1ThemeScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const Step1ThemeScreen({super.key, required this.onClose});

  @override
  ConsumerState<Step1ThemeScreen> createState() => _Step1ThemeScreenState();
}

class _Step1ThemeScreenState extends ConsumerState<Step1ThemeScreen> {
  final GlobalKey _preciseKey = GlobalKey();
  bool _didReveal = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final hasTheme = state.selectedTheme != null;
    final selectedThemeLabel = VeilleMockData.themes
        .firstWhere(
          (t) => t.id == state.selectedTheme,
          orElse: () => VeilleMockData.themes.first,
        )
        .label;

    ref.listen<String?>(
      veilleConfigProvider.select((s) => s.selectedTheme),
      (prev, next) {
        if (!_didReveal && prev == null && next != null) {
          _didReveal = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _preciseKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                alignment: 0.1,
              );
            }
          });
        }
      },
    );

    return Column(
      children: [
        VeilleStepHeader(
          step: 1,
          canGoBack: false,
          onClose: widget.onClose,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1('Sur quel sujet veux-tu une veille ?'),
                const SizedBox(height: 22),
                _ThemeGrid(
                  selected: state.selectedTheme,
                  onSelect: notifier.selectTheme,
                ),
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.topCenter,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    heightFactor: hasTheme ? 1 : 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 280),
                      opacity: hasTheme ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Column(
                          key: _preciseKey,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const VeilleBlockLabel(
                              'Précise ce qui t\'intéresse',
                            ),
                            VeilleHelpHint(
                              spans: [
                                const TextSpan(
                                  text: 'Préchargé depuis tes lectures sur ',
                                ),
                                TextSpan(
                                  text: '« $selectedThemeLabel »',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const TextSpan(text: '.'),
                              ],
                            ),
                            for (int i = 0;
                                i < VeilleMockData.presetTopics.length;
                                i++) ...[
                              if (i > 0) const SizedBox(height: 6),
                              CheckRow(
                                label: VeilleMockData.presetTopics[i].label,
                                reason: VeilleMockData.presetTopics[i].reason,
                                selected: state.selectedTopics.contains(
                                  VeilleMockData.presetTopics[i].id,
                                ),
                                onTap: () => notifier.toggleTopic(
                                  VeilleMockData.presetTopics[i].id,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: hasTheme ? Offset.zero : const Offset(0, 1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: hasTheme ? 1 : 0,
            child: IgnorePointer(
              ignoring: !hasTheme,
              child: _Footer(onTap: notifier.goNext),
            ),
          ),
        ),
      ],
    );
  }
}

class _ThemeGrid extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _ThemeGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const themes = VeilleMockData.themes;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.55,
      children: [
        for (final t in themes)
          ThemeCard(
            theme: t,
            selected: selected == t.id,
            onTap: () => onSelect(t.id),
          ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final VoidCallback onTap;
  const _Footer({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE6E1D6), width: 1),
        ),
      ),
      child: VeilleCtaButton(
        label: 'Continuer',
        trailingIcon: PhosphorIcons.arrowRight(),
        onPressed: onTap,
      ),
    );
  }
}
