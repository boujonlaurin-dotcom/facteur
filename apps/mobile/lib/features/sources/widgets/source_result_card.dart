import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../widgets/design/facteur_image.dart';
import '../models/smart_search_result.dart';
import 'recent_articles_list.dart';

class SourceResultCard extends StatelessWidget {
  final SmartSearchResult result;
  final VoidCallback onAdd;
  final VoidCallback onPreview;
  final bool isAdded;

  /// Ajout en cours : le bouton affiche un spinner et devient non cliquable
  /// (empêche les double-taps le temps de l'appel réseau).
  final bool isAdding;

  /// Mode preuve (onboarding) : à l'ajout, la carte se transforme en bloc
  /// « Connecté » avec les derniers articles, au lieu d'ouvrir la modal.
  final bool showProof;

  const SourceResultCard({
    super.key,
    required this.result,
    required this.onAdd,
    required this.onPreview,
    this.isAdded = false,
    this.isAdding = false,
    this.showProof = false,
  });

  IconData _typeIcon() {
    switch (result.type) {
      case 'youtube':
        return PhosphorIcons.youtubeLogo(PhosphorIconsStyle.fill);
      case 'reddit':
        return PhosphorIcons.redditLogo(PhosphorIconsStyle.fill);
      case 'podcast':
        return PhosphorIcons.microphone(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.rss(PhosphorIconsStyle.fill);
    }
  }

  String _typeLabel() {
    switch (result.type) {
      case 'youtube':
        return 'YouTube';
      case 'reddit':
        return 'Reddit';
      case 'podcast':
        return 'Podcast';
      case 'rss':
      case 'atom':
        return 'RSS';
      default:
        return 'Article';
    }
  }

  /// Correspondance « parfaite » : source du catalogue ET curée. Elle mérite
  /// l'affordance « Source vérifiée » et un CTA « Suivre {nom} » plutôt que le
  /// générique « Ajouter » (réservé aux URL custom / résultats non curés).
  bool get _isCuratedCatalogMatch => result.inCatalog && result.isCurated;

  /// Libellé du CTA d'ajout. Pour une correspondance vérifiée on nomme la
  /// source (« Suivre Le Monde ») en tronquant proprement les noms longs.
  String _addCtaLabel() {
    if (!_isCuratedCatalogMatch) return 'Ajouter';
    final name = result.name.trim();
    if (name.isEmpty) return 'Suivre';
    const maxLen = 22;
    final shortName = name.length > maxLen
        ? '${name.substring(0, maxLen).trimRight()}...'
        : name;
    return 'Suivre $shortName';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final proofMode = showProof && isAdded;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: proofMode ? colors.success : colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeOutCubic,
          child: proofMode
              ? _buildProofView(context, colors)
              : _buildDefaultView(context, colors),
        ),
      ),
    );
  }

  /// Vue preuve « Connecté » : identité de la source + derniers articles.
  Widget _buildProofView(BuildContext context, FacteurColors colors) {
    return Column(
      key: const ValueKey('proof'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
              size: 20,
              color: colors.success,
            ),
            const SizedBox(width: 6),
            Text(
              'Connecté',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.success,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildFavicon(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.name,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (result.recentItems.isNotEmpty)
          RecentArticlesList(items: result.recentItems)
        else
          Text(
            'Ses prochains articles arrivent dans votre tournée.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
      ],
    );
  }

  Widget _buildDefaultView(BuildContext context, FacteurColors colors) {
    final recentTitles = result.recentItems.take(3).toList();

    return Column(
      key: const ValueKey('default'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: favicon + name + type
        Row(
          children: [
            _buildFavicon(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(_typeIcon(), size: 14, color: colors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        _typeLabel(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                      ),
                      if (_isCuratedCatalogMatch) ...[
                        const SizedBox(width: 8),
                        _buildVerifiedPill(context, colors),
                      ] else if (result.inCatalog) ...[
                        const SizedBox(width: 8),
                        Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
                            size: 14, color: colors.primary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Description
        if (result.description != null && result.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            result.description!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // Recent items — preuve honnête que la source est vivante. Pour une
        // correspondance vérifiée, on les met en avant avec la présentation
        // riche (même bloc que la vue « Connecté »). Aucun fetch : on ne fait
        // que re-présenter `result.recentItems` déjà chargés.
        if (recentTitles.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_isCuratedCatalogMatch)
            RecentArticlesList(items: result.recentItems)
          else ...[
            Text(
              'Derniers articles :',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            ...recentTitles.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(PhosphorIcons.dotOutline(PhosphorIconsStyle.fill),
                          size: 14, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],

        // CTAs
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onPreview,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: colors.border),
                ),
                child: Text(
                  'Apercu',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: isAdded
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(
                          PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                          size: 18,
                          color: colors.success),
                      label: Text('Ajoutee',
                          style: TextStyle(color: colors.success)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: colors.success),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: isAdding ? null : onAdd,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: colors.primary,
                        foregroundColor: colors.textPrimary,
                        disabledBackgroundColor:
                            colors.primary.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: isAdding
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    colors.textPrimary),
                              ),
                            )
                          : Text(
                              _addCtaLabel(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  /// Pastille « Source vérifiée » pour une correspondance catalogue curée.
  /// Distingue visuellement une source vérifiée d'un résultat URL custom.
  Widget _buildVerifiedPill(BuildContext context, FacteurColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIcons.sealCheck(PhosphorIconsStyle.fill),
              size: 13, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            'Source vérifiée',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavicon(FacteurColors colors) {
    if (result.faviconUrl != null && result.faviconUrl!.isNotEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: FacteurImage(
          imageUrl: result.faviconUrl!,
          fit: BoxFit.cover,
          errorWidget: (context) => Container(
            color: colors.backgroundSecondary,
            child: Icon(_typeIcon(), color: colors.primary, size: 22),
          ),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_typeIcon(), color: colors.primary, size: 22),
    );
  }
}
