import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/theme.dart';

/// Rayon des coins **internes** (entre segments) — adouci à 4 px pour une barre
/// plus élégante. Les coins externes (1ʳᵉ/dernière stance visible) sont plus
/// marqués ([CoverageSpectrumBar._kRadiusOuter]). Réutilisé tel quel par le
/// shimmer pour la cohérence.
const _radius = BorderRadius.all(Radius.circular(4));

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

  /// Optionnel : tap sur un segment → renvoie la clé de stance (`left`…`right`).
  /// Quand fourni, la barre devient **interactive** : la cible tactile est
  /// élargie (~24 px de haut, padding transparent) sans grossir le trait
  /// visuel, et un `GestureDetector` mappe la position du tap → segment.
  final void Function(String stanceKey)? onSegmentTap;

  /// Quand `true`, ancre la barre par deux libellés « Gauche » / « Droite »
  /// posés sous le trait (permanents — pas de libellé central éphémère). Utilisé
  /// en pied de bande de la Couverture médiatique ; défaut `false` ⇒ aucun
  /// autre call-site impacté.
  final bool showAnchorLabels;

  const CoverageSpectrumBar({
    super.key,
    required this.distribution,
    this.onSegmentTap,
    this.showAnchorLabels = false,
  });

  // Ordre canonique du spectre politique, gauche → droite.
  static const _keys = [
    'left',
    'center-left',
    'center',
    'center-right',
    'right',
  ];

  // Lissage de l'évolution de la barre quand `distribution` change (refetch
  // incrémental ~2.2 s) : chaque segment grandit/rétrécit au lieu de sauter.
  static const _kSegmentAnim = Duration(milliseconds: 350);
  static const _kGap = 3.0;
  // Coins externes (bord gauche de la 1ʳᵉ stance visible, bord droit de la
  // dernière) : plus marqués que les coins internes (`_radius` = 4) pour que la
  // barre se lise comme une pilule arrondie aux extrémités.
  static const _kRadiusOuter = 5.0;
  // Trait visuel (épaissi de 8 → 11 pour la pleine largeur en pied de bande).
  static const _kBarHeight = 11.0;
  // Cible tactile confortable quand interactive : padding transparent autour du
  // trait, sans l'épaissir.
  static const _kTapTargetHeight = 24.0;

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
    final counts =
        List.generate(_keys.length, (i) => distribution[_keys[i]] ?? 0);
    final total = counts.fold<int>(0, (sum, c) => sum + c);
    final interactive = onSegmentTap != null;
    // 1ʳᵉ / dernière stance visible → coins externes plus marqués (pilule).
    final firstVisible = counts.indexWhere((c) => c > 0);
    final lastVisible = counts.lastIndexWhere((c) => c > 0);

    final barArea = SizedBox(
      height: interactive ? _kTapTargetHeight : _kBarHeight,
      // LayoutBuilder : on calcule des largeurs explicites pour pouvoir les
      // animer (les `flex` d'`Expanded` ne s'animent pas → saut visible).
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Les 5 segments sont toujours montés (largeur 0 si count 0) pour
          // qu'un nouveau segment *grandisse* de 0 au lieu d'apparaître sec.
          final visibleCount = counts.where((c) => c > 0).length;
          final totalGap = visibleCount > 1 ? (visibleCount - 1) * _kGap : 0.0;
          final barWidth =
              (constraints.maxWidth - totalGap).clamp(0.0, constraints.maxWidth);

          final bar = SizedBox(
            height: _kBarHeight,
            child: Row(
              // stretch : sans ça, un AnimatedContainer sans enfant reçoit une
              // contrainte cross-axis loose → hauteur 0, invisible. cf.
              // coverage_spectrum_visible_test.dart.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(_keys.length, (i) {
                final count = counts[i];
                final width = total > 0 ? barWidth * count / total : 0.0;
                // Gap à droite seulement s'il reste un segment visible après.
                final hasLaterVisible = counts.skip(i + 1).any((c) => c > 0);
                final rightGap = count > 0 && hasLaterVisible ? _kGap : 0.0;
                // Coins externes (bord gauche de la 1ʳᵉ visible, bord droit de
                // la dernière) plus marqués ; coins internes au rayon de base.
                final borderRadius = BorderRadius.horizontal(
                  left: Radius.circular(
                    i == firstVisible ? _kRadiusOuter : 4,
                  ),
                  right: Radius.circular(
                    i == lastVisible ? _kRadiusOuter : 4,
                  ),
                );
                return AnimatedContainer(
                  duration: _kSegmentAnim,
                  curve: Curves.easeOutCubic,
                  width: width,
                  margin: EdgeInsets.only(right: rightGap),
                  decoration: BoxDecoration(
                    color: segmentColors[i],
                    borderRadius: borderRadius,
                  ),
                );
              }),
            ),
          );

          if (!interactive) return bar;

          // Toute la hauteur (24) capte le tap ; le trait (11) reste centré.
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final key =
                  _stanceAt(details.localPosition.dx, counts, barWidth, total);
              if (key != null) onSegmentTap!(key);
            },
            child: Center(child: bar),
          );
        },
      ),
    );

    if (!showAnchorLabels) return barArea;

    // Ancrage permanent « Gauche » / « Droite » sous le trait.
    final anchorStyle = GoogleFonts.courierPrime(
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
      color: colors.textTertiary,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        barArea,
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Gauche', style: anchorStyle),
            Text('Droite', style: anchorStyle),
          ],
        ),
      ],
    );
  }

  /// Trouve la clé de stance dont les bornes x contiennent [dx]. Les segments
  /// visibles remplissent toute la largeur (gaps inclus dans le segment qui les
  /// précède) → un tap n'importe où atteint un segment non vide. Renvoie le
  /// dernier segment visible si [dx] déborde à droite, `null` si total nul.
  String? _stanceAt(double dx, List<int> counts, double barWidth, int total) {
    if (total <= 0) return null;
    var cursor = 0.0;
    String? lastVisible;
    for (var i = 0; i < _keys.length; i++) {
      final count = counts[i];
      if (count == 0) continue;
      final width = barWidth * count / total;
      lastVisible = _keys[i];
      final hasLaterVisible = counts.skip(i + 1).any((c) => c > 0);
      final right = cursor + width + (hasLaterVisible ? _kGap : 0.0);
      if (dx < right) return _keys[i];
      cursor = right;
    }
    return lastVisible;
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
      duration: const Duration(milliseconds: 1500),
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
    final baseColor = colors.textTertiary.withValues(alpha: 0.12);
    final highlightColor = Colors.white.withValues(alpha: 0.32);

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
