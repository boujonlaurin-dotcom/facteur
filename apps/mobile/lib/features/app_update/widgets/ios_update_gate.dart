import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../providers/ios_update_gate_provider.dart';

/// Gate bloquant « Mise à jour requise » (iOS) : recouvre toute l'app quand la
/// version installée est en deçà de `ios_min_supported_version`. Aucune sortie
/// (`PopScope(canPop: false)`, pas de bouton fermer) ; le seul CTA ouvre la
/// fiche App Store.
///
/// Monté en haut du `Stack` racine du shell : renvoie [SizedBox.shrink] tant
/// que le gate n'est pas requis, donc transparent au cas nominal.
class IosUpdateGate extends ConsumerWidget {
  const IosUpdateGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(iosUpdateStatusProvider).valueOrNull;

    if (status == null ||
        status.level != IosUpdateLevel.gate ||
        status.appStoreUrl == null) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      child: Material(
        color: colors.backgroundPrimary,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.arrowCircleUp(PhosphorIconsStyle.fill),
                    size: 56,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Mise à jour requise',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cette version de Facteur n\'est plus prise en charge. '
                    'Mettez à jour depuis l\'App Store pour continuer.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _openAppStore(status.appStoreUrl!),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Mettre à jour',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
