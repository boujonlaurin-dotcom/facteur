import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';
import '../models/tile_state.dart';
import 'grille_button.dart';
import 'grille_countdown.dart';

/// État visuel de la carte d'invitation.
enum CarteCtaState { neuf, deja }

/// Mini-grille de la carte d'entrée (`.mot-grid.v-mini`) : 3 lignes de mini
/// tuiles 18 px. `teaser` → seule la 1re lettre (offerte) est affichée ;
/// sinon, on montre les essais déjà joués.
class MiniMotGrid extends StatelessWidget {
  const MiniMotGrid({
    super.key,
    required this.longueur,
    required this.premiereLettre,
    this.essais = const [],
    this.teaser = false,
  });

  final int longueur;
  final String premiereLettre;
  final List<GrilleEssai> essais;
  final bool teaser;

  static const int _rows = 3;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _rows; r++) ...[
          _row(context, r),
          if (r < _rows - 1) const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, int r) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < longueur; i++) ...[
          _cell(context, r, i),
          if (i < longueur - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _cell(BuildContext context, int r, int i) {
    final c = context.facteurColors;
    if (r < essais.length) {
      final etat = i < essais[r].etats.length ? essais[r].etats[i] : 'absent';
      final state = TileStateX.fromServer(etat);
      Color color;
      switch (state) {
        case TileState.place:
          color = c.success;
        case TileState.present:
          color = c.primary;
        default:
          color = GrilleConstants.absentGrille;
      }
      return _box(color: color, border: color);
    }
    final isHint = teaser && r == 0 && i == 0;
    if (isHint) {
      return _box(
        color: c.surfacePaper,
        border: c.primary,
        child: Text(
          premiereLettre,
          style: GoogleFonts.fraunces(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: c.primary,
          ),
        ),
      );
    }
    return _box(color: c.surfacePaper, border: c.border);
  }

  Widget _box({
    required Color color,
    required Color border,
    Widget? child,
  }) {
    return Container(
      width: GrilleConstants.miniTileSize,
      height: GrilleConstants.miniTileSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border, width: 1.5),
      ),
      child: child,
    );
  }
}

/// La carte d'invitation « La Grille du jour » (`.cta-card`).
///
/// Présentationnel pur. Le câblage provider/analytics se fait dans
/// `GrilleCtaCard` (cf. `screens/`), inséré comme sliver additif au-dessus de
/// `ClosingCardV18` (zéro modification de la carte de clôture).
class CarteCta extends StatelessWidget {
  const CarteCta({
    super.key,
    required this.state,
    required this.today,
    required this.onOpen,
  });

  final CarteCtaState state;
  final GrilleTodayResponse today;
  final VoidCallback onOpen;

  bool get _deja => state == CarteCtaState.deja;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        children: [
          _stamp(context),
          const SizedBox(height: 16),
          MiniMotGrid(
            longueur: today.longueur,
            premiereLettre: today.premiereLettre,
            essais: _deja ? today.essais : const [],
            teaser: !_deja,
          ),
          if (!_deja) ...[
            const SizedBox(height: 14),
            Text(
              'La Grille du jour',
              style: GoogleFonts.fraunces(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.5,
                color: c.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _intro(),
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 14.5,
              fontStyle: FontStyle.italic,
              height: 1.5,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          if (_deja) _dejaFoot(context) else _meta(context),
          const SizedBox(height: 16),
          GrilleButton(
            label: _deja ? 'Revoir ma grille' : 'Ouvrir la grille',
            style: _deja ? GrilleButtonStyle.ghost : GrilleButtonStyle.primary,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }

  String _intro() {
    if (_deja) {
      final n = today.nbEssais;
      return '« Trouvé en $n essai${n > 1 ? 's' : ''} aujourd’hui — joli flair. '
          'Je te poste un mot tout neuf demain matin. »';
    }
    return '« Ta tournée est faite. J’ai caché un mot dans l’actu d’aujourd’hui '
        '— six lettres, six essais. »';
  }

  Widget _stamp(BuildContext context) {
    final c = context.facteurColors;
    final color = _deja ? c.success : c.textStamp;
    return Transform.rotate(
      angle: -2 * math.pi / 180,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: _deja ? 0.07 : 0.06),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          _deja ? 'DÉJÀ JOUÉE' : 'APRÈS TA TOURNÉE',
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _meta(BuildContext context) {
    final c = context.facteurColors;
    final base = FacteurTypography.bodySmall(c.textTertiary)
        .copyWith(fontSize: 12.5);
    final bold = base.copyWith(
      color: c.textSecondary,
      fontWeight: FontWeight.w700,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text.rich(TextSpan(style: base, children: [
          TextSpan(text: '${today.longueur}', style: bold),
          const TextSpan(text: ' lettres'),
        ])),
        _dot(c),
        Text.rich(TextSpan(style: base, children: [
          TextSpan(text: '<2', style: bold),
          const TextSpan(text: ' min'),
        ])),
        _dot(c),
        Icon(PhosphorIcons.fire(PhosphorIconsStyle.fill), size: 13, color: c.primary),
        const SizedBox(width: 4),
        Text.rich(TextSpan(style: base, children: [
          TextSpan(text: '${today.streak}', style: bold),
          const TextSpan(text: ' j'),
        ])),
      ],
    );
  }

  Widget _dejaFoot(BuildContext context) {
    final c = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: GrilleCountdown(
            initialSeconds: today.prochainMotDansSec,
            fontSize: 11,
            iconSize: 12,
          ),
        ),
        _dot(c),
        Icon(PhosphorIcons.fire(PhosphorIconsStyle.fill), size: 13, color: c.primary),
        const SizedBox(width: 4),
        Text(
          '${today.streak} jours',
          style: FacteurTypography.bodySmall(c.textSecondary)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _dot(FacteurColors c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('·', style: TextStyle(color: c.textTertiary)),
      );
}
