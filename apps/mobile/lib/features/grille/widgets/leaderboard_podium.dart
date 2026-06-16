import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';

/// Podium du quartier (`.gl-podium`) — ordre visuel rang 2 · rang 1 · rang 3.
/// L'avatar « Toi » est en ocre et légèrement plus grand.
class LeaderboardPodium extends StatelessWidget {
  const LeaderboardPodium({super.key, required this.quartier});

  final List<GrilleQuartierItem> quartier;

  GrilleQuartierItem? _byRank(int rank) {
    for (final q in quartier) {
      if (q.rang == rank) return q;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rang1 = _byRank(1);
    final rang2 = _byRank(2);
    final rang3 = _byRank(3);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: _col(context, rang2, 70)),
        const SizedBox(width: 12),
        Expanded(child: _col(context, rang1, 92)),
        const SizedBox(width: 12),
        Expanded(child: _col(context, rang3, 56)),
      ],
    );
  }

  Widget _col(BuildContext context, GrilleQuartierItem? p, double barHeight) {
    if (p == null) return const SizedBox.shrink();
    final c = context.facteurColors;
    final moi = p.moi;
    final label = moi ? 'Toi' : p.initiales;
    final avatarSize = moi ? 54.0 : 46.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: moi ? c.primary : GrilleConstants.steel,
            border: Border.all(color: c.surface, width: 2),
            boxShadow: moi
                ? [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: FacteurTypography.labelLarge(
              moi ? Colors.white : c.backgroundPrimary,
            ).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: FacteurTypography.bodySmall(
            moi ? c.primary : c.textSecondary,
          ).copyWith(
            fontSize: 11.5,
            fontWeight: moi ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: barHeight,
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: moi ? c.primaryMuted : c.backgroundSecondary,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(FacteurRadius.small),
            ),
          ),
          child: Text(
            p.score,
            style: GoogleFonts.courierPrime(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: moi ? c.primary : c.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          p.rang == 1 ? '1ᵉʳ' : '${p.rang}ᵉ',
          style: GoogleFonts.courierPrime(
            fontSize: 9,
            letterSpacing: 1,
            color: c.textTertiary,
          ),
        ),
      ],
    );
  }
}
