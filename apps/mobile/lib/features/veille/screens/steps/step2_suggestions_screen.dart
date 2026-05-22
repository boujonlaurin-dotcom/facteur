import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 2 — Story 23.3 refonte complète :
/// Affiche les angles LLM (state.suggestedAngles) avec édition keywords + titre.
/// L'user peut décocher des angles, retirer/ajouter des keywords, ajouter un
/// angle custom. Au tap "Continuer" → startTransition(2) qui appelle
/// /suggest/sources avec les angles+keywords retenus.
class Step2SuggestionsScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    final canContinue = state.suggestedAngles.isNotEmpty &&
        state.selectedAngleIndexes.isNotEmpty;

    return Column(
      children: [
        VeilleStepHeader(
          step: 2,
          onClose: onClose,
          onBack: () => notifier.goBack(),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const VeilleFlowH1('Affine tes angles'),
                const SizedBox(height: 8),
                Text(
                  'Le facteur a identifié ces angles à partir de ton brief. '
                  'Décoche ceux qui ne t\'intéressent pas, ajuste les mots-clés '
                  'qui pilotent le filtrage des articles.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                if (state.suggestedAngles.isEmpty)
                  _EmptyAnglesState(onAdd: () => _openAddAngleSheet(context, notifier))
                else
                  _AnglesList(state: state, notifier: notifier),
                const SizedBox(height: 16),
                _AddAngleButton(
                  onTap: () => _openAddAngleSheet(context, notifier),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FacteurColors.veilleLineSoft)),
          ),
          child: Opacity(
            opacity: canContinue ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !canContinue,
              child: VeilleCtaButton(
                label: 'Continuer',
                trailingIcon: PhosphorIcons.arrowRight(),
                onPressed: () => notifier.startTransition(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnglesList extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _AnglesList({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < state.suggestedAngles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _AngleCard(
            index: i,
            angle: state.suggestedAngles[i],
            selected: state.selectedAngleIndexes.contains(i),
            notifier: notifier,
          ),
        ],
      ],
    );
  }
}

class _AngleCard extends StatelessWidget {
  final int index;
  final dynamic angle; // VeilleAngleSuggestionDto, dynamic pour éviter import circulaire
  final bool selected;
  final VeilleConfigNotifier notifier;
  const _AngleCard({
    required this.index,
    required this.angle,
    required this.selected,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: selected ? FacteurColors.veilleTint : const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? FacteurColors.veille
              : FacteurColors.veilleLineSoft,
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : checkbox + titre + reason
          InkWell(
            onTap: () => notifier.toggleSuggestedAngle(index),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? PhosphorIcons.checkSquare(PhosphorIconsStyle.fill)
                        : PhosphorIcons.square(),
                    size: 20,
                    color: selected
                        ? FacteurColors.veille
                        : const Color(0xFF8B7E63),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          angle.title as String,
                          style: GoogleFonts.dmSans(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2C2A29),
                            height: 1.3,
                          ),
                        ),
                        if ((angle.reason as String?)?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 4),
                          Text(
                            angle.reason as String,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              color: const Color(0xFF5D5B5A),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Keywords chips (visibles que si coché)
          if (selected) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: FacteurColors.veilleLineSoft,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final kw in (angle.keywords as List<String>))
                        _KeywordChip(
                          label: kw,
                          onRemove: () =>
                              notifier.removeKeywordFromAngle(index, kw),
                        ),
                      _AddKeywordChip(
                        onTap: () => _openAddKeywordSheet(context, notifier, index),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
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

class _AddKeywordChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddKeywordChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FacteurColors.veilleTint,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: FacteurColors.veille),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.plus(), size: 12, color: FacteurColors.veille),
              const SizedBox(width: 4),
              Text(
                'Ajouter',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FacteurColors.veille,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddAngleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddAngleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FacteurColors.veilleLineSoft,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(PhosphorIcons.plus(), size: 16, color: FacteurColors.veille),
            const SizedBox(width: 10),
            Text(
              'Ajouter un angle perso',
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

class _EmptyAnglesState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyAnglesState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFDFBF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: FacteurColors.veilleLineSoft),
      ),
      child: Column(
        children: [
          Text(
            'Aucun angle suggéré pour l\'instant.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: const Color(0xFF5D5B5A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ajoute un angle perso pour continuer.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: const Color(0xFF8B7E63),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _openAddAngleSheet(
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
              'Ajouter un angle',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ex : « Tests cliniques en oncologie », « Politique numérique européenne »',
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
                hintText: 'Ton angle',
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
  if (result != null && result.isNotEmpty) notifier.addCustomAngle(result);
}

Future<void> _openAddKeywordSheet(
  BuildContext context,
  VeilleConfigNotifier notifier,
  int angleIndex,
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
  if (result != null && result.isNotEmpty) {
    notifier.addKeywordToAngle(angleIndex, result);
  }
}
