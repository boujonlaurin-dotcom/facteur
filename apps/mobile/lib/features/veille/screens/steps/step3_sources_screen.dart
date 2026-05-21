import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../models/veille_config.dart';
import '../../models/veille_config_dto.dart';
import '../../providers/veille_config_provider.dart';
import '../../widgets/veille_add_source_sheet.dart';
import '../../widgets/veille_source_card.dart';
import '../../widgets/veille_widgets.dart';

/// Step 3 — Story 23.3 refonte :
///   - Liste principale = `state.suggestedSources` (LLM, hydratée par
///     /suggest/sources lancé pendant la transition Step2→Step3).
///   - Sources curées pre-applied (preset) affichées en complément si présentes.
///   - Mode advanced URL (déjà OK).
///   - canSubmit = au moins 1 source sélectionnée (LLM suggérée OU catalogue OU URL).
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

    final hasSelectedSuggested = state.selectedSuggestedSourceIndexes.isNotEmpty;
    final hasRealCuratedSource = state.realSelectedSourceCount > 0;
    final canSubmit = (hasSelectedSuggested || hasRealCuratedSource) && !state.isSubmitting;

    // Sources catalogue déjà appliquées (preset / customSourceAdded). Affichées
    // en complément des sources LLM.
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
                  state.suggestedSources.isEmpty
                      ? 'Le facteur n\'a pas trouvé de source à proposer. Tu peux '
                          'ajouter manuellement par URL ci-dessous.'
                      : 'Le facteur a sélectionné ces sources pour matcher tes '
                          'angles. Décoche celles que tu ne veux pas suivre.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: const Color(0xFF5D5B5A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                if (state.suggestedSources.isNotEmpty)
                  _SuggestedSourcesList(state: state, notifier: notifier),
                if (curatedSources.isNotEmpty) ...[
                  if (state.suggestedSources.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'AUTRES SOURCES',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: const Color(0xFF8B7E63),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                ],
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
                if (!canSubmit) ...[
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

class _SuggestedSourcesList extends StatelessWidget {
  final VeilleConfigState state;
  final VeilleConfigNotifier notifier;
  const _SuggestedSourcesList({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (int i = 0; i < state.suggestedSources.length; i++) {
      final src = state.suggestedSources[i];
      final selected = state.selectedSuggestedSourceIndexes.contains(i);
      cards.add(_SuggestedSourceCard(
        source: src,
        selected: selected,
        onToggle: () => notifier.toggleSuggestedSource(i),
      ));
    }
    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          cards[i],
        ],
      ],
    );
  }
}

class _SuggestedSourceCard extends StatelessWidget {
  final VeilleSourceSuggestionDto source;
  final bool selected;
  final VoidCallback onToggle;
  const _SuggestedSourceCard({
    required this.source,
    required this.selected,
    required this.onToggle,
  });

  String get _domain {
    final uri = Uri.tryParse(source.url);
    return uri?.host ?? source.url;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? FacteurColors.veilleTint : const Color(0xFFFDFBF7),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? FacteurColors.veille : FacteurColors.veilleLineSoft,
              width: 1.4,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 38,
                  height: 38,
                  color: Colors.white,
                  child: Image.network(
                    'https://www.google.com/s2/favicons?sz=128&domain=$_domain',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(
                        source.name.isNotEmpty
                            ? source.name[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.fraunces(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: FacteurColors.veille,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2C2A29),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _domain,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: const Color(0xFF8B7E63),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((source.why ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        source.why!,
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
              const SizedBox(width: 8),
              Icon(
                selected
                    ? PhosphorIcons.checkSquare(PhosphorIconsStyle.fill)
                    : PhosphorIcons.square(),
                size: 22,
                color:
                    selected ? FacteurColors.veille : const Color(0xFF8B7E63),
              ),
            ],
          ),
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
