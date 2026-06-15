import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';
import 'dashed_border.dart';
import 'mot_grid.dart';

/// Vue de résultat (`GMotResultat`, sans `CartePlusLoin`) : cachet de verdict,
/// titre, sous-titre, grille révélée et carte « pourquoi » (voix Facteur).
class GrilleResultView extends StatelessWidget {
  const GrilleResultView({
    super.key,
    required this.today,
    this.animateReveal = false,
  });

  final GrilleTodayResponse today;

  /// Joue le flip de la dernière ligne (arrivée fraîche depuis le jeu).
  final bool animateReveal;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final solved = today.isSolved;
    final revealed = today.isRevealed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Cachet(solved: solved, revealed: revealed),
        const SizedBox(height: 16),
        Text(
          revealed
              ? 'Tu as donné ta langue au chat.'
              : solved
                  ? 'Mot livré.'
                  : 'Mot non distribué.',
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        _subtitle(context, solved, revealed),
        const SizedBox(height: 20),
        MotGrid(
          longueur: today.longueur,
          essaisMax: today.essaisMax,
          premiereLettre: today.premiereLettre,
          essais: today.essais,
          variant: MotGridVariant.resultat,
          revealRow:
              animateReveal && solved ? today.essais.length - 1 : -1,
          bounceRevealRow: animateReveal && solved,
        ),
        const SizedBox(height: 18),
        if (today.pourquoi != null) _pourquoi(context),
      ],
    );
  }

  Widget _subtitle(BuildContext context, bool solved, bool revealed) {
    final c = context.facteurColors;
    final base = FacteurTypography.bodyMedium(c.textSecondary)
        .copyWith(fontSize: 14);
    final bold = base.copyWith(
      color: c.textPrimary,
      fontWeight: FontWeight.w700,
    );
    if (revealed) {
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Pas de défaite — le mot du jour était '),
            TextSpan(text: today.mot ?? '', style: bold),
            const TextSpan(text: '. Cette grille ne compte pas au classement.'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    if (solved) {
      final n = today.nbEssais;
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Trouvé en '),
            TextSpan(text: '$n', style: bold),
            TextSpan(text: ' essai${n > 1 ? 's' : ''} sur ${today.essaisMax}.'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Le mot du jour était '),
          TextSpan(text: today.mot ?? '', style: bold),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _pourquoi(BuildContext context) {
    final c = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: GrilleConstants.avatarFallback,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  today.mot ?? '',
                  style: GoogleFonts.fraunces(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 4),
                // Priorité : sélection hybride (« où le mot se cachait dans
                // l'actu réelle »), puis l'ancien snapshot featured (titre +
                // extrait), puis la phrase « pourquoi » (fallback historique).
                if (today.hybridSnippet != null)
                  ..._hybrid(context)
                else if (today.featuredExcerpt != null) ...[
                  Text(
                    today.featuredTitle ?? '',
                    style: GoogleFonts.fraunces(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    today.featuredExcerpt!,
                    style: GoogleFonts.fraunces(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                      color: c.textSecondary,
                    ),
                  ),
                  if (today.featuredSource != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      today.featuredSource!,
                      style: FacteurTypography.bodySmall(c.textTertiary)
                          .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ] else
                  Text(
                    '« ${today.pourquoi} »',
                    style: GoogleFonts.fraunces(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      height: 1.5,
                      color: c.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bloc « où le mot se cachait » : badge titre/description, snippet avec la
  /// surface matchée surlignée, source, et lien « Lire l'article ».
  List<Widget> _hybrid(BuildContext context) {
    final c = context.facteurColors;
    final isTitle = today.hybridField == 'title';
    final badge = isTitle ? 'caché dans le titre' : 'caché dans la description';
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(FacteurRadius.small),
        ),
        child: Text(
          badge,
          style: FacteurTypography.bodySmall(c.primary)
              .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 8),
      Text.rich(
        _highlight(
          context,
          today.hybridSnippet!,
          today.hybridMatch,
        ),
        style: GoogleFonts.fraunces(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.45,
          color: c.textPrimary,
        ),
      ),
      if (today.featuredSource != null) ...[
        const SizedBox(height: 8),
        Text(
          today.featuredSource!,
          style: FacteurTypography.bodySmall(c.textTertiary)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
      if (today.featuredUrl != null) ...[
        const SizedBox(height: 10),
        InkWell(
          onTap: () => _openArticle(today.featuredUrl!),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lire l\'article',
                style: FacteurTypography.bodySmall(c.primary).copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_forward, size: 14, color: c.primary),
            ],
          ),
        ),
      ],
    ];
  }

  Future<void> _openArticle(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  /// Découpe `snippet` autour de `surface` (insensible casse/accents) et met la
  /// surface en gras + surligné. Si la surface est introuvable, rend le texte tel quel.
  TextSpan _highlight(BuildContext context, String snippet, String? surface) {
    final c = context.facteurColors;
    final bold = GoogleFonts.fraunces(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      height: 1.45,
      color: c.primary,
      backgroundColor: c.primary.withValues(alpha: 0.14),
    );
    if (surface == null || surface.isEmpty) {
      return TextSpan(text: snippet);
    }
    final hay = _fold(snippet);
    final needle = _fold(surface);
    final idx = hay.indexOf(needle);
    if (idx < 0) {
      return TextSpan(text: snippet);
    }
    final end = idx + surface.length;
    return TextSpan(
      children: [
        TextSpan(text: snippet.substring(0, idx)),
        TextSpan(text: snippet.substring(idx, end), style: bold),
        TextSpan(text: snippet.substring(end)),
      ],
    );
  }

  /// Normalisation légère pour la recherche de surface : minuscules + accents
  /// FR courants repliés (la longueur est préservée → les offsets restent valides).
  String _fold(String s) {
    const map = {
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'î': 'i', 'ï': 'i', 'í': 'i',
      'ô': 'o', 'ö': 'o', 'ó': 'o',
      'û': 'u', 'ü': 'u', 'ù': 'u', 'ú': 'u',
      'ç': 'c',
    };
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }
}

/// Cachet circulaire de verdict (`.mv-cachet`) — ✓ Livré / ✕ Manqué /
/// « ? » Révélé (langue au chat, ni gagné ni perdu).
class _Cachet extends StatelessWidget {
  const _Cachet({required this.solved, this.revealed = false});
  final bool solved;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final color = revealed
        ? c.textStamp
        : solved
            ? c.success
            : c.error;
    final glyph = revealed
        ? '?'
        : solved
            ? '✓'
            : '✕';
    final label = revealed
        ? 'RÉVÉLÉ'
        : solved
            ? 'LIVRÉ'
            : 'MANQUÉ';
    return Transform.rotate(
      angle: -9 * math.pi / 180,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: CustomPaint(
                  painter: DashedRRectPainter(
                    color: color.withValues(alpha: 0.45),
                    strokeWidth: 1.5,
                    radius: 999,
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  glyph,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.courierPrime(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
