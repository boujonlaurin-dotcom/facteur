import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../alerts/models/alert_item.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/flux_continu_models.dart';
import '../utils/theme_color_mapping.dart';

/// Carte « Tes alertes » de la Tournée : les cloches « source rare » qui ont du
/// neuf non lu, en une ligne chacune.
///
/// Volontairement compacte et sans bandeau de section : une alerte est un
/// rappel, pas un flux. Elle annonce ce qui a bougé et renvoie tout de suite
/// vers la source ; l'inventaire complet des cloches (et leur réglage) reste
/// dans « Mes alertes ».
class AlertsSectionCard extends StatelessWidget {
  final AlertsSection section;

  const AlertsSectionCard({super.key, required this.section});

  /// Ouvre la curation complète de la source alertée. On passe une section
  /// synthétique en `extra` pour que l'écran ait tout de suite le nom + le logo :
  /// une source alertée n'est pas forcément une section de la Tournée, donc
  /// `SourceSectionScreen` ne peut pas toujours la retrouver dans l'état.
  void _openSource(BuildContext context, AlertItem item) {
    final key = 'source:${item.sourceId}';
    context.push(
      '${RoutePaths.fluxContinu}/source/${Uri.encodeComponent(key)}',
      extra: FeedThemeSection(
        kind: SectionKind.source,
        label: item.sourceName,
        accent: sourceAccentFor(item.sourceId),
        coreVisibleCount: 3,
        sourceId: item.sourceId,
        sourceLogoUrl: item.sourceLogoUrl,
        items: const [],
        hasMore: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final visible = section.items.take(kAlertsSectionMaxRows).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space3,
        FacteurSpacing.space4,
        FacteurSpacing.space2,
      ),
      decoration: facteurSurfaceCardDecoration(colors, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIcons.bellRinging(PhosphorIconsStyle.fill),
                size: 15,
                color: section.accent,
              ),
              const SizedBox(width: 6),
              Text(
                section.label,
                style: textTheme.labelSmall?.copyWith(
                  color: section.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space2),
          for (final item in visible)
            _AlertRow(item: item, onTap: () => _openSource(context, item)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.pushNamed(RouteNames.alerts),
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Gérer mes alertes'),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une cloche : logo + nom de la source + compteur de neuf non lu.
class _AlertRow extends StatelessWidget {
  final AlertItem item;
  final VoidCallback onTap;

  const _AlertRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '${item.sourceName}, ${_newCountLabel(item.newContent)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SourceLogoAvatar.fromUrl(
                  logoUrl: item.sourceLogoUrl,
                  name: item.sourceName,
                  size: 26,
                  radius: FacteurRadius.small,
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Text(
                    item.sourceName,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                Text(
                  _newCountLabel(item.newContent),
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _newCountLabel(int count) => '$count nouveau${count > 1 ? 'x' : ''}';
