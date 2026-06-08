import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/premium_source_connection.dart';
import '../../sources/widgets/source_logo_avatar.dart';

/// Écran « Mes abonnements » : point d'entrée global pour gérer les sources
/// payantes connectées (statut de session, reconnexion, dissociation).
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final subscribed = ref.watch(subscribedSourcesProvider);
    final isLoading = ref.watch(userSourcesProvider).isLoading;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mes abonnements'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: Theme.of(context).textTheme.displaySmall,
      ),
      body: SafeArea(
        child: () {
          if (subscribed.isEmpty && isLoading) {
            return Center(
              child: CircularProgressIndicator(color: colors.primary),
            );
          }
          if (subscribed.isEmpty) {
            return _EmptyState(colors: colors);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            itemCount: subscribed.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: FacteurSpacing.space3),
            itemBuilder: (_, i) => _SubscriptionTile(source: subscribed[i]),
          );
        }(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final FacteurColors colors;
  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.lockKeyOpen(PhosphorIconsStyle.regular),
              size: 48,
              color: colors.textTertiary,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              'Aucun abonnement connecté',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              'Connecte un abonnement à un média payant depuis sa fiche pour '
              'lire ses articles directement dans Facteur.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  final Source source;
  const _SubscriptionTile({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final store = ref.watch(premiumSessionStoreProvider);

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.surfaceElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceLogoAvatar(source: source, size: 40),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<bool>(
                      future: store.hasSession(source),
                      builder: (context, snap) {
                        final active = snap.data ?? false;
                        return Text(
                          active
                              ? 'Session active'
                              : 'Reconnexion nécessaire',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: active
                                        ? colors.success
                                        : colors.warning,
                                  ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _reconnect(context, ref),
                  icon: Icon(PhosphorIcons.link(), size: 18),
                  label: const Text('Reconnecter'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _disconnect(ref),
                  icon: Icon(PhosphorIcons.linkBreak(), size: 18),
                  label: const Text('Dissocier'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _reconnect(BuildContext context, WidgetRef ref) async {
    if (source.premiumConnection == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          onConnected: () => ref
              .read(userSourcesProvider.notifier)
              .connectSubscription(source.id),
        ),
      ),
    );
  }

  Future<void> _disconnect(WidgetRef ref) async {
    await ref
        .read(userSourcesProvider.notifier)
        .disconnectSubscription(source.id);
    await ref.read(premiumSessionStoreProvider).clearForSource(source);
  }
}
