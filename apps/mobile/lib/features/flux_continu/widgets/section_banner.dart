import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

  const SectionBanner({
    super.key,
    required this.title,
    required this.accent,
    this.blurb,
    this.illustrationAsset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // `width: double.infinity` is required because the parent SectionBlock
    // Column uses `CrossAxisAlignment.start`, which would otherwise size
    // this Container to its intrinsic width and leave parchment showing
    // past the gradient on the right.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      constraints: const BoxConstraints(minHeight: 132),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.14),
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
                width: 220,
                height: 140,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.0,
                    colors: [
                      accent.withValues(alpha: 0.12),
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
          // Vertical dashed rule on the left edge.
          Positioned(
            left: 10,
            top: 14,
            bottom: 14,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(2, double.infinity),
                painter: _VerticalDashedPainter(color: accent),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: 0.8,
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      title,
                      style: GoogleFonts.fraunces(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                        height: 1.06,
                        letterSpacing: -0.5,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (blurb != null && blurb!.trim().isNotEmpty)
                  FractionallySizedBox(
                    widthFactor: 0.78,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      blurb!,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        height: 1.45,
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
      alignment: Alignment.bottomRight,
      child: IgnorePointer(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Colors.black, Colors.transparent],
            stops: [0.45, 1.0],
          ).createShader(rect),
          child: Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 2),
            child: Image.asset(
              asset,
              height: 136,
              // Source PNGs are 1024² — decode at 2× display height to
              // keep texture memory bounded (saves ~10× per image).
              cacheHeight: 272,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a vertical dashed line — used as the left rule of the banner.
class _VerticalDashedPainter extends CustomPainter {
  static const double _dashLength = 4;
  static const double _gap = 4;

  final Color color;

  _VerticalDashedPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    double y = 0;
    final centerX = size.width / 2;
    while (y < size.height) {
      final end = (y + _dashLength).clamp(0.0, size.height);
      canvas.drawLine(Offset(centerX, y), Offset(centerX, end), paint);
      y = end + _gap;
    }
  }

  @override
  bool shouldRepaint(_VerticalDashedPainter old) => old.color != color;
}
