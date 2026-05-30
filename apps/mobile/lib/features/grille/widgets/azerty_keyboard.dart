import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/tile_state.dart';

/// Disposition AZERTY (`fKkZuc/grille-mot.jsx`).
const List<List<String>> _azertyRows = [
  ['A', 'Z', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
  ['Q', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M'],
  ['↵', 'W', 'X', 'C', 'V', 'B', 'N', '⌫'],
];

/// Clavier AZERTY coloré façon Wordle (`.mot-clavier`).
///
/// Les touches se teintent selon [states] (pli des essais joués) :
/// `place` (vert), `present` (ocre), `absent` (gris clair). `↵` valide,
/// `⌫` efface ; ces deux touches sont larges.
class AzertyKeyboard extends StatelessWidget {
  const AzertyKeyboard({
    super.key,
    required this.states,
    required this.onKey,
    required this.onEnter,
    required this.onBackspace,
    this.enabled = true,
  });

  final Map<String, TileState> states;
  final ValueChanged<String> onKey;
  final VoidCallback onEnter;
  final VoidCallback onBackspace;
  final bool enabled;

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
    final state = states[key];

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
        background = c.primary;
        foreground = Colors.white;
      case TileState.absent:
        background = GrilleConstants.absentClavier;
        foreground = Colors.white;
        shadow = null;
      default:
        background = c.surface;
        foreground = c.textPrimary;
    }

    final label = isEnter ? 'Entrée' : key;

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
          onTap: enabled
              ? () {
                  if (isEnter) {
                    onEnter();
                  } else if (isBackspace) {
                    onBackspace();
                  } else {
                    onKey(key);
                  }
                }
              : null,
          child: Container(
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
          ),
        ),
      ),
    );
  }
}
