import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/tile_state.dart';

/// Disposition AZERTY (`fKkZuc/grille-mot.jsx`).
///
/// 3e rangée : « Effacer » (⌫) à gauche, « Entrée » (↵) à droite — inversion
/// par rapport au design d'origine pour une ergonomie pouce-droit (valider).
const List<List<String>> _azertyRows = [
  ['A', 'Z', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
  ['Q', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M'],
  ['⌫', 'W', 'X', 'C', 'V', 'B', 'N', '↵'],
];

/// Clavier AZERTY coloré façon Wordle (`.mot-clavier`).
///
/// Les touches se teintent selon [states] (pli des essais joués) :
/// `place` (vert), `present` (ocre), `absent` (gris clair). `↵` valide,
/// `⌫` efface ; ces deux touches sont larges. Quand [highlightEnter] est vrai
/// (le mot est complet, prêt à valider), la touche `↵` se remplit en primaire
/// et pulse doucement pour inviter à appuyer — sauf en reduce-motion.
class AzertyKeyboard extends StatefulWidget {
  const AzertyKeyboard({
    super.key,
    required this.states,
    required this.onKey,
    required this.onEnter,
    required this.onBackspace,
    this.enabled = true,
    this.highlightEnter = false,
  });

  final Map<String, TileState> states;
  final ValueChanged<String> onKey;
  final VoidCallback onEnter;
  final VoidCallback onBackspace;
  final bool enabled;

  /// Mot complet → met en avant + anime la touche « Entrée ».
  final bool highlightEnter;

  @override
  State<AzertyKeyboard> createState() => _AzertyKeyboardState();
}

class _AzertyKeyboardState extends State<AzertyKeyboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
      lowerBound: 1.0,
      upperBound: 1.06,
    );
    if (widget.highlightEnter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPulse());
    }
  }

  @override
  void didUpdateWidget(AzertyKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightEnter != oldWidget.highlightEnter) {
      _syncPulse();
    }
  }

  bool get _reducedMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _syncPulse() {
    if (!mounted) return;
    if (widget.highlightEnter && !_reducedMotion) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _azertyRows.length; r++) ...[
          Row(
            children: [
              for (var k = 0; k < _azertyRows[r].length; k++) ...[
                _buildKey(context, _azertyRows[r][k]),
                if (k < _azertyRows[r].length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
          if (r < _azertyRows.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _buildKey(BuildContext context, String key) {
    final c = context.facteurColors;
    final isEnter = key == '↵';
    final isBackspace = key == '⌫';
    final isWide = isEnter || isBackspace;
    final state = widget.states[key];
    final highlight = isEnter && widget.highlightEnter;

    Color background;
    Color foreground;
    List<BoxShadow>? shadow = const [
      BoxShadow(color: Color(0x14000000), blurRadius: 2, offset: Offset(0, 1)),
    ];

    switch (state) {
      case TileState.place:
        background = c.success;
        foreground = Colors.white;
      case TileState.present:
        background = GrilleConstants.presentTile;
        foreground = Colors.white;
      case TileState.absent:
        background = GrilleConstants.absentClavier;
        foreground = Colors.white;
        shadow = null;
      default:
        background = c.surface;
        foreground = c.textPrimary;
    }

    // La touche « Entrée » en avant quand le mot est complet : fond plein.
    if (highlight) {
      background = c.primary;
      foreground = Colors.white;
    }

    final label = isEnter ? 'Entrée' : key;

    Widget keyBox = Container(
      height: GrilleConstants.keyHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(GrilleConstants.keyRadius),
        boxShadow: shadow,
      ),
      child: Text(
        label,
        style: FacteurTypography.labelLarge(foreground).copyWith(
          fontSize: isWide ? 11 : 15,
          fontWeight: FontWeight.w700,
          letterSpacing: isWide ? 0.5 : 0,
        ),
      ),
    );

    if (highlight) {
      keyBox = ScaleTransition(scale: _pulse, child: keyBox);
    }

    return Expanded(
      flex: isWide ? 17 : 10,
      child: Semantics(
        button: true,
        label: isEnter
            ? 'Valider'
            : isBackspace
                ? 'Effacer'
                : key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled
              ? () {
                  if (isEnter) {
                    widget.onEnter();
                  } else if (isBackspace) {
                    widget.onBackspace();
                  } else {
                    widget.onKey(key);
                  }
                }
              : null,
          child: keyBox,
        ),
      ),
    );
  }
}
