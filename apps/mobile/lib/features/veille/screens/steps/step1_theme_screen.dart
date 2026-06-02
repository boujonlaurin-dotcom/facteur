import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../onboarding/data/available_subtopics.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_presets_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 1 :
///   1) Grid 10 thèmes (9 Facteur + "Autre" custom)
///   2) Champ libre "Précise ton angle" (fusion ancien purpose+editorialBrief)
/// Au tap "Continuer" → goNext() (passage à Step 2).
class Step1ThemeScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const Step1ThemeScreen({super.key, required this.onClose});

  @override
  ConsumerState<Step1ThemeScreen> createState() => _Step1ThemeScreenState();
}

class _Step1ThemeScreenState extends ConsumerState<Step1ThemeScreen> {
  final GlobalKey _briefSectionKey = GlobalKey();
  final GlobalKey _subtopicSectionKey = GlobalKey();
  final TextEditingController _customTopicCtrl = TextEditingController();
  int _openSection = 1;
  bool _showCustomTopicCard = false;
  bool _resolvingCustomTopic = false;
  String? _customTopicError;

  @override
  void dispose() {
    _customTopicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final hasTheme = state.selectedTheme != null;
    final isOther = state.selectedTheme == kVeilleOtherThemeSlug;
    final customLabelOk =
        !isOther || (state.customThemeLabel ?? '').trim().isNotEmpty;
    // Story 23.4 — sujets granulaires du macro choisi (drill macro→topic).
    final subtopics = (hasTheme && !isOther)
        ? (AvailableSubtopics.byTheme[state.selectedTheme] ?? const [])
        : const <SubtopicOption>[];
    // Le sujet principal granulaire est le gate obligatoire. Exceptions : thème
    // "Autre" (chemin free-text) et macro sans sous-thèmes connus (rare) — dans
    // ces cas le user peut continuer sans granulaire.
    final needsMainTopic = hasTheme && !isOther && subtopics.isNotEmpty;
    final hasMainTopic =
        state.mainTopicSlug != null ||
        state.selectedTopics.isNotEmpty; // presets : topics déjà choisis
    final canContinue =
        hasTheme && customLabelOk && (!needsMainTopic || hasMainTopic);

    final selectedThemeLabel = state.selectedTheme == null
        ? ''
        : (isOther
              ? (state.customThemeLabel ?? 'Autre')
              : veilleThemeLabelForSlug(state.selectedTheme!));

    final themesAsync = ref.watch(veilleThemesProvider);

    // Après choix du thème, scroll vers la section immédiatement suivante :
    // la grille de sujets précis en priorité, le brief seulement en fallback.
    ref.listen<String?>(veilleConfigProvider.select((s) => s.selectedTheme), (
      prev,
      next,
    ) {
      if (prev != next && next != null) {
        final hasSubtopics =
            next != kVeilleOtherThemeSlug &&
            (AvailableSubtopics.byTheme[next] ?? const []).isNotEmpty;
        setState(() => _openSection = hasSubtopics ? 1 : 2);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = hasSubtopics
              ? _subtopicSectionKey.currentContext
              : _briefSectionKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              alignment: 0.08,
            );
          }
        });
      }
    });

    return Column(
      children: [
        VeilleStepHeader(step: 1, canGoBack: false, onClose: widget.onClose),
        _PresetTeaserLink(onTap: () => _openPresetSheet(context)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilleToggleSection(
                  index: 1,
                  title:
                      'Sur quel thème aimerais-tu recevoir un condensé des '
                      'meilleurs articles récents ?',
                  subtitleWhenCollapsed: hasTheme
                      ? selectedThemeLabel.toUpperCase()
                      : null,
                  expanded: _openSection == 1,
                  onToggle: () => setState(() => _openSection = 1),
                  child: themesAsync.when(
                    loading: () => const _ThemeGridSkeleton(),
                    error: (_, __) => _ThemeGrid(
                      themes: const [],
                      selected: state.selectedTheme,
                      onSelect: notifier.selectTheme,
                      errorState: true,
                    ),
                    data: (themes) => _ThemeGrid(
                      themes: themes,
                      selected: state.selectedTheme,
                      onSelect: notifier.selectTheme,
                    ),
                  ),
                ),
                if (isOther) ...[
                  const SizedBox(height: 12),
                  _OtherThemeLabelField(
                    initial: state.customThemeLabel ?? '',
                    onChanged: notifier.setCustomThemeLabel,
                  ),
                ],
                if (subtopics.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Column(
                    key: _subtopicSectionKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SubtopicGrid(
                        subtopics: subtopics,
                        selected: state.mainTopicSlug,
                        customSelected:
                            state.mainTopicSlug?.startsWith('custom-') ?? false,
                        onSelect: (o) {
                          setState(() {
                            _showCustomTopicCard = false;
                            _customTopicError = null;
                          });
                          notifier.selectMainTopic(o.slug, o.label);
                        },
                        onOther: () {
                          setState(() {
                            _showCustomTopicCard = true;
                            _customTopicError = null;
                          });
                        },
                      ),
                      if (_showCustomTopicCard) ...[
                        const SizedBox(height: 10),
                        _CustomTopicCard(
                          controller: _customTopicCtrl,
                          loading: _resolvingCustomTopic,
                          error: _customTopicError,
                          onSubmit: () => _submitCustomTopic(notifier),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                VeilleToggleSection(
                  index: 2,
                  title: 'Précise ton angle',
                  enabled: hasTheme,
                  expanded: _openSection == 2 && hasTheme,
                  subtitleWhenCollapsed:
                      (state.editorialBrief ?? '').trim().isEmpty
                      ? null
                      : 'BRIEF RENSEIGNÉ',
                  onToggle: () {
                    if (!hasTheme) return;
                    setState(() => _openSection = 2);
                  },
                  child: Column(
                    key: _briefSectionKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'En quelques mots, décris ce qui t\'intéresse : un angle '
                        'précis, un objectif, une zone géographique, un format. '
                        'Le facteur s\'en servira pour te proposer des angles '
                        'sur-mesure à l\'étape suivante.',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          height: 1.45,
                          color: const Color(0xFF5D5B5A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      VeilleEditorialBriefField(
                        value: state.editorialBrief,
                        onChanged: notifier.setEditorialBrief,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: canContinue ? Offset.zero : const Offset(0, 1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: canContinue ? 1 : 0,
            child: IgnorePointer(
              ignoring: !canContinue,
              child: _Footer(onTap: notifier.goNext),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitCustomTopic(VeilleConfigNotifier notifier) async {
    final raw = _customTopicCtrl.text.trim();
    if (raw.length < 2 || _resolvingCustomTopic) return;
    setState(() {
      _resolvingCustomTopic = true;
      _customTopicError = null;
    });
    try {
      await notifier.resolveCustomMainTopic(raw);
      if (!mounted) return;
      setState(() {
        _showCustomTopicCard = false;
        _resolvingCustomTopic = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvingCustomTopic = false;
        _customTopicError =
            'Impossible d\'enrichir ce sujet pour l\'instant. Réessaie.';
      });
    }
  }
}

class _ThemeGrid extends StatelessWidget {
  final List<VeilleTheme> themes;
  final String? selected;
  final ValueChanged<String> onSelect;
  final bool errorState;
  const _ThemeGrid({
    required this.themes,
    required this.selected,
    required this.onSelect,
    this.errorState = false,
  });

  @override
  Widget build(BuildContext context) {
    if (themes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          errorState
              ? 'Impossible de charger tes thèmes. Vérifie ta connexion et reviens.'
              : 'Aucun thème disponible.',
          style: const TextStyle(color: Color(0xFF8B7E63), fontSize: 13),
        ),
      );
    }
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

/// Story 23.4 — 2ᵉ grille (granulaire) révélée après le choix du macro :
/// l'utilisateur fixe le **sujet principal** qui gate la curation (slug
/// canonique). Réutilise le visuel `ThemeCard`.
class _SubtopicGrid extends StatelessWidget {
  final List<SubtopicOption> subtopics;
  final String? selected;
  final bool customSelected;
  final ValueChanged<SubtopicOption> onSelect;
  final VoidCallback onOther;
  const _SubtopicGrid({
    required this.subtopics,
    required this.selected,
    required this.customSelected,
    required this.onSelect,
    required this.onOther,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quel sujet précis veux-tu suivre ?',
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: const Color(0xFF2C2A29),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'On cible ta veille sur ce sujet — tu pourras ajouter des angles à '
          'l\'étape suivante.',
          style: GoogleFonts.dmSans(
            fontSize: 13,
            height: 1.45,
            color: const Color(0xFF5D5B5A),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.55,
          children: [
            for (final o in subtopics)
              ThemeCard(
                theme: VeilleTheme(
                  id: o.slug,
                  label: o.label,
                  meta: '',
                  iconKey: '',
                  emoji: o.emoji,
                  hot: o.isPopular,
                ),
                selected: selected == o.slug,
                onTap: () => onSelect(o),
              ),
            ThemeCard(
              theme: const VeilleTheme(
                id: kVeilleOtherTopicSlug,
                label: 'Autre',
                meta: '',
                iconKey: '',
                emoji: '✎',
              ),
              selected: customSelected,
              onTap: onOther,
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomTopicCard extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  const _CustomTopicCard({
    required this.controller,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veilleLineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sujet sur-mesure',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C2A29),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !loading,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ex : Musées contemporains à Barcelone',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: FacteurColors.veilleLineSoft,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    counterText: '',
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: loading ? null : onSubmit,
                style: IconButton.styleFrom(
                  backgroundColor: FacteurColors.veille,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFD2C9BB),
                ),
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(PhosphorIcons.check()),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: const Color(0xFF9B3D2E),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeGridSkeleton extends StatelessWidget {
  const _ThemeGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.55,
      children: List.generate(
        6,
        (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F0E5),
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Champ visible juste sous la grid quand l'user a sélectionné "Autre" :
/// permet de saisir un theme_label libre (ex : "Musées contemporains Barcelone").
class _OtherThemeLabelField extends StatefulWidget {
  final String initial;
  final ValueChanged<String?> onChanged;
  const _OtherThemeLabelField({required this.initial, required this.onChanged});

  @override
  State<_OtherThemeLabelField> createState() => _OtherThemeLabelFieldState();
}

class _OtherThemeLabelFieldState extends State<_OtherThemeLabelField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FacteurColors.veilleLineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quel sujet ?',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2C2A29),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ex : « Musées contemporains à Barcelone », « Droit du numérique européen ».',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: const Color(0xFF8B7E63),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Ton sujet',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: FacteurColors.veilleLineSoft,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              counterText: '',
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    );
  }
}

/// Lien teaser sous le header Step1 — visible sans scroll. Tap → ouvre
/// la bottom sheet `_VeillePresetsSheet`.
class _PresetTeaserLink extends StatelessWidget {
  final VoidCallback onTap;
  const _PresetTeaserLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Material(
        color: FacteurColors.veilleTint,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.sparkle(),
                  size: 16,
                  color: FacteurColors.veille,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pas inspiré ? Pioche un pré-set',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FacteurColors.veille,
                    ),
                  ),
                ),
                Icon(
                  PhosphorIcons.arrowRight(),
                  size: 14,
                  color: FacteurColors.veille,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _openPresetSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFF2E8D5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const _VeillePresetsSheet(),
  );
}

class _VeillePresetsSheet extends ConsumerWidget {
  const _VeillePresetsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPresets = ref.watch(veillePresetsProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2A29).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pré-sets',
                    style: GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: const Color(0xFF2C2A29),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Une veille curée prête à l\'emploi.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: const Color(0xFF5D5B5A),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: asyncPresets.when(
                  loading: () => const _PresetCardSkeleton(),
                  error: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Pré-sets indisponibles. Réessaie dans un instant.',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: const Color(0xFF8B7E63),
                      ),
                    ),
                  ),
                  data: (presets) {
                    if (presets.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Aucun pré-set disponible pour l\'instant.',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            color: const Color(0xFF8B7E63),
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < presets.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          PresetCard(
                            label: presets[i].label,
                            accroche: presets[i].accroche,
                            icon: phosphorThemeIcon(presets[i].themeId),
                            onTap: () {
                              Navigator.of(context).pop();
                              notifier.openPresetPreview(presets[i].slug);
                            },
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetCardSkeleton extends StatelessWidget {
  const _PresetCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: Container(
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0E5),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
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
        border: Border(top: BorderSide(color: Color(0xFFE6E1D6), width: 1)),
      ),
      child: VeilleCtaButton(
        label: 'Continuer',
        trailingIcon: PhosphorIcons.arrowRight(),
        onPressed: onTap,
      ),
    );
  }
}
