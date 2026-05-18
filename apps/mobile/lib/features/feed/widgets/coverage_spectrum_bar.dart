import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Spectrum bar pour le bandeau hi-fi `cm-panel-inline` de la Couverture
/// médiatique : 5 segments distincts L/CL/C/CR/R, taille fixe 96×9 px.
///
/// Diffère du [`BiasSpectrumBar`](../../digest/widgets/bias_spectrum_bar.dart)
/// qui merge en 3 segments (Gauche/Centre/Droite) et est utilisé dans le
/// digest. On garde les deux : 3-segs pour la lecture rapide du digest,
/// 5-segs pour le détail panel.
class CoverageSpectrumBar extends StatelessWidget {
  /// Distribution brute : `{'left': n, 'center-left': n, 'center': n,
  /// 'center-right': n, 'right': n}`. Tout segment manquant ou à 0 est
  /// rendu avec un flex floor=1 pour rester visible (sinon un segment
  /// nul disparaîtrait, faussant la lecture chromatique 5-segs).
  final Map<String, int> distribution;

  const CoverageSpectrumBar({
    super.key,
    required this.distribution,
  });

  // Ordre canonique du spectre politique, gauche → droite.
  static const _keys = ['left', 'center-left', 'center', 'center-right', 'right'];

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

    return SizedBox(
      width: 96,
      height: 9,
      child: Row(
        // stretch : sans ça, le DecoratedBox sans enfant reçoit une contrainte
        // cross-axis loose (0..9) et se peint à hauteur 0 → invisible. cf.
        // coverage_spectrum_visible_test.dart.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(_keys.length, (i) {
          final count = distribution[_keys[i]] ?? 0;
          return Expanded(
            flex: count > 0 ? count : 1,
            child: Padding(
              padding: EdgeInsets.only(right: i == _keys.length - 1 ? 0 : 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: segmentColors[i],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
