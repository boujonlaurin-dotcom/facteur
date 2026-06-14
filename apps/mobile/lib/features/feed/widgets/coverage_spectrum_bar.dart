import 'package:flutter/material.dart';
import '../../../config/theme.dart';

const _radius = BorderRadius.all(Radius.circular(2));

/// Spectrum bar pour le bandeau hi-fi `cm-panel-inline` de la Couverture
/// médiatique : 5 segments distincts L/CL/C/CR/R, hauteur fixe 8 px,
/// **largeur déléguée au parent** (proto v4 : la barre s'étire dans un
/// `Flexible(ConstrainedBox(min70/max150))` côté header).
///
/// Diffère du [`BiasSpectrumBar`](../../digest/widgets/bias_spectrum_bar.dart)
/// qui merge en 3 segments (Gauche/Centre/Droite) et est utilisé dans le
/// digest. On garde les deux : 3-segs pour la lecture rapide du digest,
/// 5-segs pour le détail panel.
class CoverageSpectrumBar extends StatelessWidget {
  /// Distribution brute : `{'left': n, 'center-left': n, 'center': n,
  /// 'center-right': n, 'right': n}`. Les segments absents ou à 0 ne sont
  /// pas rendus afin que les largeurs reflètent strictement les compteurs.
  final Map<String, int> distribution;

  const CoverageSpectrumBar({super.key, required this.distribution});

  // Ordre canonique du spectre politique, gauche → droite.
  static const _keys = [
    'left',
    'center-left',
    'center',
    'center-right',
    'right',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final segmentColors = <Color>[
      colors.biasLeft,
      colors.biasCenterLeft,
      colors.biasCenter,
      colors.biasCenterRight,
      colors.biasRight,
    ];
    final visibleSegments = List.generate(
      _keys.length,
      (index) =>
          (count: distribution[_keys[index]] ?? 0, color: segmentColors[index]),
    ).where((segment) => segment.count > 0).toList();

    return SizedBox(
      height: 8,
      child: Row(
        // stretch : sans ça, le DecoratedBox sans enfant reçoit une contrainte
        // cross-axis loose (0..8) et se peint à hauteur 0 → invisible. cf.
        // coverage_spectrum_visible_test.dart.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(visibleSegments.length, (i) {
          final segment = visibleSegments[i];
          return Expanded(
            flex: segment.count,
            child: Padding(
              padding: EdgeInsets.only(
                right: i == visibleSegments.length - 1 ? 0 : 2,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: segment.color,
                  borderRadius: _radius,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class CoverageSpectrumBarShimmer extends StatefulWidget {
  const CoverageSpectrumBarShimmer({super.key});

  @override
  State<CoverageSpectrumBarShimmer> createState() =>
      _CoverageSpectrumBarShimmerState();
}

class _CoverageSpectrumBarShimmerState extends State<CoverageSpectrumBarShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
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
    final baseColor = colors.textTertiary.withValues(alpha: 0.16);
    final highlightColor = Colors.white.withValues(alpha: 0.72);

    return SizedBox(
      height: 8,
      child: ClipRRect(
        borderRadius: _radius,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final offset = _controller.value * 2.8;
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment(-1.4 + offset, 0),
                  end: Alignment(-0.2 + offset, 0),
                  colors: [
                    Colors.transparent,
                    highlightColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ).createShader(rect);
              },
              child: child,
            );
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: _radius,
            ),
          ),
        ),
      ),
    );
  }
}
