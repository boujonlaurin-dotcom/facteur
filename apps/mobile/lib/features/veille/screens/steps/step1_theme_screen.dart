import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_presets_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_widgets.dart';

/// Step 1 — Story 23.3 refonte simplifiée :
///   1) Grid 10 thèmes (9 Facteur + "Autre" custom)
///   2) Champ libre "Précise ton angle" (fusion ancien purpose+editorialBrief)
/// Au tap "Continuer" → startTransition(1) qui déclenche /suggest/angles.
class Step1ThemeScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const Step1ThemeScreen({super.key, required this.onClose});

  @override
  ConsumerState<Step1ThemeScreen> createState() => _Step1ThemeScreenState();
}

class _Step1ThemeScreenState extends ConsumerState<Step1ThemeScreen> {
  final GlobalKey _briefSectionKey = GlobalKey();
  int _openSection = 1;
  bool _didAutoOpenSection2 = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final hasTheme = state.selectedTheme != null;
    final isOther = state.selectedTheme == kVeilleOtherThemeSlug;
    final customLabelOk = !isOther || (state.customThemeLabel ?? '').trim().isNotEmpty;
    final canContinue = hasTheme && customLabelOk;

    final selectedThemeLabel = state.selectedTheme == null
        ? ''
        : (isOther
            ? (state.customThemeLabel ?? 'Autre')
            : veilleThemeLabelForSlug(state.selectedTheme!));

    final themesAsync = ref.watch(veilleThemesProvider);

    // Auto-ouvre la section 2 (brief) dès qu'un thème est choisi.
    ref.listen<String?>(
      veilleConfigProvider.select((s) => s.selectedTheme),
      (prev, next) {
        if (!_didAutoOpenSection2 && prev == null && next != null) {
          _didAutoOpenSection2 = true;
          setState(() => _openSection = 2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _briefSectionKey.currentContext;
            if (ctx != null) {
              Scrollable.ensureVisible(
                ctx,
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                alignment: 0.05,
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
                  subtitleWhenCollapsed:
                      hasTheme ? selectedThemeLabel.toUpperCase() : null,
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
              child: _Footer(onTap: () => notifier.startTransition(1)),
            ),
          ),
        ),
      ],
    );
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
                borderSide: const BorderSide(color: FacteurColors.veilleLineSoft),
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
