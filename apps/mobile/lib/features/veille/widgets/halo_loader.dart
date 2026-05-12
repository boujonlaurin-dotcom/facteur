import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Halo : 3 anneaux pulsés (delays 0, 0.6s, 1.2s) + icône binoculars
/// qui respire (scale 1↔1.05).
class HaloLoader extends StatefulWidget {
  const HaloLoader({super.key});
  @override
  State<HaloLoader> createState() => _HaloLoaderState();
}

class _HaloLoaderState extends State<HaloLoader>
    with TickerProviderStateMixin {
  late final List<AnimationController> _ringCtrls;
  late final AnimationController _iconCtrl;

  @override
  void initState() {
    super.initState();
    _ringCtrls = List.generate(
      3,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      ),
    );
    // Démarre avec offsets pour l'effet "vague".
    Future<void>.delayed(Duration.zero, () {
      if (!mounted) return;
      _ringCtrls[0].repeat();
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _ringCtrls[1].repeat();
      });
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) _ringCtrls[2].repeat();
      });
    });
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    for (final c in _ringCtrls) {
      c.dispose();
    }
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final ctrl in _ringCtrls) _Ring(ctrl: ctrl),
          ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.05).animate(
              CurvedAnimation(parent: _iconCtrl, curve: Curves.easeInOut),
            ),
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: FacteurColors.veilleTint,
                shape: BoxShape.circle,
                border: Border.all(color: FacteurColors.veilleLine, width: 1.5),
              ),
              child: Icon(
                PhosphorIcons.binoculars(),
                size: 36,
                color: FacteurColors.veille,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final AnimationController ctrl;
  const _Ring({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final t = ctrl.value;
        final scale = 0.55 + (1.25 - 0.55) * t;
        // Opacité : 0 → 0.8 (à 20%) → 0
        final opacity = t < 0.2 ? (t / 0.2) * 0.8 : 0.8 * (1 - (t - 0.2) / 0.8);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: FacteurColors.veilleLine,
                  width: 1.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Spinner mini (12px) — utilisé dans la checklist (state=running).
class MiniSpinner extends StatefulWidget {
  const MiniSpinner({super.key});
  @override
  State<MiniSpinner> createState() => _MiniSpinnerState();
}

class _MiniSpinnerState extends State<MiniSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: FacteurColors.veilleLine, width: 1.5),
          gradient: const SweepGradient(
            colors: [FacteurColors.veille, Colors.transparent],
            stops: [0.25, 0.75],
          ),
        ),
      ),
    );
  }
}
