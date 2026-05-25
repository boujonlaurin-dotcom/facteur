import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Banner that opens a Flux Continu V1.8 section.
///
/// Visual treatment mirrors the FeedScreen hero carrousel cards
/// (`DigestEntryCard._CarouselCard`) — same radial veil and asset
/// incrustation — so the two surfaces feel like one family.
class SectionBanner extends StatelessWidget {
  final String title;
  final String? blurb;
  final Color accent;
  final String? illustrationAsset;

  /// Optional callback fired when the banner is tapped — drives the manual
  /// fold gesture on editorial sections (caret `expand_less` to the right of
  /// the title). When null, the banner is non-interactive (legacy behavior).
  final VoidCallback? onTapFold;

  /// Optional callback for the inline favorite star, posed at the end of the
  /// title's last line. When null, no star is rendered — the banner layout is
  /// strictly identical to the legacy V1.8 banner. Only the two user-favorite
  /// sections (theme1 / theme2) wire this up.
  final VoidCallback? onTapFavorite;

  const SectionBanner({
    super.key,
    required this.title,
    required this.accent,
    this.blurb,
    this.illustrationAsset,
    this.onTapFold,
    this.onTapFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasIllustration = illustrationAsset != null;
    // Reserve the right half for the illustration when present, so the
    // title and blurb never bleed under the asset (QA Laurin 2026-05-14 — V1.8 final).
    final textWidthFactor = hasIllustration ? 0.70 : 0.92;
    // `width: double.infinity` is required because the parent SectionBlock
    // Column uses `CrossAxisAlignment.start`, which would otherwise size
    // this Container to its intrinsic width and leave parchment showing
    // past the gradient on the right.
    // Top-only radius : the cards below the banner butt up against its
    // bottom edge, so rounding the bottom would carve out a parchment notch.
    const topRadius = BorderRadius.vertical(top: Radius.circular(10));
    final container = Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 12),
      constraints: const BoxConstraints(minHeight: 108),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: topRadius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.09),
            accent.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Mirrors `DigestEntryCard._CarouselCard` so the two surfaces
          // share the same hero-card identity.
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 112,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.0,
                    colors: [
                      accent.withValues(alpha: 0.07),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (illustrationAsset != null)
            Positioned.fill(
              child: _BannerIllustration(asset: illustrationAsset!),
            ),
          if (onTapFold != null)
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(
                child: Icon(
                  Icons.expand_less,
                  size: 16,
                  color: colors.textPrimary.withValues(alpha: 0.45),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FractionallySizedBox(
                  widthFactor: textWidthFactor,
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text.rich(
                      TextSpan(
                        text: title,
                        children: onTapFavorite == null
                            ? null
                            : <InlineSpan>[
                                const TextSpan(text: '  '),
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle,
                                  child: _FavoriteStar(
                                    color: colors.primary,
                                    onTap: onTapFavorite!,
                                  ),
                                ),
                              ],
                        style: GoogleFonts.fraunces(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          height: 1.06,
                          letterSpacing: -0.4,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (blurb != null && blurb!.trim().isNotEmpty)
                  FractionallySizedBox(
                    widthFactor: textWidthFactor,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      blurb!,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTapFold == null) return container;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapFold,
        borderRadius: topRadius,
        splashColor: accent.withValues(alpha: 0.08),
        highlightColor: accent.withValues(alpha: 0.04),
        child: container,
      ),
    );
  }
}

/// Inline "favorite" affordance posed at the end of a banner's title (last
/// line), used to signal that a section is one of the user's two configurable
/// favorites. Kept deliberately small — the rule is that this should not
/// disturb the title/blurb/illustration layout.
class _FavoriteStar extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _FavoriteStar({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Gérer mes thèmes favoris',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Icon(
            PhosphorIcons.star(PhosphorIconsStyle.fill),
            size: 14,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Right-anchored illustration, baseline-aligned, faded on the left so it
/// stays as background to the title. Falls back silently if the asset is
/// missing.
class _BannerIllustration extends StatelessWidget {
  final String asset;

  const _BannerIllustration({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0.98, 0.6),
      child: IgnorePointer(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Colors.black, Colors.transparent],
            stops: [0.50, 1.0],
          ).createShader(rect),
          child: Padding(
            padding: const EdgeInsets.only(right: 0, bottom: 2),
            child: Opacity(
              opacity: 0.72,
              child: Image.asset(
                asset,
                height: 78,
                // Source PNGs are 1024² — decode at 2× display height to
                // keep texture memory bounded (saves ~10× per image).
                cacheHeight: 156,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
