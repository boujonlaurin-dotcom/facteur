import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import 'diff_title.dart';
import 'perspectives_bottom_sheet.dart' show Perspective, openPerspectiveReader;

/// Carte de comparaison « Couverture médiatique » (gabarit parchemin du proto
/// carrousel v4). Réutilisable : titre diff-surligné au-dessus, footer
/// source + biais + temps relatif en bas. Tap → reader de la perspective.
///
/// **Contrat de hauteur** : la carte épingle son footer en bas via un
/// [Column] à hauteur pleine — elle doit donc être posée dans un contexte qui
/// **borne sa hauteur** (le carrousel l'enveloppe dans un viewport de hauteur
/// fixe + `CrossAxisAlignment.stretch`). Largeur fixe 248 px.
class CoverageComparisonCard extends StatelessWidget {
  final Perspective perspective;

  /// Clé posée sur la 1ʳᵉ carte du carrousel pour que l'écran parent détecte
  /// le scroll au-delà (nudge CTA). `null` sur les cartes suivantes.
  final Key? firstCardKey;

  const CoverageComparisonCard({
    super.key,
    required this.perspective,
    this.firstCardKey,
  });

  /// Temps relatif depuis `publishedAt` (`timeago` `fr_short`). `null` si la
  /// date est absente ou non parsable → le slot temps est masqué (on
  /// n'invente jamais de durée de lecture).
  static String? relativeTime(String? publishedAt) {
    if (publishedAt == null) return null;
    final dt = DateTime.tryParse(publishedAt);
    if (dt == null) return null;
    return timeago.format(dt, locale: 'fr_short');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final biasColor = perspective.getBiasColor(colors);

    return SizedBox(
      key: firstCardKey,
      width: 248,
      child: FacteurCard(
        onTap: () => openPerspectiveReader(context, perspective),
        backgroundColor: colors.surface,
        borderRadius: 16,
        padding: const EdgeInsets.all(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DiffTitle(
                title: perspective.title,
                highlightSpans: perspective.highlightSpans,
                sharedTokens: perspective.sharedTokens,
                biasColor: biasColor,
                maxLines: 4,
                baseStyle: textTheme.bodyMedium?.copyWith(
                      fontSize: 15.5,
                      height: 1.42,
                      letterSpacing: -0.1,
                      color: colors.textPrimary,
                    ) ??
                    GoogleFonts.dmSans(
                      fontSize: 15.5,
                      height: 1.42,
                      letterSpacing: -0.1,
                      color: colors.textPrimary,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            _Footer(perspective: perspective, biasColor: biasColor),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final Perspective perspective;
  final Color biasColor;

  const _Footer({required this.perspective, required this.biasColor});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final timeLabel = CoverageComparisonCard.relativeTime(
      perspective.publishedAt,
    );

    // Groupe source + biais à gauche (shrink via le nom), temps à droite.
    // `spaceBetween` + un seul Flexible évite la famine de largeur d'un
    // Spacer concurrent (sinon la pastille déborde sur les noms longs).
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SourcePastille(
                domain: perspective.sourceDomain,
                name: perspective.sourceName,
                colors: colors,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  perspective.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              // Chip biais (dot + libellé MAJ coloré).
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: biasColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                perspective.getBiasLabel().toUpperCase(),
                style: GoogleFonts.courierPrime(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: biasColor,
                ),
              ),
            ],
          ),
        ),
        // Slot temps relatif, épinglé à droite. Masqué si pas de date.
        if (timeLabel != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 9),
              Icon(
                PhosphorIcons.clock(PhosphorIconsStyle.regular),
                size: 12,
                color: colors.textTertiary,
              ),
              const SizedBox(width: 3),
              Text(
                timeLabel,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _SourcePastille extends StatelessWidget {
  final String domain;
  final String name;
  final FacteurColors colors;

  const _SourcePastille({
    required this.domain,
    required this.name,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (domain.isEmpty) {
      return _SourceFallback(name: name, colors: colors);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$domain&sz=64',
        width: 20,
        height: 20,
        errorBuilder: (_, __, ___) => _SourceFallback(name: name, colors: colors),
      ),
    );
  }
}

/// Pastille de repli quand le favicon est absent ou échoue : initiale de la
/// source sur fond clair. Relocalisée depuis `perspectives_bottom_sheet.dart`
/// (l'ancien `_VariantRow` supprimé) — partagée par la carte de couverture.
class _SourceFallback extends StatelessWidget {
  final String name;
  final FacteurColors colors;

  const _SourceFallback({required this.name, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
