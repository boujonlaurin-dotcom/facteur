import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../shared/widgets/loaders/facteur_loader.dart';
import '../../models/veille_config_dto.dart';
import '../../providers/veille_angles_provider.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 2 — angles optionnels pour la veille.
///
/// Veille C3 (PR-3) : la suggestion LLM des angles est ré-introduite. À
/// l'entrée du Step 2, on fetch `POST /veille/suggest/angles` (thème + brief)
/// et on affiche chaque angle comme une carte « titre + grappe de mots-clés
/// éditable » sélectionnable (opt-in). Le sujet principal est fixé en Step 1.
/// Un toggle "Configuration avancée" expose les mots-clés libres.
class Step2SuggestionsScreen extends ConsumerWidget {
  final VoidCallback onClose;
  const Step2SuggestionsScreen({super.key, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final theme = state.selectedTheme;
    final anglesAsync = theme == null
        ? const AsyncValue<List<VeilleAngleSuggestionDto>>.data(
            <VeilleAngleSuggestionDto>[],
          )
        : ref.watch(
            veilleAnglesProvider((
              themeId: theme,
              themeLabel: state.resolvedThemeLabel(
                veilleThemeLabelForSlug(theme),
              ),
              brief: state.editorialBrief ?? '',
            )),
          );

    // Story 23.4 — le sujet principal du Step 1 satisfait déjà l'upsert (≥1
    // topic garanti), donc la CTA n'est plus gatée par une sélection
    // supplémentaire : angles et preset topics deviennent optionnels.
    final hasSelection =
        state.mainTopicSlug != null ||
        state.selectedTopics.isNotEmpty ||
        state.selectedSuggestions.isNotEmpty;

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
                const VeilleFlowH1('Affine ta veille'),
                const SizedBox(height: 8),
                Text(
                  state.mainTopicSlug != null
                      ? 'Ton sujet principal est fixé. Ajoute des angles pour '
                            'préciser — ou passe directement à la suite.'
                      : 'Ajoute des angles si tu veux préciser la veille, ou '
                            'passe directement à la suite.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.45,
                  ),
                ),
                if (state.mainTopicSlug != null) ...[
                  const SizedBox(height: 16),
                  _MainTopicChip(
                    label:
                        state.mainTopicLabel ??
                        state.topicLabels[state.mainTopicSlug!] ??
                        state.mainTopicSlug!,
                  ),
                ],
                const SizedBox(height: 22),
                _AnglesSection(
                  anglesAsync: anglesAsync,
                  state: state,
                  notifier: notifier,
                ),
                const SizedBox(height: 24),
                _AdvancedToggle(
                  expanded: state.advancedMode,
                  onTap: () => notifier.setAdvancedMode(!state.advancedMode),
                ),
                if (state.advancedMode) ...[
                  const SizedBox(height: 16),
                  _KeywordsSection(state: state, notifier: notifier),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: FacteurColors.veilleLineSoft),
            ),
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

/// Story 23.4 — chip non-supprimable du sujet principal (fixé en Step 1).
/// Évite le double-ask et signale que ce sujet gate déjà la veille.
class _MainTopicChip extends StatelessWidget {
  final String label;
  const _MainTopicChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veille, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
            size: 16,
            color: FacteurColors.veille,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUJET PRINCIPAL',
                  style: GoogleFonts.courierPrime(
                    fontSize: 9,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: FacteurColors.veille,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloc « Angles suggérés » (LLM). Affiché au-dessus des preset topics.
/// Pendant le fetch (~10-15 s) : un [FacteurLoader]. Liste vide (LLM KO ou
/// thème sans angle) → rien (on retombe sur les preset topics → pas de
/// régression).
class _AnglesSection extends StatelessWidget {
  final AsyncValue<List<VeilleAngleSuggestionDto>> anglesAsync;
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _AnglesSection({
    required this.anglesAsync,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    return anglesAsync.when(
      loading: () => const _AnglesLoading(),
      error: (_, __) => const SizedBox.shrink(),
      data: (angles) {
        if (angles.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ANGLES SUGGÉRÉS',
              style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: const Color(0xFF8B7E63),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Des angles proposés pour ton thème. Touche pour en suivre un — '
              'tu peux ajuster ses mots-clés.',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: const Color(0xFF5D5B5A),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < angles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _AngleCard(angle: angles[i], state: state, notifier: notifier),
            ],
            const SizedBox(height: 22),
          ],
        );
      },
    );
  }
}

class _AnglesLoading extends StatelessWidget {
  const _AnglesLoading();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        children: [
          const FacteurLoader(width: 64, height: 64),
          const SizedBox(height: 8),
          Text(
            'Recherche d\'angles pour ton thème…',
            style: GoogleFonts.dmSans(
              fontSize: 12.5,
              color: const Color(0xFF8B7E63),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carte d'un angle LLM : en-tête tapable (checkbox + titre + raison) qui
/// active/désactive l'angle (opt-in), puis la grappe de mots-clés. Les chips
/// ne sont éditables (supprimables + ajout) qu'une fois l'angle sélectionné ;
/// sinon ils s'affichent en aperçu statique.
class _AngleCard extends StatelessWidget {
  final VeilleAngleSuggestionDto angle;
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _AngleCard({
    required this.angle,
    required this.state,
    required this.notifier,
  });

  @override
  Widget build(BuildContext context) {
    final slug = VeilleConfigNotifier.angleSlug(angle.title);
    final selected = state.selectedSuggestions.contains(slug);
    final keywords = selected
        ? (state.angleKeywords[slug] ?? const <String>[])
        : angle.keywords;
    final showChips = keywords.isNotEmpty || selected;

    return Container(
      decoration: BoxDecoration(
        color: selected ? FacteurColors.veilleTint : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? FacteurColors.veille : FacteurColors.veilleLineSoft,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => notifier.toggleAngle(angle),
              child: Padding(
                padding: const EdgeInsets.all(12),
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
                          ? const Icon(
                              Icons.check,
                              size: 11,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            angle.title,
                            style: GoogleFonts.dmSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: const Color(0xFF2C2A29),
                            ),
                          ),
                          if (angle.reason != null &&
                              angle.reason!.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              angle.reason!,
                              style: GoogleFonts.dmSans(
                                fontSize: 11.5,
                                height: 1.4,
                                color: const Color(0xFF959392),
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
          ),
          if (showChips)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final kw in keywords)
                    _KeywordChip(
                      label: kw,
                      onRemove: selected
                          ? () => notifier.removeAngleKeyword(slug, kw)
                          : null,
                    ),
                  if (selected &&
                      keywords.length < VeilleConfigNotifier.maxAngleKeywords)
                    _AddKeywordButton(
                      enabled: true,
                      onTap: () =>
                          _openAddAngleKeywordSheet(context, notifier, slug),
                    ),
                ],
              ),
            ),
        ],
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
                _KeywordChip(
                  label: kw,
                  onRemove: () => notifier.removeKeyword(kw),
                ),
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

/// Chip d'un mot-clé. `onRemove == null` → aperçu statique (pas d'icône X, pas
/// de tap) ; sinon supprimable au tap.
class _KeywordChip extends StatelessWidget {
  final String label;
  final VoidCallback? onRemove;
  const _KeywordChip({required this.label, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
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
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            Icon(PhosphorIcons.x(), size: 12, color: const Color(0xFF8B7E63)),
          ],
        ],
      ),
    );
    if (onRemove == null) return chip;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onRemove,
        borderRadius: BorderRadius.circular(20),
        child: chip,
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
              color: enabled ? FacteurColors.veille : const Color(0xFFB8B0A0),
            ),
            const SizedBox(width: 4),
            Text(
              enabled ? 'Ajouter un mot-clé' : 'Limite atteinte',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: enabled ? FacteurColors.veille : const Color(0xFFB8B0A0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mot-clé libre global (config avancée) → `notifier.addKeyword`.
Future<void> _openAddKeywordSheet(
  BuildContext context,
  VeilleConfigNotifier notifier,
) => _showAddKeywordSheet(
  context,
  subtitle: 'Sera utilisé pour filtrer les articles (titre, description).',
  hint: 'Ex : gpt-5',
  onAdd: notifier.addKeyword,
);

/// Mot-clé ajouté à la grappe d'un angle → `notifier.addAngleKeyword(slug, …)`.
Future<void> _openAddAngleKeywordSheet(
  BuildContext context,
  VeilleConfigNotifier notifier,
  String slug,
) => _showAddKeywordSheet(
  context,
  subtitle: 'Affine cet angle — filtre les articles sur ce terme.',
  hint: 'Ex : régulation',
  onAdd: (kw) => notifier.addAngleKeyword(slug, kw),
);

/// Bottom sheet partagé de saisie d'un mot-clé. `onAdd` reçoit le texte trimé
/// non-vide ; la normalisation/dédupe est faite côté notifier.
Future<void> _showAddKeywordSheet(
  BuildContext context, {
  required String subtitle,
  required String hint,
  required void Function(String) onAdd,
}) async {
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
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: hint,
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
  if (result != null && result.isNotEmpty) onAdd(result);
}
