import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../providers/ios_update_gate_provider.dart';

/// Bandeau discret « nouvelle version dispo » (iOS), affiché tant que la version
/// installée est en deçà de `ios_latest_version` et que le gate n'est pas actif.
/// Tap → ouvre la fiche App Store. `×` → masque pour la session.
///
/// Calqué sur `ChangelogBanner` (Material 10% primary, icône, texte, `×`).
class IosUpdateBanner extends ConsumerWidget {
  const IosUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(iosUpdateStatusProvider).valueOrNull;
    final dismissed = ref.watch(iosBannerDismissedProvider);

    if (dismissed ||
        status == null ||
        status.level != IosUpdateLevel.banner ||
        status.appStoreUrl == null) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Material(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _openAppStore(status.appStoreUrl!),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.arrowCircleUp(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nouvelle version disponible. Touchez pour mettre à jour.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(iosBannerDismissedProvider.notifier).state = true,
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

Future<void> _openAppStore(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
