import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Section repliable en accordéon pour l'onboarding (page « Tes médias, sur
/// mesure »). Calquée sur le `VeilleToggleSection` de la config de veille
/// (badge numéroté + titre + corps animé), mais aux couleurs/typo de
/// l'onboarding (via `context.facteurColors` / `Theme.of(context).textTheme`).
///
/// Une seule section est ouverte à la fois (accordéon piloté) : le parent garde
/// l'index ouvert et passe `expanded: openIndex == index`.
class OnboardingToggleSection extends StatelessWidget {
  final int index;
  final String title;

  /// Court résumé affiché sous le titre quand la section est repliée
  /// (ex. « 9 médias sélectionnés »).
  final String? subtitleWhenCollapsed;

  /// Description longue affichée en tête du corps **quand la section est
  /// ouverte** — explique le rôle de la section (ne disparaît pas au clic,
  /// contrairement au [subtitleWhenCollapsed]).
  final String? description;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggle;
  final Widget child;

  const OnboardingToggleSection({
    super.key,
    required this.index,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.subtitleWhenCollapsed,
    this.description,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final headerColor = enabled ? colors.textPrimary : colors.textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? onToggle : null,
          borderRadius: BorderRadius.circular(FacteurRadius.small),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionIndexBadge(index: index, enabled: enabled),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: headerColor,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      if (!expanded &&
                          subtitleWhenCollapsed != null &&
                          subtitleWhenCollapsed!.isNotEmpty) ...[
                        const SizedBox(height: FacteurSpacing.space1),
                        Text(
                          subtitleWhenCollapsed!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    PhosphorIcons.caretDown(),
                    size: 18,
                    color: enabled ? colors.textSecondary : colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Corps construit uniquement à l'ouverture (lazy) : évite de monter le
        // contenu lourd des sections repliées (catalogue, panneau d'ajout qui
        // autofocus la recherche). Animation de hauteur via AnimatedSize.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: FacteurSpacing.space3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (description != null && description!.isNotEmpty) ...[
                        Text(
                          description!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: colors.textSecondary,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: FacteurSpacing.space3),
                      ],
                      child,
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _SectionIndexBadge extends StatelessWidget {
  final int index;
  final bool enabled;

  const _SectionIndexBadge({required this.index, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final accent = enabled ? colors.primary : colors.textTertiary;

    return Container(
      width: 26,
      height: 26,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: enabled
            ? colors.primary.withValues(alpha: 0.10)
            : colors.backgroundSecondary,
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$index',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: accent,
            ),
      ),
    );
  }
}
