import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../feed/repositories/feed_repository.dart';

/// Carte « Pas de recul » affichée tout en bas du reader d'article.
///
/// Surface un article de fond ([reco]) pour prendre du recul sur le sujet lu,
/// avec une raison de match éditoriale ([DeepRecommendation.matchReason]). Un tap
/// ouvre l'article recommandé dans le reader via [onTap].
///
/// Design : variante « Pas de recul · B5 » du handoff Claude Design — bandeau
/// pleine largeur discret (bord supérieur seul, dégradé horizontal en lavis,
/// sans radius ni ombre), recoloré via le token `colors.info` (bleu ⇒ cohérent
/// en clair / sombre / oled).
class DeepRecommendationCard extends StatelessWidget {
  final DeepRecommendation reco;
  final VoidCallback? onTap;

  const DeepRecommendationCard({
    super.key,
    required this.reco,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final info = colors.info;

    return _PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
        decoration: BoxDecoration(
          // Lavis horizontal (≈105°) : de gauche vers droite avec léger biais
          // bas, s'estompant vers transparent avant le bord droit. Variante
          // « strong » propre à la carte (accent PO) — le header contextuel
          // garde le lavis standard.
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: const Alignment(1.0, 0.25),
            colors: DeepReculMedallion.lavisColorsStrong(info),
            stops: const [0.0, 0.5, 0.92],
          ),
          // Bord supérieur seul (bandeau edge-to-edge), accentué (PO).
          border: Border(
            top: BorderSide(color: info.withValues(alpha: 0.28), width: 1.0),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DeepReculMedallion(size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Le pas de recul · Facteur'.toUpperCase(),
                    style: GoogleFonts.courierPrime(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.3,
                      height: 1.0,
                      color: info,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    reco.title,
                    style: GoogleFonts.fraunces(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _SourceMeta(
                    logoUrl: reco.sourceLogoUrl,
                    sourceName: reco.sourceName,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                size: 19,
                color: info,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Médaillon circulaire longue-vue 🔭 (style B5 : pas de ring ni d'ombre).
/// Dégradé radial bleu `info → navy`. Réutilisé par le header contextuel de
/// l'article ouvert depuis un CTA « Pas de recul » (taille réduite).
class DeepReculMedallion extends StatelessWidget {
  /// Diamètre du médaillon ; l'emoji est dimensionné à ≈ `size * 0.48`.
  final double size;

  const DeepReculMedallion({super.key, this.size = 44});

  /// Navy profond fixe (= `--pdr-deep` du mockup) pour le stop « lointain » du
  /// radial, indépendant du thème pour garder la profondeur du médaillon.
  static const Color _deep = Color(0xFF1B4F72);

  /// Triple de couleurs du « lavis » Pas de recul (bleu `info` s'estompant vers
  /// transparent). Source unique partagée par la carte CTA et le header
  /// contextuel du reader → même tint des deux côtés (l'écho visuel est
  /// justement l'intention de la feature). Seuls direction/stops diffèrent.
  static List<Color> lavisColors(Color info) => [
        info.withValues(alpha: 0.11),
        info.withValues(alpha: 0.06),
        Colors.transparent,
      ];

  /// Variante « dense » du lavis, réservée au bandeau de la carte CTA (accent
  /// PO : présence visuelle qui justifie sa priorité en tête de reader). On ne
  /// modifie **pas** [lavisColors] car ce tint est partagé avec le header
  /// contextuel `fromDeepReco` — l'assombrir déborderait sur le header (l'écho
  /// visuel entre les deux reste volontairement discret). Même stops/direction
  /// que la version standard, seule l'opacité change.
  static List<Color> lavisColorsStrong(Color info) => [
        info.withValues(alpha: 0.16),
        info.withValues(alpha: 0.09),
        Colors.transparent,
      ];

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Désature légèrement les deux extrémités vers la surface : couleur « moins
    // marquée » sans perdre le point focal lumineux du radial.
    final surface = colors.surface;
    final softInfo = Color.lerp(colors.info, surface, 0.12)!;
    final softDeep = Color.lerp(_deep, surface, 0.12)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5), // focal ~30% / 25%
          radius: 0.9,
          colors: [softInfo, softDeep],
          stops: const [0.0, 0.8],
        ),
      ),
      alignment: Alignment.center,
      child: Text('🔭', style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

/// Avatar source (logo, fallback initiale) + nom de source en méta.
class _SourceMeta extends StatelessWidget {
  final String? logoUrl;
  final String sourceName;
  final Color color;

  const _SourceMeta({
    required this.logoUrl,
    required this.sourceName,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = sourceName.isNotEmpty ? sourceName[0].toUpperCase() : '?';
    final hasLogo = logoUrl != null && logoUrl!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child: hasLogo
              ? FacteurImage(
                  imageUrl: logoUrl!,
                  width: 16,
                  height: 16,
                  fit: BoxFit.cover,
                  errorWidget: (_) => _initialAvatar(colorScheme, initial),
                )
              : _initialAvatar(colorScheme, initial),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            sourceName,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _initialAvatar(ColorScheme colorScheme, String initial) {
    return Container(
      alignment: Alignment.center,
      color: colorScheme.surfaceContainerHighest,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Press state des cartes existantes : scale(0.98) + opacity .8 sur ~150ms.
class _PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _PressableScale({required this.child, this.onTap});

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.8 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}
