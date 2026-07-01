import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/sources_providers.dart';

/// Délai après un « plus tard » avant de re-proposer la reconnexion. Le bandeau
/// reste auto-clearing : si tout est reconnecté avant la fin du cooldown, il
/// disparaît de lui-même (liste vide).
const Duration kReconnectBannerCooldown = Duration(days: 7);

/// Box Hive partagée des réglages (même box que les clés re-nudge / géoloc).
const String _kSettingsBox = 'settings';

/// Persistance Hive (box `settings`) du dernier dismiss du bandeau de
/// reconnexion. Même pattern que les clés re-nudge / géoloc.
class ReconnectBannerController {
  ReconnectBannerController(this._ref);

  final Ref _ref;

  static const kDismissedAt = 'reconnect_banner_dismissed_at';

  /// Enregistre un dismiss (« plus tard ») : démarre le cooldown.
  Future<void> dismiss() async {
    try {
      final box = await Hive.openBox<dynamic>(_kSettingsBox);
      await box.put(kDismissedAt, DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      debugPrint('ReconnectBanner: Hive write failed: $e');
    }
    _ref.invalidate(reconnectBannerCooldownActiveProvider);
  }
}

final reconnectBannerControllerProvider =
    Provider<ReconnectBannerController>((ref) {
  return ReconnectBannerController(ref);
});

/// `true` tant que le cooldown du dernier dismiss n'est pas écoulé (bandeau
/// masqué). Défaut prudent : `true` en cas d'échec de lecture Hive (on ne
/// flashe pas le bandeau si l'état de dismiss est inconnu).
final reconnectBannerCooldownActiveProvider = FutureProvider<bool>((ref) async {
  try {
    final box = await Hive.openBox<dynamic>(_kSettingsBox);
    final raw =
        box.get(ReconnectBannerController.kDismissedAt) as String?;
    if (raw == null || raw.isEmpty) return false;
    final dismissedAt = DateTime.tryParse(raw);
    if (dismissedAt == null) return false;
    return DateTime.now().toUtc().difference(dismissedAt) <
        kReconnectBannerCooldown;
  } catch (e) {
    debugPrint('ReconnectBanner: Hive read failed: $e');
    return true;
  }
});

/// Bandeau inline (haut du shell) qui repropose de reconnecter les abonnements
/// dont la session locale a été perdue (réinstallation / reset OS). On ne
/// restaure jamais la session côté serveur (choix privacy) : on détecte
/// « abonné mais session locale absente » et on renvoie vers l'écran
/// Abonnements existant. Se masque seul une fois tout reconnecté.
class ReconnectSubscriptionsBanner extends ConsumerStatefulWidget {
  const ReconnectSubscriptionsBanner({super.key});

  @override
  ConsumerState<ReconnectSubscriptionsBanner> createState() =>
      _ReconnectSubscriptionsBannerState();
}

class _ReconnectSubscriptionsBannerState
    extends ConsumerState<ReconnectSubscriptionsBanner> {
  /// Dismiss de session : tant que le shell vit, on ne ré-affiche pas après un
  /// « plus tard ». Le cooldown Hive prend le relais au prochain cold start.
  bool _dismissedThisSession = false;

  Future<void> _onDismiss() async {
    await ref.read(reconnectBannerControllerProvider).dismiss();
    if (!mounted) return;
    setState(() => _dismissedThisSession = true);
  }

  void _onReconnect() {
    context.pushNamed(RouteNames.subscriptions);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissedThisSession) return const SizedBox.shrink();

    final needing =
        ref.watch(subscriptionsNeedingReconnectProvider).valueOrNull ??
            const <Object>[];
    if (needing.isEmpty) return const SizedBox.shrink();

    // Défaut `true` (cooldown actif) tant que la lecture Hive n'a pas résolu :
    // évite un flash du bandeau au premier frame.
    final cooldownActive =
        ref.watch(reconnectBannerCooldownActiveProvider).valueOrNull ?? true;
    if (cooldownActive) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final theme = Theme.of(context);
    final count = needing.length;
    final subtitle = count == 1
        ? '1 abonnement à reconnecter après la mise à jour.'
        : '$count abonnements à reconnecter après la mise à jour.';

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space3,
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIcons.link(PhosphorIconsStyle.bold),
            size: 22,
            color: colors.primary,
          ),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reconnecte tes abonnements',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: FacteurSpacing.space2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _onReconnect,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space2,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Reconnecter'),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Plus tard',
            visualDensity: VisualDensity.compact,
            onPressed: _onDismiss,
            icon: Icon(
              PhosphorIcons.x(PhosphorIconsStyle.regular),
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
