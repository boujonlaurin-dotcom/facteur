import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';
import 'source_logo_avatar.dart';

/// Carte "Pépite" affichée dans le carousel de recommandation de sources.
/// Logo grand format prioritaire, validation sociale (followers), bouton
/// "Suivre" qui passe à l'état "Suivi ✓" sans faire disparaître la carte.
/// Bordure en pointillés + fond teinté primary pour signaler le statut
/// "suggestion / non encore activée".
class PepiteCard extends StatelessWidget {
  final Source source;
  final VoidCallback onToggleFollow;
  final VoidCallback onTap;
  final bool isFollowing;

  const PepiteCard({
    super.key,
    required this.source,
    required this.onToggleFollow,
    required this.onTap,
    this.isFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final radius = BorderRadius.circular(FacteurRadius.medium);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        foregroundPainter: _DashedRRectPainter(
          color: colors.primary.withValues(alpha: 0.45),
          radius: FacteurRadius.medium,
          strokeWidth: 1.2,
          dash: 4,
          gap: 3,
        ),
        child: Container(
          width: 170,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: radius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SourceLogoAvatar(source: source, size: 64, radius: 12),
              const SizedBox(height: 10),
              Text(
                source.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(FacteurRadius.small),
                ),
                child: Text(
                  source.getThemeLabel(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10.5,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              if (source.followerCount > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.users(PhosphorIconsStyle.regular),
                      size: 12,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${source.followerCount} '
                        '${source.followerCount > 1 ? "lecteurs" : "lecteur"}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              fontSize: 11,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: OutlinedButton(
                  onPressed: onToggleFollow,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colors.surface,
                    foregroundColor: colors.primary,
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: colors.primary, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.small),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isFollowing) ...[
                        Icon(
                          PhosphorIcons.check(PhosphorIconsStyle.bold),
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        isFollowing ? 'Suivi' : 'Suivre',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trace une bordure en pointillés autour d'un RRect — utilisée pour signaler
/// les cartes "non encore activées" (pattern récurrent dans l'app).
class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}
