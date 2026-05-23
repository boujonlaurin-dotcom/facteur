import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import 'sticky_backdrop.dart';

/// Macro-bloc the user is currently traversing.
///
/// Drives [StickyThreeStateBar] : each value swaps icon, accent and label.
/// Story 9.2, composant 2.
enum StickyMacroBloc { essentiel, parTheme, explorer }

/// Sticky bar v3 — 3-state contextual reminder of the macro zone.
///
/// Layout (~64 px) :
/// - Row 1 : 40×40 rounded square with `--k-tint` background + Phosphor icon,
///   Fraunces 15px/w600 title, mono "~N min" hint pinned right.
/// - Row 2 : N progress plots (lu = filled accent + check / current = ring /
///   upcoming = grey disc) + "read/total" ratio.
///
/// Transition between blocs : container stays in place, only the inner
/// content crossfades over 200 ms via [AnimatedSwitcher].
class StickyThreeStateBar extends StatelessWidget {
  final StickyMacroBloc bloc;
  final int read;
  final int total;
  final int remainingMin;
  final VoidCallback? onTap;

  const StickyThreeStateBar({
    super.key,
    required this.bloc,
    required this.read,
    required this.total,
    required this.remainingMin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StickyBackdrop(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _StickyContent(
              key: ValueKey(bloc),
              bloc: bloc,
              read: read,
              total: total,
              remainingMin: remainingMin,
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyContent extends StatelessWidget {
  final StickyMacroBloc bloc;
  final int read;
  final int total;
  final int remainingMin;

  const _StickyContent({
    super.key,
    required this.bloc,
    required this.read,
    required this.total,
    required this.remainingMin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final accent = _accentFor(colors, bloc);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space2,
        FacteurSpacing.space4,
        FacteurSpacing.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconBadge(accent: accent, bloc: bloc),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _titleFor(bloc),
                  style: GoogleFonts.fraunces(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                _ProgressPlots(
                  accent: accent,
                  read: read.clamp(0, total),
                  total: total,
                ),
              ],
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Text(
            '~$remainingMin min',
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  static String _titleFor(StickyMacroBloc bloc) {
    switch (bloc) {
      case StickyMacroBloc.essentiel:
        return 'L’Essentiel du jour';
      case StickyMacroBloc.parTheme:
        return 'L’Essentiel, par thème';
      case StickyMacroBloc.explorer:
        return 'Explorer';
    }
  }

  static Color _accentFor(FacteurColors colors, StickyMacroBloc bloc) {
    switch (bloc) {
      case StickyMacroBloc.essentiel:
        return colors.sectionEssentiel;
      case StickyMacroBloc.parTheme:
        return colors.sectionBonnes;
      case StickyMacroBloc.explorer:
        return colors.sectionVeille1;
    }
  }
}

class _IconBadge extends StatelessWidget {
  final Color accent;
  final StickyMacroBloc bloc;

  const _IconBadge({required this.accent, required this.bloc});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
      ),
      child: Icon(_iconFor(bloc), color: accent, size: 20),
    );
  }

  static IconData _iconFor(StickyMacroBloc bloc) {
    switch (bloc) {
      case StickyMacroBloc.essentiel:
        return PhosphorIcons.envelopeSimple();
      case StickyMacroBloc.parTheme:
        return PhosphorIcons.stack();
      case StickyMacroBloc.explorer:
        return PhosphorIcons.compass();
    }
  }
}

class _ProgressPlots extends StatelessWidget {
  final Color accent;
  final int read;
  final int total;

  const _ProgressPlots({
    required this.accent,
    required this.read,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (total <= 0) {
      return const SizedBox(height: 12);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _plotFor(i, accent, colors),
        ],
        const SizedBox(width: 8),
        Text(
          '$read/$total',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _plotFor(int i, Color accent, FacteurColors colors) {
    if (i < read) {
      // Read
      return Container(
        width: 12,
        height: 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 9, color: Colors.white),
      );
    }
    if (i == read) {
      // Current
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 2),
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: colors.textTertiary.withValues(alpha: 0.25),
        shape: BoxShape.circle,
      ),
    );
  }
}
