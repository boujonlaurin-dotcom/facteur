import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'tour_page_scaffold.dart';

/// Page 1 — "L'Essentiel" : soleil levant au-dessus de 3 cartes stackées.
class TourPageEssentiel extends StatelessWidget {
  const TourPageEssentiel({super.key});

  @override
  Widget build(BuildContext context) {
    return const TourPageScaffold(
      title: "L'Essentiel",
      subtitle:
          'Chaque matin, 5 articles pour te sortir de ta bulle — '
          'basés sur l\'actualité du monde, pas uniquement sur tes sources.',
      illustration: _SunAndStack(),
    );
  }
}

class _SunAndStack extends StatefulWidget {
  const _SunAndStack();

  @override
  State<_SunAndStack> createState() => _SunAndStackState();
}

class _SunAndStackState extends State<_SunAndStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final rise = Curves.easeOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soleil (monte + apparaît)
              Positioned(
                top: 20 + (40 * (1 - rise)),
                child: Opacity(
                  opacity: rise,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.primary,
                          colors.primary.withValues(alpha: 0.25),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Cartes stackées en bas
              Positioned(
                bottom: 20,
                child: SizedBox(
                  width: 180,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      _StackedCard(offset: -16, opacity: 0.45, rise: rise),
                      _StackedCard(offset: -8, opacity: 0.7, rise: rise),
                      _StackedCard(offset: 0, opacity: 1.0, rise: rise),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StackedCard extends StatelessWidget {
  const _StackedCard({
    required this.offset,
    required this.opacity,
    required this.rise,
  });

  final double offset;
  final double opacity;
  final double rise;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Opacity(
      opacity: opacity * rise,
      child: Transform.translate(
        offset: Offset(offset, offset),
        child: Container(
          width: 160,
          height: 96,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(FacteurRadius.large),
            border: Border.all(
              color: colors.border,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(FacteurSpacing.space3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 90,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 140,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 110,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
