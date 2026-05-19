import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_add_source_sheet.dart';
import '../../widgets/veille_source_card.dart';
import '../../widgets/veille_widgets.dart';

/// Step 3 — Sources. Désormais dernière étape du flow (step4 frequency
/// dropé en Story 23.2 PR-4).
///
/// Sources curées affichées depuis `state.sourcesMeta` (hydratées par
/// preset ou par défaut). Plus de curation LLM ranking — le filtre temps-réel
/// backend trie les articles à l'exécution.
///
/// Toggle "Configuration avancée" : révèle le bouton "Ajouter par URL"
/// (réutilise `VeilleAddSourceSheet`). Sans le toggle, l'utilisateur voit
/// uniquement les sources curées + un CTA standard d'ajout.
class Step3SourcesScreen extends ConsumerWidget {
  final VoidCallback onClose;
  final Future<void> Function() onSubmit;

  const Step3SourcesScreen({
    super.key,
    required this.onClose,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final hasRealSource = state.realSelectedSourceCount > 0;
    final canSubmit = hasRealSource && !state.isSubmitting;

    final curatedSources = <VeilleSource>[];
    for (final id in state.selectedSourceIds) {
      final meta = state.sourcesMeta[id];
      if (meta?.apiSourceId == null) continue;
      curatedSources.add(_metaToUiSource(meta!));
    }
    // Si l'utilisateur a désélectionné les sources du preset, on les ré-affiche
    // quand même (en mode désélectionné) — sourceMeta contient toujours leur
    // metadata. Sinon on n'aurait plus rien à proposer.
    for (final entry in state.sourcesMeta.entries) {
      if (state.selectedSourceIds.contains(entry.key)) continue;
      if (entry.value.apiSourceId == null) continue;
      curatedSources.add(_metaToUiSource(entry.value));
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
                const VeilleFlowH1(
                  'Quelles sources veux-tu suivre ?',
                ),
                const SizedBox(height: 8),
                Text(
                  'On a déjà sélectionné des sources reconnues pour ton thème. '
                  'Tu peux décocher celles qui ne t\'intéressent pas.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                if (curatedSources.isEmpty)
                  const _EmptyCuratedSources()
                else
                  Column(
                    children: [
                      for (int i = 0; i < curatedSources.length; i++) ...[
                        if (i > 0) const SizedBox(height: 6),
                        VeilleSourceCard(
                          source: curatedSources[i],
                          inVeille: state.selectedSourceIds
                              .contains(curatedSources[i].id),
                          isAlreadyFollowed: false,
                          onToggle: () =>
                              notifier.toggleSource(curatedSources[i].id),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 24),
                _AdvancedToggle(
                  expanded: state.advancedMode,
                  onTap: () => notifier.setAdvancedMode(!state.advancedMode),
                ),
                if (state.advancedMode) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Ajoute une source par URL — un blog niche, un flux RSS '
                    'spécialisé, etc.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF5D5B5A),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AddSourceButton(
                    onTap: () => _openAddSheet(context, ref, notifier),
                  ),
                ],
                if (!hasRealSource) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Sélectionne au moins une source pour continuer.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: const Color(0xFF8B7E63),
                    ),
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
            label: state.isSubmitting ? 'Enregistrement…' : 'Créer ma veille',
            trailingIcon: PhosphorIcons.check(),
            onPressed: canSubmit ? () => onSubmit() : null,
          ),
        ),
      ],
    );
  }

  void _openAddSheet(
    BuildContext context,
    WidgetRef ref,
    VeilleConfigNotifier notifier,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => VeilleAddSourceSheet(
        onSourceAdded: (SmartSearchResult result) {
          final id = result.sourceId;
          if (id != null && id.isNotEmpty && id != 'null') {
            notifier.addCustomSourceToVeille(
              sourceId: id,
              name: result.name,
              url: result.url,
            );
          }
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  static VeilleSource _metaToUiSource(VeilleSourceMeta meta) {
    final letter = meta.name.isNotEmpty ? meta.name[0].toUpperCase() : '?';
    return VeilleSource(
      id: meta.slug,
      letter: letter,
      name: meta.name,
      meta: meta.kind == 'niche' ? 'Source niche' : 'Source curée',
      why: meta.why,
      logoUrl: meta.url == null
          ? null
          : 'https://www.google.com/s2/favicons?sz=128&domain=${_domain(meta.url!)}',
    );
  }

  static String _domain(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host ?? url;
  }
}

class _EmptyCuratedSources extends StatelessWidget {
  const _EmptyCuratedSources();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veilleLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pas de source curée pour ce thème.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2A2419),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ajoute une source manuellement via "Configuration avancée".',
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

class _AddSourceButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSourceButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FacteurColors.veilleLine,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 16,
                color: FacteurColors.veille,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ajouter une source par URL',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FacteurColors.veille,
                  ),
                ),
              ),
              Icon(
                PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                size: 14,
                color: FacteurColors.veille,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
