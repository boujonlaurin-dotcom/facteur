import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../alerts/models/alert_item.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../models/flux_continu_models.dart';

/// Carte « Tes alertes » de la Tournée : ce que les cloches viennent
/// d'annoncer, une ligne par article.
///
/// Story 30.4 — la carte **est** l'article. Avant, elle affichait « N nouveaux »
/// et renvoyait vers la page de la source, qui rechargeait tout : l'information
/// était cachée derrière un rappel, puis derrière 3-4 s d'écran blanc. Elle
/// porte désormais le titre, et le tap ouvre le lecteur avec le contenu déjà en
/// mémoire.
///
/// Le prix : ~+75 px de hauteur (cf. story). Il est borné par
/// [kAlertsSectionMaxRows], resté à 3, et par l'absence de vignette d'article —
/// le logo de la source suffit à identifier qui publie.
class AlertsSectionCard extends StatelessWidget {
  final AlertsSection section;

  const AlertsSectionCard({super.key, required this.section});

  /// Ouvre l'article annoncé. Le contenu est déjà en mémoire (servi par
  /// `GET /api/alerts`) : `ContentDetailScreen` peint le header au 1ᵉʳ frame
  /// depuis l'`extra`, exactement comme depuis l'Essentiel ou la Tournée.
  void _openRow(BuildContext context, AlertRow row) {
    final content = row.content;
    if (content == null) {
      context.push(alertFallbackRoute(row.alert));
      return;
    }
    context.push(
      '${RoutePaths.fluxContinu}/content/${content.contentId}',
      extra: content.toPreviewContent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final rows = buildAlertRows(section.items, maxRows: kAlertsSectionMaxRows);
    if (rows.isEmpty) return const SizedBox.shrink();

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
          for (final row in rows)
            _AlertRowTile(row: row, onTap: () => _openRow(context, row)),
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

/// Destination de repli quand la cloche n'a aucun contenu à ouvrir (backend v1,
/// ou contenu purgé entre deux rafraîchissements).
///
/// **Jamais `source:<id>` pour un sujet.** `AlertItem.sourceId` porte
/// l'identité du *sujet* quand `kind == topic` : construire une route source
/// avec cet id ouvrait `SourceSectionScreen` sur un `source_id` inexistant, et
/// c'est ce qui produisait la liste vide systématique signalée par le PO.
@visibleForTesting
String alertFallbackRoute(AlertItem alert) {
  if (alert.isTopic) return RoutePaths.alerts;
  final key = 'source:${alert.sourceId}';
  return '${RoutePaths.fluxContinu}/source/${Uri.encodeComponent(key)}';
}

/// Une ligne : logo du média + titre de l'article + méta « cloche · fraîcheur ».
class _AlertRowTile extends StatelessWidget {
  final AlertRow row;
  final VoidCallback onTap;

  const _AlertRowTile({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final content = row.content;
    final alert = row.alert;
    final title = content?.title ?? alert.sourceName;
    final logoUrl = content?.sourceLogoUrl ?? alert.sourceLogoUrl;
    final logoName = (content?.sourceName.isNotEmpty ?? false)
        ? content!.sourceName
        : alert.sourceName;

    return Semantics(
      button: true,
      label: content == null
          ? '${alert.sourceName}, ${_newCountLabel(alert.newContent)}'
          : '${alert.sourceName}, $title',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SourceLogoAvatar.fromUrl(
                  logoUrl: logoUrl,
                  name: logoName,
                  size: content == null ? 26 : 34,
                  radius: FacteurRadius.small,
                ),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: colors.textPrimary,
                        ),
                        maxLines: content == null ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (content != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _metaLine(alert, content),
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (content == null) ...[
                  const SizedBox(width: FacteurSpacing.space2),
                  Text(
                    _newCountLabel(alert.newContent),
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
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

/// « nom de la cloche · 2 h ». Ce nom explique *pourquoi* la ligne est là :
/// indispensable pour un sujet, dont le média change d'un article à l'autre.
///
/// Même format compact que `FluxContinuArticleCard` (`fr_short`) pour que deux
/// cartes voisines ne datent pas leurs articles différemment.
String _metaLine(AlertItem alert, AlertContent content) {
  final publishedAt = content.publishedAt;
  if (publishedAt == null) return alert.sourceName;
  final age = timeago
      .format(publishedAt.toLocal(), locale: 'fr_short')
      .replaceAll('il y a ', '')
      .trim();
  return '${alert.sourceName} · $age';
}

String _newCountLabel(int count) => '$count nouveau${count > 1 ? 'x' : ''}';
