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

/// Step 3 — choix des sources pour la veille.
///
/// PR-4 (Story 23.3) : la suggestion LLM des sources a été supprimée.
/// L'écran affiche les sources curées déjà appliquées (depuis un preset ou
/// l'historique de la config en mode édition). Un toggle "Configuration
/// avancée" ouvre `VeilleAddSourceSheet` pour ajouter une source par URL.
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

    final canSubmit = state.realSelectedSourceCount > 0 && !state.isSubmitting;

    // Sources catalogue déjà appliquées (preset / customSourceAdded). Affichées
    // d'abord les sélectionnées, puis le reste (preset non-cochés p.ex.).
    final curatedSources = <VeilleSource>[];
    final seen = <String>{};
    for (final id in state.selectedSourceIds) {
      final meta = state.sourcesMeta[id];
      if (meta?.apiSourceId == null) continue;
      if (!seen.add(id)) continue;
      curatedSources.add(_metaToUiSource(meta!));
    }
    for (final entry in state.sourcesMeta.entries) {
      if (state.selectedSourceIds.contains(entry.key)) continue;
      if (entry.value.apiSourceId == null) continue;
      if (!seen.add(entry.key)) continue;
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
                const VeilleFlowH1('Quelles sources veux-tu suivre ?'),
                const SizedBox(height: 8),
                Text(
                  curatedSources.isEmpty
                      ? 'Ajoute une source par URL pour démarrer ta veille — '
                          'un blog niche, un flux RSS, etc.'
                      : 'Décoche celles que tu ne veux pas suivre, ou ajoute '
                          'une source par URL via la configuration avancée.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                if (curatedSources.isNotEmpty)
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
                    onTap: () => _openAddSheet(context, notifier),
                  ),
                ],
                if (!canSubmit && !state.isSubmitting) ...[
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
