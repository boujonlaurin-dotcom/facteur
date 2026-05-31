import 'package:flutter/material.dart';

import '../grille_constants.dart';
import '../models/grille_models.dart';
import '../models/tile_state.dart';
import 'mot_grid_row.dart';

/// Variante d'affichage de la grille.
enum MotGridVariant { jeu, resultat }

/// La grille de lettres complète (`.mot-grid`).
///
/// Compose des lignes révélées (essais joués), éventuellement la ligne en cours
/// de saisie (variante [MotGridVariant.jeu]) et des lignes vides jusqu'au
/// nombre d'essais max. Widget **pur** (aucune lecture de provider) → testable
/// et golden-friendly.
class MotGrid extends StatelessWidget {
  const MotGrid({
    super.key,
    required this.longueur,
    required this.essaisMax,
    required this.premiereLettre,
    required this.essais,
    this.draft = '',
    this.variant = MotGridVariant.jeu,
    this.revealRow = -1,
    this.shakeNonce = 0,
  });

  final int longueur;
  final int essaisMax;
  final String premiereLettre;
  final List<GrilleEssai> essais;

  /// Ligne en cours de saisie (variante jeu uniquement).
  final String draft;
  final MotGridVariant variant;

  /// Index de la ligne à révéler par flip (`-1` = aucune).
  final int revealRow;

  /// Incrément de shake pour la ligne courante (essai refusé).
  final int shakeNonce;

  bool get _isJeu => variant == MotGridVariant.jeu;

  double get _tileSize => _isJeu
      ? GrilleConstants.tileSize
      : GrilleConstants.tileSizeResult;
  double get _gap =>
      _isJeu ? GrilleConstants.tileGap : GrilleConstants.tileGapResult;

  /// Nombre total de lignes : tous les essais en résultat, sinon `essaisMax`.
  int get _totalRows => _isJeu ? essaisMax : essais.length;

  List<MotCell> _revealedCells(GrilleEssai essai) {
    return List.generate(longueur, (i) {
      final letter = i < essai.mot.length ? essai.mot[i] : '';
      final etat = i < essai.etats.length ? essai.etats[i] : 'absent';
      return MotCell(TileStateX.fromServer(etat), letter);
    });
  }

  List<MotCell> _currentCells() {
    return List.generate(longueur, (i) {
      if (i < draft.length) {
        return MotCell(TileState.filled, draft[i]);
      }
      if (i == 0 && draft.isEmpty) {
        return MotCell(TileState.hint, premiereLettre);
      }
      return const MotCell(TileState.empty, '');
    });
  }

  List<MotCell> _emptyCells() =>
      List.generate(longueur, (_) => const MotCell(TileState.empty, ''));

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    final currentRowIndex = essais.length;

    for (var r = 0; r < _totalRows; r++) {
      List<MotCell> cells;
      var reveal = false;
      var shake = 0;

      if (r < essais.length) {
        cells = _revealedCells(essais[r]);
        reveal = r == revealRow;
      } else if (_isJeu && r == currentRowIndex) {
        cells = _currentCells();
        shake = shakeNonce;
      } else {
        cells = _emptyCells();
      }

      rows.add(
        MotGridRow(
          key: ValueKey('grille-row-$r'),
          cells: cells,
          size: _tileSize,
          gap: _gap,
          reveal: reveal,
          shakeNonce: shake,
        ),
      );
      if (r < _totalRows - 1) {
        rows.add(SizedBox(height: _gap));
      }
    }

    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}
