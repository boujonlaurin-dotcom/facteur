import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'tour_page_scaffold.dart';

/// Page 2 — "Ton flux" : 3 cartes qui défilent horizontalement.
class TourPageFeed extends StatelessWidget {
  const TourPageFeed({super.key});

  @override
  Widget build(BuildContext context) {
    return const TourPageScaffold(
      title: 'Ton flux',
      subtitle:
          'Toutes tes sources suivies, heure par heure. '
          'Tu choisis quoi explorer, quand.',
      illustration: _ScrollingCards(),
    );
  }
}

class _ScrollingCards extends StatefulWidget {
  const _ScrollingCards();

  @override
  State<_ScrollingCards> createState() => _ScrollingCardsState();
}

class _ScrollingCardsState extends State<_ScrollingCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // Glissement continu : les cartes se déplacent de gauche à droite
          // et ré-entrent depuis la gauche.
          return ClipRect(
            child: Stack(
              children: [
                _FloatingCard(phase: (t + 0.00) % 1.0, yOffset: -60),
                _FloatingCard(phase: (t + 0.33) % 1.0, yOffset: 0),
                _FloatingCard(phase: (t + 0.66) % 1.0, yOffset: 60),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FloatingCard extends StatelessWidget {
  const _FloatingCard({required this.phase, required this.yOffset});

  /// 0..1 — position horizontale. 0 = gauche (entrée), 1 = droite (sortie).
  final double phase;
  final double yOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Rendre invisible pendant une petite fenêtre pour éviter le popping
    final visible = phase > 0.02 && phase < 0.98;
    // Courbe de fondu aux extrémités
    final fade = () {
      if (phase < 0.15) return phase / 0.15;
      if (phase > 0.85) return (1.0 - phase) / 0.15;
      return 1.0;
    }()
        .clamp(0.0, 1.0);

    return Positioned(
      top: 80 + yOffset,
      left: -60 + phase * 320,
      child: Opacity(
        opacity: visible ? fade : 0,
        child: Container(
          width: 180,
          height: 64,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(color: colors.border, width: 1),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: FacteurSpacing.space2,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.textPrimary.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 70,
                      height: 5,
                      decoration: BoxDecoration(
                        color: colors.textTertiary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
