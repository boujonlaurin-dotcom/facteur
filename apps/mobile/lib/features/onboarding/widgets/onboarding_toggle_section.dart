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
class OnboardingToggleSection extends StatefulWidget {
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

  /// Section déjà parcourue / validée (l'utilisateur est passé à la suivante) :
  /// le badge numéroté reste affiché avec un check vert persistant.
  final bool validated;
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
    this.validated = false,
  });

  @override
  State<OnboardingToggleSection> createState() =>
      _OnboardingToggleSectionState();
}

class _OnboardingToggleSectionState extends State<OnboardingToggleSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _validateController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _validateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      // Déjà validée au premier build (rebuild / restauration) : afficher
      // directement l'état final sans rejouer la pulse.
      value: widget.validated ? 1.0 : 0.0,
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_validateController);
  }

  @override
  void didUpdateWidget(OnboardingToggleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Section nouvellement validée (l'utilisateur passe à la suivante) :
    // brève pulsation, puis le badge reste sur son check vert persistant.
    if (!oldWidget.validated && widget.validated) {
      _validateController.forward(from: 0);
    } else if (oldWidget.validated && !widget.validated) {
      // Retour en arrière : on réinitialise l'état du badge.
      _validateController.value = 0;
    }
  }

  @override
  void dispose() {
    _validateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final headerColor =
        widget.enabled ? colors.textPrimary : colors.textTertiary;
    final index = widget.index;
    final title = widget.title;
    final expanded = widget.expanded;
    final enabled = widget.enabled;
    final onToggle = widget.onToggle;
    final subtitleWhenCollapsed = widget.subtitleWhenCollapsed;
    final description = widget.description;
    final child = widget.child;

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
                _SectionIndexBadge(
                  index: index,
                  enabled: enabled,
                  validated: widget.validated,
                  scaleAnim: _scaleAnim,
                  validateController: _validateController,
                ),
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
                          subtitleWhenCollapsed.isNotEmpty) ...[
                        const SizedBox(height: FacteurSpacing.space1),
                        Text(
                          subtitleWhenCollapsed,
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
                      if (description != null && description.isNotEmpty) ...[
                        Text(
                          description,
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
  final bool validated;
  final Animation<double> scaleAnim;
  final AnimationController validateController;

  const _SectionIndexBadge({
    required this.index,
    required this.enabled,
    required this.validated,
    required this.scaleAnim,
    required this.validateController,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final baseAccent = enabled ? colors.primary : colors.textTertiary;
    final validatedColor = Colors.green.shade500;

    return AnimatedBuilder(
      animation: validateController,
      builder: (context, _) {
        final t = validateController.value;
        // Une fois validée, la section conserve son check vert ; pendant la
        // pulse (t montant) on bascule tôt sur le check pour l'effet visuel.
        final showCheck = validated || t > 0.2;
        // Couleur : vire au vert dès la pulse et y reste tant que validée.
        final accent = Color.lerp(
              baseAccent,
              validatedColor,
              validated ? 1.0 : (t * 2).clamp(0.0, 1.0),
            ) ??
            baseAccent;

        return Transform.scale(
          scale: scaleAnim.value,
          child: Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? accent.withValues(alpha: 0.10)
                  : colors.backgroundSecondary,
              border:
                  Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
            ),
            alignment: Alignment.center,
            child: showCheck
                ? Icon(PhosphorIcons.check(), size: 14, color: accent)
                : Text(
                    '$index',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                  ),
          ),
        );
      },
    );
  }
}
