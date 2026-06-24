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
/// Design : composant `CardFinal` du handoff « Pas de recul · B6 final »,
/// recoloré de la palette bleue d'origine vers l'orange `primary` Facteur (tokens
/// dérivés de `colors.*` ⇒ cohérent en clair / sombre / oled).
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
    final primary = colors.primary;
    final deep = colors.sectionEssentiel;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: _PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 14, 13, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // Fondu primary → surface, plus doux et léger qu'avant : teinte
            // discrète qui s'efface vers la surface (3 stops lissés).
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.08),
                primary.withValues(alpha: 0.03),
                colors.surface,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                offset: const Offset(0, 1),
                blurRadius: 6,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Medallion(primary: primary, deep: deep),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pas de recul'.toUpperCase(),
                      style: GoogleFonts.courierPrime(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
                        height: 1.0,
                        color: deep,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      reco.title,
                      style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                        letterSpacing: -0.3,
                        color: colors.textPrimary,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (reco.matchReason.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        reco.matchReason.trim(),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          height: 1.3,
                          color: colors.textSecondary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 5),
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
                  size: 18,
                  color: primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Médaillon circulaire 44px avec emoji longue-vue (style B5 : pas de ring ni
/// d'ombre). Dégradé radial `primary → sectionEssentiel`.
class _Medallion extends StatelessWidget {
  final Color primary;
  final Color deep;

  const _Medallion({required this.primary, required this.deep});

  @override
  Widget build(BuildContext context) {
    // Désature légèrement les deux extrémités vers la surface : couleur « moins
    // marquée » sans perdre la chaleur ni le point focal lumineux du radial.
    final surface = context.facteurColors.surface;
    final softPrimary = Color.lerp(primary, surface, 0.12)!;
    final softDeep = Color.lerp(deep, surface, 0.12)!;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5), // focal ~30% / 25%
          radius: 0.9,
          colors: [softPrimary, softDeep],
          stops: const [0.0, 0.8],
        ),
      ),
      alignment: Alignment.center,
      child: const Text('🔭', style: TextStyle(fontSize: 21)),
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
