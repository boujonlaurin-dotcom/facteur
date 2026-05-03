import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/veille_config.dart';
import '../../providers/veille_config_provider.dart';
import '../../providers/veille_preset_topics_provider.dart';
import '../../providers/veille_presets_provider.dart';
import '../../providers/veille_themes_provider.dart';
import '../../widgets/veille_widgets.dart';

class Step1ThemeScreen extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const Step1ThemeScreen({super.key, required this.onClose});

  @override
  ConsumerState<Step1ThemeScreen> createState() => _Step1ThemeScreenState();
}

class _Step1ThemeScreenState extends ConsumerState<Step1ThemeScreen> {
  final GlobalKey _q2BodyKey = GlobalKey();
  int _openSection = 1;
  bool _didAutoOpenQ2 = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final hasTheme = state.selectedTheme != null;
    final selectedThemeLabel = state.selectedTheme == null
        ? ''
        : veilleThemeLabelForSlug(state.selectedTheme!);

    final themesAsync = ref.watch(veilleThemesProvider);

    ref.listen<String?>(
      veilleConfigProvider.select((s) => s.selectedTheme),
      (prev, next) {
        if (!_didAutoOpenQ2 && prev == null && next != null) {
          _didAutoOpenQ2 = true;
          setState(() => _openSection = 2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _q2BodyKey.currentContext;
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
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VeilleToggleSection(
                  index: 1,
                  title: 'Sur quel sujet veux-tu une veille ?',
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
                const SizedBox(height: 18),
                VeilleToggleSection(
                  index: 2,
                  title: 'Précise ce qui t\'intéresse',
                  expanded: _openSection == 2 && hasTheme,
                  enabled: hasTheme,
                  onToggle: () {
                    if (!hasTheme) return;
                    setState(() => _openSection = 2);
                  },
                  child: Column(
                    key: _q2BodyKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Indique les sujets précis sur lesquels tu aimerais '
                        'qu\'on focalise ta veille. Ça permet à Facteur '
                        'd\'orienter la recherche sur les meilleures sources '
                        'et articles, et de t\'aider à comprendre les angles '
                        'qui t\'intéressent vraiment sur le sujet.',
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          height: 1.45,
                          color: const Color(0xFF5D5B5A),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      if (state.selectedTheme != null)
                        _PresetTopicsList(themeSlug: state.selectedTheme!),
                      const SizedBox(height: 10),
                      AddTopicCard(
                        label: 'Ajouter un sujet',
                        reason: 'Décris un angle précis qui te manque',
                        onTap: () => _openAddTopicSheet(
                          context,
                          (label) => notifier.addCustomTopic(label),
                        ),
                      ),
                      _CustomTopicsList(
                        customTopics: state.customTopics,
                        selected: state.selectedTopics,
                        onToggle: notifier.toggleTopic,
                        onRemove: notifier.removeCustomTopic,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const _InspirationsSection(),
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

class _PresetTopicsList extends ConsumerWidget {
  final String themeSlug;
  const _PresetTopicsList({required this.themeSlug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);
    final asyncTopics = ref.watch(veillePresetTopicsProvider(themeSlug));

    // Hydrate `topicLabels` pour le payload backend — appliqué après le
    // build pour éviter le "ref.read inside build" warning. Idempotent.
    asyncTopics.whenData((topics) {
      if (topics.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifier.registerPresetTopicLabels(topics);
        });
      }
    });

    return asyncTopics.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Impossible de charger les sujets préchargés. Tu peux quand même ajouter les tiens ci-dessous.',
          style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
        ),
      ),
      data: (topics) {
        if (topics.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Pas encore d\'angles préchargés pour ce thème — ajoute-en un ci-dessous.',
              style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
            ),
          );
        }
        return Column(
          children: [
            for (int i = 0; i < topics.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              CheckRow(
                label: topics[i].label,
                reason: topics[i].reason,
                selected: state.selectedTopics.contains(topics[i].id),
                onTap: () => notifier.toggleTopic(topics[i].id),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _CustomTopicsList extends StatelessWidget {
  final List<VeilleTopic> customTopics;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onRemove;
  const _CustomTopicsList({
    required this.customTopics,
    required this.selected,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (customTopics.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (int i = 0; i < customTopics.length; i++) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: CheckRow(
                  label: customTopics[i].label,
                  reason: customTopics[i].reason,
                  selected: selected.contains(customTopics[i].id),
                  onTap: () => onToggle(customTopics[i].id),
                ),
              ),
              IconButton(
                tooltip: 'Retirer ce sujet',
                onPressed: () => onRemove(customTopics[i].id),
                icon: Icon(
                  PhosphorIcons.x(),
                  size: 16,
                  color: const Color(0xFF8B7E63),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> _openAddTopicSheet(
  BuildContext context,
  ValueChanged<String> onAdd,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

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
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + viewInsets.bottom,
        ),
        child: Form(
          key: formKey,
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
                'Ex : « robotique molle », « accessibilité numérique »',
                style: TextStyle(fontSize: 12, color: Color(0xFF8B7E63)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 60,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Ton sujet',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Renseigne un sujet';
                  if (t.length < 2) return 'Trop court';
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.of(ctx).pop(controller.text.trim());
                  }
                },
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
                    onPressed: () {
                      if (formKey.currentState?.validate() ?? false) {
                        Navigator.of(ctx).pop(controller.text.trim());
                      }
                    },
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  controller.dispose();
  if (result != null && result.isNotEmpty) onAdd(result);
}

class _InspirationsSection extends ConsumerWidget {
  const _InspirationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPresets = ref.watch(veillePresetsProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    return asyncPresets.when(
      loading: () => const _PresetCardSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (presets) {
        if (presets.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INSPIRATIONS',
              style: GoogleFonts.courierPrime(
                fontSize: 11,
                letterSpacing: 0.5,
                color: const Color(0xFF8B7E63),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pas sûr·e par où commencer ? Pioche un pré-set.',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: const Color(0xFF5D5B5A),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < presets.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              PresetCard(
                label: presets[i].label,
                accroche: presets[i].accroche,
                icon: phosphorThemeIcon(presets[i].themeId),
                onTap: () => notifier.openPresetPreview(presets[i].slug),
              ),
            ],
          ],
        );
      },
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
