import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_preset_topics_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 2 — choix des sujets pour la veille.
///
/// PR-4 (Story 23.3) : la suggestion LLM des angles a été supprimée. L'écran
/// affiche les sujets curés du thème (via `veillePresetTopicsProvider`) +
/// les sujets custom déjà ajoutés ; l'user peut en ajouter d'autres ou tout
/// passer. Un toggle "Configuration avancée" expose mots-clés libres + brief
/// éditorial pour les power-users.
class Step2SuggestionsScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final theme = state.selectedTheme;
    final presetTopicsAsync = theme == null
        ? const AsyncValue<List<VeilleTopic>>.data(<VeilleTopic>[])
        : ref.watch(veillePresetTopicsProvider(theme));

    final hasSelection = state.selectedTopics.isNotEmpty;

    return Column(
      children: [
        VeilleStepHeader(
          step: 2,
          onClose: onClose,
          onBack: notifier.goBack,
          trailingAction: _SkipButton(onTap: notifier.skipStep2),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1('Quels sujets veux-tu suivre ?'),
                const SizedBox(height: 8),
                Text(
                  'Coche les sujets qui t\'intéressent dans ce thème. Tu peux '
                  'aussi en ajouter un sur-mesure, ou passer cette étape.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                _TopicsList(
                  presetTopicsAsync: presetTopicsAsync,
                  state: state,
                  notifier: notifier,
                ),
                const SizedBox(height: 12),
                _AddTopicChip(
                  onTap: () => _openAddTopicSheet(context, notifier),
                ),
                const SizedBox(height: 24),
                _AdvancedToggle(
                  expanded: state.advancedMode,
                  onTap: () => notifier.setAdvancedMode(!state.advancedMode),
                ),
                if (state.advancedMode) ...[
                  const SizedBox(height: 16),
                  _KeywordsSection(state: state, notifier: notifier),
                  const SizedBox(height: 18),
                  _BriefSection(state: state, notifier: notifier),
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
            onPressed: hasSelection ? notifier.goNext : null,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        'Passer',
        style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: FacteurColors.veille,
        ),
      ),
    );
  }
}

class _TopicsList extends ConsumerWidget {
  final AsyncValue<List<VeilleTopic>> presetTopicsAsync;
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _TopicsList({
    required this.presetTopicsAsync,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return presetTopicsAsync.when(
      loading: () => const _SkeletonList(),
      error: (_, __) => _renderList(const <VeilleTopic>[]),
      data: (preset) {
        // Hydrate les labels une fois pour que `_buildUpsertRequest` les envoie.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifier.registerPresetTopicLabels(preset);
        });
        return _renderList(preset);
      },
    );
  }

  Widget _renderList(List<VeilleTopic> presetTopics) {
    final seen = <String>{};
    final merged = <VeilleTopic>[];
    for (final t in state.customTopics) {
      if (seen.add(t.id)) merged.add(t);
    }
    for (final t in presetTopics) {
      if (seen.add(t.id)) merged.add(t);
    }

    if (merged.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDFBF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: FacteurColors.veilleLineSoft),
        ),
        child: Text(
          'Aucun sujet pré-curé pour ce thème. Ajoute un sujet sur-mesure '
          'ci-dessous ou passe cette étape.',
          style: GoogleFonts.dmSans(
            fontSize: 12.5,
            color: const Color(0xFF5D5B5A),
            height: 1.4,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < merged.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _TopicRow(
            topic: merged[i],
            selected: state.selectedTopics.contains(merged[i].id),
            onToggle: () => notifier.toggleTopic(merged[i].id),
          ),
        ],
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  final VeilleTopic topic;
  final bool selected;
  final VoidCallback onToggle;
  const _TopicRow({
    required this.topic,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? FacteurColors.veille
                  : FacteurColors.veilleLineSoft,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: selected ? FacteurColors.veille : Colors.white,
                  border: Border.all(
                    color: selected
                        ? FacteurColors.veille
                        : const Color(0xFFD2C9BB),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.label,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: const Color(0xFF2C2A29),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      topic.reason,
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        height: 1.4,
                        color: const Color(0xFF959392),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTopicChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddTopicChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FacteurColors.veille.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.plus(), size: 16, color: FacteurColors.veille),
            const SizedBox(width: 10),
            Text(
              'Ajouter un sujet',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FacteurColors.veille,
              ),
            ),
          ],
        ),
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

class _KeywordsSection extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _KeywordsSection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MOTS-CLÉS',
          style: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: const Color(0xFF8B7E63),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ajoute jusqu\'à ${VeilleConfigNotifier.maxKeywords} mots-clés pour '
          'filtrer plus finement les articles (titre, description).',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFF5D5B5A),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        if (state.keywords.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kw in state.keywords)
                _KeywordChip(label: kw, onRemove: () => notifier.removeKeyword(kw)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _AddKeywordButton(
          enabled: state.keywords.length < VeilleConfigNotifier.maxKeywords,
          onTap: () => _openAddKeywordSheet(context, notifier),
        ),
      ],
    );
  }
}

class _KeywordChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _KeywordChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FacteurColors.veilleLineSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  color: const Color(0xFF2C2A29),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                PhosphorIcons.x(),
                size: 12,
                color: const Color(0xFF8B7E63),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddKeywordButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _AddKeywordButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? FacteurColors.veilleTint : const Color(0xFFEDE7D8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: enabled ? FacteurColors.veille : const Color(0xFFD2C9BB),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.plus(),
              size: 12,
              color: enabled
                  ? FacteurColors.veille
                  : const Color(0xFFB8B0A0),
            ),
            const SizedBox(width: 4),
            Text(
              enabled ? 'Ajouter un mot-clé' : 'Limite atteinte',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled
                    ? FacteurColors.veille
                    : const Color(0xFFB8B0A0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefSection extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _BriefSection({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BRIEF ÉDITORIAL',
          style: GoogleFonts.dmSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: const Color(0xFF8B7E63),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Précise le format ou l\'angle (analyses long format, focus PME, etc.).',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFF5D5B5A),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        VeilleEditorialBriefField(
          value: state.editorialBrief,
          onChanged: notifier.setEditorialBrief,
        ),
      ],
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0E5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openAddTopicSheet(
  BuildContext context,
  VeilleConfigNotifier notifier,
) async {
  final ctrl = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final viewInsets = MediaQuery.of(ctx).viewInsets;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ajouter un sujet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ex : « IA générative », « Politique numérique européenne »',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ton sujet',
                counterText: '',
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                  child: const Text('Ajouter'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  if (result != null && result.isNotEmpty) notifier.addCustomTopic(result);
}

Future<void> _openAddKeywordSheet(
  BuildContext context,
  VeilleConfigNotifier notifier,
) async {
  final ctrl = TextEditingController();
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final viewInsets = MediaQuery.of(ctx).viewInsets;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ajouter un mot-clé',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sera utilisé pour filtrer les articles (titre, description).',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Ex : gpt-5',
                counterText: '',
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(ctrl.text.trim()),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                  child: const Text('Ajouter'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  if (result != null && result.isNotEmpty) notifier.addKeyword(result);
}
