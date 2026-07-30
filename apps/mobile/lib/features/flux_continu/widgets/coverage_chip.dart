import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../digest/models/digest_models.dart';

/// Seuil d'affichage de la couverture : en dessous de 2 rédactions, le signal
/// « ce sujet est couvert par plusieurs médias » n'existe pas.
const int kCoverageChipMinSources = 2;

/// Pastille de couverture multi-sources — pile d'avatars (3 max) suivie du
/// nombre de rédactions qui traitent le sujet. C'est le signal qui répond au
/// « pourquoi cet article m'est poussé » et qui justifie « Comparer les
/// angles » ; partagé entre les cartes du flux et la carte hi-fi Essentiel.
class CoverageChip extends StatelessWidget {
  final int sourceCount;
  final List<SourceMini> sources;
  final FacteurColors colors;

  const CoverageChip({
    super.key,
    required this.sourceCount,
    required this.sources,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    const dotSize = 12.0;
    const overlap = 4.0;
    final visibleCount = sources.length < 3 ? sources.length : 3;
    final stackWidth = visibleCount == 0
        ? 0.0
        : dotSize + (visibleCount - 1) * (dotSize - overlap);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visibleCount > 0) ...[
          SizedBox(
            width: stackWidth,
            height: dotSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < visibleCount; i++)
                  Positioned(
                    left: i * (dotSize - overlap),
                    child: SourceDot(
                      name: sources[i].name,
                      logoUrl: sources[i].logoUrl,
                      accent: colors.primary,
                      ringColor: colors.surface,
                      size: dotSize,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          sourceCount > 1 ? '$sourceCount sources' : '1 source',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Source identity dot — logo when [logoUrl] is provided, initial otherwise.
class SourceDot extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final Color accent;
  final Color ringColor;
  final double size;

  const SourceDot({
    super.key,
    required this.name,
    required this.logoUrl,
    required this.accent,
    required this.ringColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.trim().isNotEmpty;
    final initial = _Initial(name: name, fontSize: size * 0.55);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: ringColor, spreadRadius: 1.5, blurRadius: 0),
        ],
      ),
      child: hasLogo
          ? ClipOval(
              child: FacteurImage(
                imageUrl: logoUrl!,
                width: size,
                height: size,
                placeholder: (_) => initial,
                errorWidget: (_) => initial,
              ),
            )
          : initial,
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  final double fontSize;

  const _Initial({required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Text(
      initial,
      style: GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.0,
      ),
    );
  }
}
