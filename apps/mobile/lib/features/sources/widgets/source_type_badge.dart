import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';

/// Chip discret « icône + libellé » au style pill (bordure, fond surface, texte
/// secondaire). Chassis partagé pour tous les petits badges de l'onboarding et
/// des fiches source (format, tier, fréquence…) — évite de redéclarer le même
/// Container à chaque emplacement.
class IconLabelPill extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Taille de l'icône (défaut 14).
  final double iconSize;

  const IconLabelPill({
    super.key,
    required this.icon,
    required this.label,
    this.iconSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Badge « format » rendu **uniquement pour les sources non-article** (YouTube,
/// Podcast, Vidéo, Reddit). Pour un `article`, [Source.getTypeIcon] renvoie
/// `null` et le badge se masque (`SizedBox.shrink`) — le format article est
/// implicite, jamais badgé. Réutilisé sur le swipe, les recos et la fiche source.
class SourceTypeBadge extends StatelessWidget {
  final Source source;

  /// Taille de l'icône (défaut 14, cohérent avec les chips de format).
  final double iconSize;

  const SourceTypeBadge({
    super.key,
    required this.source,
    this.iconSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final icon = source.getTypeIcon();
    if (icon == null) return const SizedBox.shrink();
    return IconLabelPill(
      icon: icon,
      label: source.getTypeLabel(),
      iconSize: iconSize,
    );
  }
}
