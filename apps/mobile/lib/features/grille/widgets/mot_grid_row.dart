import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../grille_constants.dart';
import '../models/tile_state.dart';
import 'mot_tile.dart';

/// Une cellule de la ligne : état + lettre.
class MotCell {
  const MotCell(this.state, this.letter);
  final TileState state;
  final String letter;
}

/// Une ligne de la grille, porteuse des deux animations :
///
/// - **flip** de révélation (`@keyframes mt-flip`) : `rotateX 0 → -88° → 0`,
///   420 ms `ease-out-cubic`, décalé de 95 ms par colonne. Joué une seule fois
///   lorsque [reveal] passe à vrai.
/// - **shake** d'un mot invalide (~250 ms) : translation horizontale amortie,
///   rejouée à chaque incrément de [shakeNonce].
///
/// `MediaQuery.disableAnimations` (reduced-motion) → révélation directe, pas de
/// shake.
class MotGridRow extends StatefulWidget {
  const MotGridRow({
    super.key,
    required this.cells,
    this.size = GrilleConstants.tileSize,
    this.gap = GrilleConstants.tileGap,
    this.reveal = false,
    this.shakeNonce = 0,
  });

  final List<MotCell> cells;
  final double size;
  final double gap;

  /// Joue le flip de révélation une fois (ligne fraîchement validée).
  final bool reveal;

  /// Incrémenté pour déclencher un shake (essai refusé).
  final int shakeNonce;

  @override
  State<MotGridRow> createState() => _MotGridRowState();
}

class _MotGridRowState extends State<MotGridRow>
    with TickerProviderStateMixin {
  late final AnimationController _flip;
  late final AnimationController _shake;

  static const double _maxTiltDeg = 88;
  static const double _peakAt = 0.45; // 45 % de la durée

  @override
  void initState() {
    super.initState();
    final n = widget.cells.length;
    _flip = AnimationController(
      vsync: this,
      duration: GrilleConstants.flipDuration +
          GrilleConstants.flipStagger * (n > 0 ? n - 1 : 0),
    );
    _shake = AnimationController(
      vsync: this,
      duration: GrilleConstants.shakeDuration,
    );
    if (widget.reveal) {
      // Joué après le 1er frame pour respecter disableAnimations du contexte.
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybePlayFlip());
    }
  }

  @override
  void didUpdateWidget(MotGridRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reveal && !oldWidget.reveal) {
      _maybePlayFlip();
    }
    if (widget.shakeNonce != oldWidget.shakeNonce) {
      _maybeShake();
    }
  }

  bool get _reducedMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations ?? false;
  }

  void _maybePlayFlip() {
    if (!mounted) return;
    if (_reducedMotion) {
      _flip.value = 1; // révélation directe
      return;
    }
    _flip.forward(from: 0);
  }

  void _maybeShake() {
    if (!mounted || _reducedMotion) return;
    _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _flip.dispose();
    _shake.dispose();
    super.dispose();
  }

  /// Angle (radians) d'une tuile à l'instant courant du contrôleur de flip.
  double _tiltFor(int index) {
    final total = _flip.duration!.inMilliseconds;
    final elapsed = _flip.value * total;
    final start = index * GrilleConstants.flipStagger.inMilliseconds;
    final local =
        ((elapsed - start) / GrilleConstants.flipDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    double deg;
    if (local <= _peakAt) {
      deg = -_maxTiltDeg * (local / _peakAt);
    } else {
      deg = -_maxTiltDeg * (1 - (local - _peakAt) / (1 - _peakAt));
    }
    return deg * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (var i = 0; i < widget.cells.length; i++) {
      final cell = widget.cells[i];
      final tile = MotTile(state: cell.state, letter: cell.letter, size: widget.size);
      tiles.add(
        AnimatedBuilder(
          animation: _flip,
          builder: (context, child) {
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0015) // perspective
              ..rotateX(_tiltFor(i));
            return Transform(
              alignment: Alignment.center,
              transform: matrix,
              child: child,
            );
          },
          child: tile,
        ),
      );
      if (i < widget.cells.length - 1) {
        tiles.add(SizedBox(width: widget.gap));
      }
    }

    final row = Row(mainAxisSize: MainAxisSize.min, children: tiles);

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = _shake.value;
        // Oscillation amortie : 4 allers-retours qui s'éteignent.
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 4) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: row,
    );
  }
}
