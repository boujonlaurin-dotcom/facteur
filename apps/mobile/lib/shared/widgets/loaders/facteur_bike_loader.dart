import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Le facteur en tournée — l'attente illustrée du cold boot de l'Essentiel.
///
/// Pourquoi un widget animé plutôt qu'un Lottie : l'asset disponible
/// (`assets/notifications/facteur_bike.png`, déjà utilisé par la carte de
/// clôture et la modale de notifications) est une **image plate unique**, pas
/// une composition à calques — les roues ne peuvent pas tourner
/// indépendamment. Le mouvement est donc porté par la *scène* : le facteur
/// tangue doucement et la route défile sous lui. Lu à taille réelle, ça se
/// lit comme « il pédale, il arrive », sans le coût d'un Lottie qui repeint
/// chaque frame (cf. la note web de [FacteurLoader]).
///
/// Ton volontairement calme (« moment de fermeture ») : amplitudes faibles,
/// cycle lent de 2,4 s. Respecte `MediaQuery.disableAnimations` — le rendu
/// tombe alors sur l'illustration figée, sans contrôleur.
class FacteurBikeLoader extends StatefulWidget {
  /// Largeur de l'illustration. La hauteur suit le ratio de l'asset (1:1).
  final double size;

  const FacteurBikeLoader({super.key, this.size = 96});

  static const _asset = 'assets/notifications/facteur_bike.png';

  @override
  State<FacteurBikeLoader> createState() => _FacteurBikeLoaderState();
}

class _FacteurBikeLoaderState extends State<FacteurBikeLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final image = Image.asset(
      FacteurBikeLoader._asset,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      // Décoratif : la sémantique porteuse est le texte d'attente à côté.
      excludeFromSemantics: true,
    );

    if (MediaQuery.disableAnimationsOf(context)) {
      return SizedBox(width: widget.size, height: widget.size, child: image);
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        // L'image est construite une fois et passée en `child` : elle n'est pas
        // reconstruite à chaque frame, seul le transform l'est.
        child: image,
        builder: (context, child) {
          final t = _controller.value;
          final phase = t * 2 * math.pi;
          // Tangage : ±2,5 px verticaux, et un roulis deux fois plus lent pour
          // que les deux ne se resynchronisent pas en un balancement mécanique.
          final bob = math.sin(phase) * 2.5;
          final tilt = math.sin(phase / 2) * 0.018;

          return Stack(
            alignment: Alignment.center,
            children: [
              // La route : trois tirets qui défilent vers l'arrière. C'est eux
              // qui portent le sens « il avance » — le facteur, lui, ne fait
              // que tanguer sur place.
              Positioned(
                bottom: widget.size * 0.06,
                left: 0,
                right: 0,
                child: _RoadDashes(progress: t, color: colors.textTertiary),
              ),
              Transform.translate(
                offset: Offset(0, bob),
                child: Transform.rotate(angle: tilt, child: child),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Tirets de route défilants. Chaque tiret parcourt la largeur en boucle, décalé
/// d'un tiers de cycle, et s'estompe aux deux extrémités pour éviter le « pop »
/// d'apparition/disparition.
class _RoadDashes extends StatelessWidget {
  final double progress;
  final Color color;

  const _RoadDashes({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < 3; i++)
                _dash(width: width, phase: (progress + i / 3) % 1.0),
            ],
          );
        },
      ),
    );
  }

  Widget _dash({required double width, required double phase}) {
    const dashWidth = 10.0;
    // Défile de droite à gauche : le facteur regarde vers la droite.
    final x = (1 - phase) * (width - dashWidth);
    // Fondu symétrique : plein au centre, transparent aux bords.
    final fade = math.sin(phase * math.pi);

    return Positioned(
      left: x,
      child: Container(
        width: dashWidth,
        height: 2,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.28 * fade),
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
        ),
      ),
    );
  }
}
