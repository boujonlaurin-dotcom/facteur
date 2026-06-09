import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/changelog_entry.dart';
import '../providers/changelog_provider.dart';
import 'whats_new_modal.dart';

/// Bandeau discret affiché en haut du Flâner tant que des releases sont non
/// vues. Affiche la concaténation des `tag` séparés par `, ` avec `…` quand
/// ça déborde (via `TextOverflow.ellipsis`). Tap → ouvre le modal détaillé.
/// `×` → marque vu sans ouvrir le modal.
class ChangelogBanner extends ConsumerWidget {
  const ChangelogBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReleases = ref.watch(unseenReleasesProvider);

    return asyncReleases.maybeWhen(
      data: (releases) => releases.isEmpty
          ? const SizedBox.shrink()
          : _ChangelogBannerContent(releases: releases),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ChangelogBannerContent extends ConsumerWidget {
  const _ChangelogBannerContent({required this.releases});

  final List<ChangelogRelease> releases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final tags = _collectTags(releases);
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => showWhatsNewModal(context, ref, releases),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tags.join(', '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => markChangelogSeen(ref),
                  icon: Icon(
                    PhosphorIcons.x(),
                    size: 16,
                    color: colors.textTertiary,
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  tooltip: 'Ignorer',
                  splashRadius: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collecte les tags des releases non vues, dans l'ordre fourni (caller
/// garantit déjà l'ordre version desc). Pas de dédup — si deux versions ont le
/// même tag, on l'affiche deux fois (rare en pratique, et la troncature gère).
List<String> _collectTags(List<ChangelogRelease> releases) {
  return [
    for (final r in releases)
      for (final e in r.entries) e.tag,
  ];
}
