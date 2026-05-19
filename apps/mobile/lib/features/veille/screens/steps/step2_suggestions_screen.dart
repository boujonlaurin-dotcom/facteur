import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_preset_topics_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 2 — Sujets + (optionnel) angles libres en mode avancé.
///
/// Refonte Story 23.2 PR-4 :
/// - Plus de curation LLM (endpoints `/suggestions/*` dropés en Story 23.1).
/// - Liste de topics présélectionnés issus du preset ou du thème.
/// - Bouton "+ Ajouter un sujet" pour saisie free-text (custom topic).
/// - Bouton "Passer cette étape" → skip vers step 3.
/// - Toggle "Configuration avancée" → champs free-text angles + brief éditorial.
class Step2SuggestionsScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  ConsumerState<Step2SuggestionsScreen> createState() =>
      _Step2SuggestionsScreenState();
}

class _Step2SuggestionsScreenState
    extends ConsumerState<Step2SuggestionsScreen> {
  final TextEditingController _customTopicCtrl = TextEditingController();
  final TextEditingController _keywordCtrl = TextEditingController();

  @override
  void dispose() {
    _customTopicCtrl.dispose();
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final themeId = state.selectedTheme;

    final presetTopicsAsync = themeId == null
        ? const AsyncValue<List<VeilleTopic>>.data([])
        : ref.watch(veillePresetTopicsProvider(themeId));

    return Column(
      children: [
        VeilleStepHeader(
          step: 2,
          onClose: widget.onClose,
          onBack: notifier.goBack,
          // Bouton "Passer cette étape" en top-right (avant la croix close).
          trailingAction: _SkipButton(onTap: notifier.skipStep2),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1(
                  'Quels sujets précis veux-tu suivre ?',
                ),
                const SizedBox(height: 8),
                Text(
                  'Optionnel — passe cette étape si tu veux juste le thème global.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                presetTopicsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    // Hydrate les labels du state au premier rendu pour que
                    // _buildUpsertRequest envoie le label correct.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      notifier.registerPresetTopicLabels(items);
                    });
                    return Column(
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 6),
                          CheckRow(
                            label: items[i].label,
                            reason: items[i].reason,
                            selected: state.selectedTopics.contains(items[i].id),
                            onTap: () => notifier.toggleTopic(items[i].id),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _AddCustomTopicField(
                  controller: _customTopicCtrl,
                  onSubmit: (label) {
                    notifier.addCustomTopic(label);
                    _customTopicCtrl.clear();
                  },
                ),
                if (state.customTopics.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in state.customTopics)
                        _CustomTopicChip(
                          label: t.label,
                          onRemove: () => notifier.removeCustomTopic(t.id),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                _AdvancedToggle(
                  expanded: state.advancedMode,
                  onTap: () => notifier.setAdvancedMode(!state.advancedMode),
                ),
                if (state.advancedMode) ...[
                  const SizedBox(height: 16),
                  _AdvancedSection(
                    state: state,
                    notifier: notifier,
                    keywordCtrl: _keywordCtrl,
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FacteurColors.veilleLineSoft)),
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

class _SkipButton extends StatelessWidget {
  final VoidCallback onTap;
  const _SkipButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Passer',
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF5D5B5A),
        ),
      ),
    );
  }
}

class _AddCustomTopicField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  const _AddCustomTopicField({
    required this.controller,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.done,
      onSubmitted: (v) {
        if (v.trim().isEmpty) return;
        onSubmit(v);
      },
      maxLength: 80,
      decoration: InputDecoration(
        hintText: 'Ajouter un sujet…',
        prefixIcon: const Icon(Icons.add, color: Color(0xFF8B7E63), size: 18),
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: FacteurColors.veilleLineSoft),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _CustomTopicChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _CustomTopicChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: GoogleFonts.dmSans(fontSize: 12)),
      onDeleted: onRemove,
      deleteIcon: Icon(PhosphorIcons.x(), size: 14),
      backgroundColor: FacteurColors.veilleTint,
      side: const BorderSide(color: FacteurColors.veilleLineSoft),
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

class _AdvancedSection extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  final TextEditingController keywordCtrl;
  const _AdvancedSection({
    required this.state,
    required this.notifier,
    required this.keywordCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const VeilleBlockLabel('Angles précis'),
        const SizedBox(height: 6),
        Text(
          'Ajoute des mots-clés (ex: GPT-5, transition écologique). On les '
          'priorisera dans ta veille.',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFF5D5B5A),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: keywordCtrl,
          textInputAction: TextInputAction.done,
          maxLength: 60,
          decoration: InputDecoration(
            hintText: 'Ex: intelligence artificielle',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: FacteurColors.veilleLineSoft),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onSubmitted: (v) {
            notifier.addKeyword(v);
            keywordCtrl.clear();
          },
        ),
        if (state.keywords.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kw in state.keywords)
                Chip(
                  label: Text(kw, style: GoogleFonts.dmSans(fontSize: 12)),
                  onDeleted: () => notifier.removeKeyword(kw),
                  deleteIcon: Icon(PhosphorIcons.x(), size: 14),
                  backgroundColor: const Color(0xFFFFF8E7),
                  side: const BorderSide(color: FacteurColors.veilleLineSoft),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const VeilleBlockLabel('Brief éditorial'),
        const SizedBox(height: 6),
        Text(
          'Une phrase courte qui décrit ton angle de lecture.',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFF5D5B5A),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        VeilleEditorialBriefField(
          value: state.editorialBrief,
          onChanged: notifier.setEditorialBrief,
        ),
      ],
    );
  }
}
