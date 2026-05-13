import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Banner that opens a Flux Continu V1.8 section.
///
/// Visual: vertical gradient tinted with the section [accent], a 28×2 rule
/// line over the title, the section title (Fraunces 25), and an optional
/// blurb. When [illustrationAsset] is provided, the asset is rendered on
/// the right side and masked with a left-fade gradient so it stays subtle
/// under the typography.
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
    // The banner is edge-to-edge per V6 spec — the accent gradient and the
    // background illustration fade across the full screen width. Force the
    // width explicitly because the parent SectionBlock Column uses
    // `CrossAxisAlignment.start`, which would otherwise let the Container
    // size to its intrinsic width and leave parchment showing on the right.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 16),
      constraints: const BoxConstraints(minHeight: 96),
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
          if (illustrationAsset != null)
            Positioned.fill(child: _BannerIllustration(asset: illustrationAsset!)),
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
                    widthFactor: 0.8,
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

/// Right-anchored illustration, vertically centered, faded from right to
/// left so it stays as background to the title. Falls back to nothing if
/// the asset can't be decoded.
class _BannerIllustration extends StatelessWidget {
  final String asset;

  const _BannerIllustration({required this.asset});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 0),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Colors.black, Colors.transparent],
            stops: [0.3, 1.0],
          ).createShader(rect),
          child: Opacity(
            opacity: 0.95,
            child: Transform.translate(
              offset: const Offset(16, 0),
              child: Image.asset(
                asset,
                height: 108,
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
