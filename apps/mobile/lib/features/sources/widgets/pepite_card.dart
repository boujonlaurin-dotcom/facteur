import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';

/// Carte "Pépite" affichée dans le carousel de recommandation de sources.
/// Logo central, nom, validation sociale, bouton "Suivre" explicite.
class PepiteCard extends StatelessWidget {
  final Source source;
  final VoidCallback onFollow;
  final VoidCallback onTap;
  final bool isFollowing;

  const PepiteCard({
    super.key,
    required this.source,
    required this.onFollow,
    required this.onTap,
    this.isFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildLogo(colors),
            const SizedBox(height: 10),
            Text(
              source.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _socialProof(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton(
                onPressed: isFollowing ? null : onFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.textPrimary,
                  disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                ),
                child: Text(
                  isFollowing ? '…' : 'Suivre',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _socialProof() {
    final n = source.followerCount;
    if (n <= 0) return 'Source de confiance';
    final lecteurs = n > 1 ? 'lecteurs' : 'lecteur';
    return 'Source de confiance\nde $n $lecteurs';
  }

  Widget _buildLogo(FacteurColors colors) {
    if (source.logoUrl != null && source.logoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(FacteurRadius.small),
        child: Image.network(
          source.logoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLogoFallback(colors),
        ),
      );
    }
    return _buildLogoFallback(colors);
  }

  Widget _buildLogoFallback(FacteurColors colors) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Icon(
        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
        size: 22,
        color: colors.primary,
      ),
    );
  }
}
