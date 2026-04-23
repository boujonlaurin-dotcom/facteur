import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import 'tour_page_scaffold.dart';

/// Page 3 — "Personnalisation" : icônes sources/thèmes + slider priorité.
class TourPagePerso extends StatelessWidget {
  const TourPagePerso({super.key});

  @override
  Widget build(BuildContext context) {
    return const TourPageScaffold(
      title: 'Personnalisation',
      subtitle:
          'Ajoute des sources, crée tes thèmes, affine tes préférences. '
          'L\'app s\'adapte à toi.',
      illustration: _ChipsAndSlider(),
    );
  }
}

class _ChipsAndSlider extends StatefulWidget {
  const _ChipsAndSlider();

  @override
  State<_ChipsAndSlider> createState() => _ChipsAndSliderState();
}

class _ChipsAndSliderState extends State<_ChipsAndSlider>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: 260,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Chip "source" en haut-gauche
              Positioned(
                top: 10,
                left: 0,
                child: _FadeSlide(
                  delay: 0.0,
                  t: t,
                  from: const Offset(-20, 0),
                  child: _Chip(
                    icon: PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                    label: 'Le Monde',
                    color: colors.primary,
                  ),
                ),
              ),
              // Chip "thème" en haut-droite
              Positioned(
                top: 10,
                right: 0,
                child: _FadeSlide(
                  delay: 0.2,
                  t: t,
                  from: const Offset(20, 0),
                  child: _Chip(
                    icon: PhosphorIcons.tag(PhosphorIconsStyle.regular),
                    label: 'Climat',
                    color: colors.secondary,
                  ),
                ),
              ),
              // Chip "+" centre
              Positioned(
                top: 70,
                child: _FadeSlide(
                  delay: 0.35,
                  t: t,
                  from: const Offset(0, -12),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      color: colors.primary,
                      size: 20,
                    ),
                  ),
                ),
              ),
              // Slider priorité en bas
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: _FadeSlide(
                  delay: 0.5,
                  t: t,
                  from: const Offset(0, 16),
                  child: _PrioritySliderMock(colors: colors),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FadeSlide extends StatelessWidget {
  const _FadeSlide({
    required this.delay,
    required this.t,
    required this.from,
    required this.child,
  });

  /// 0..1 — phase où l'élément commence à apparaître.
  final double delay;
  final double t;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final raw = (t - delay) / (1 - delay);
    final p = raw.clamp(0.0, 1.0);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(from.dx * (1 - p), from.dy * (1 - p)),
        child: child,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrioritySliderMock extends StatelessWidget {
  const _PrioritySliderMock({required this.colors});

  final FacteurColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Priorité',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Segment(active: false, color: colors),
              const SizedBox(width: 4),
              _Segment(active: true, color: colors),
              const SizedBox(width: 4),
              _Segment(active: false, color: colors),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.active, required this.color});

  final bool active;
  final FacteurColors color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: active
              ? color.primary
              : color.textTertiary.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
