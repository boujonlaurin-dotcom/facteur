import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
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
            return _EmptyState(
              colors: colors,
              onAdd: () => _showAddSubscriptionSheet(context),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            children: [
              PrimaryButton(
                label: 'Ajouter un abonnement',
                icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
                onPressed: () => _showAddSubscriptionSheet(context),
              ),
              const SizedBox(height: FacteurSpacing.space4),
              for (var i = 0; i < subscribed.length; i++) ...[
                _SubscriptionTile(source: subscribed[i]),
                if (i < subscribed.length - 1)
                  const SizedBox(height: FacteurSpacing.space3),
              ],
            ],
          );
        }(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final FacteurColors colors;
  final VoidCallback onAdd;

  const _EmptyState({required this.colors, required this.onAdd});

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
              'Connecte un média payant que tu suis déjà pour lire ses '
              'articles directement dans Facteur.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            PrimaryButton(
              label: 'Ajouter un abonnement',
              icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
              onPressed: onAdd,
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
                          active ? 'Session active' : 'Reconnexion nécessaire',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: active ? colors.success : colors.warning,
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
    // `forceGenericConnection` est un superset : renvoie la connexion curée si
    // utilisable, sinon un flux générique depuis l'URL. Couvre donc aussi les
    // sources libres connectées génériquement (backend sans `premium_connection`).
    final connection =
        resolvePremiumConnection(source) ?? forceGenericConnection(source);
    if (connection == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          connection: connection,
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

Future<void> _showAddSubscriptionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddSubscriptionSheet(),
  );
}

class _AddSubscriptionSheet extends ConsumerStatefulWidget {
  const _AddSubscriptionSheet();

  @override
  ConsumerState<_AddSubscriptionSheet> createState() =>
      _AddSubscriptionSheetState();
}

class _AddSubscriptionSheetState extends ConsumerState<_AddSubscriptionSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final eligible = ref.watch(eligibleSubscriptionSourcesProvider);
    final loginConnectable = ref.watch(loginConnectableSourcesProvider);
    bool matchesQuery(Source source) =>
        _query.isEmpty || source.name.toLowerCase().contains(_query);
    final eligibleVisible = eligible.where(matchesQuery).toList();
    final loginVisible = loginConnectable.where(matchesQuery).toList();
    final hasAny = eligible.isNotEmpty || loginConnectable.isNotEmpty;
    final hasVisible = eligibleVisible.isNotEmpty || loginVisible.isNotEmpty;
    List<Widget> tilesFor(
      List<Source> sources,
      PremiumConnection Function(Source) resolve,
    ) =>
        [
          for (final source in sources) ...[
            _EligibleSourceTile(source: source, connection: resolve(source)),
            Divider(color: colors.border.withValues(alpha: 0.5)),
          ],
        ];

    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Material(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: FacteurSpacing.space3),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space4,
                  FacteurSpacing.space4,
                  FacteurSpacing.space2,
                  FacteurSpacing.space3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ajouter un abonnement',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.regular),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasAny)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FacteurSpacing.space4,
                    0,
                    FacteurSpacing.space4,
                    FacteurSpacing.space3,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher parmi mes sources suivies',
                      prefixIcon: Icon(
                        PhosphorIcons.magnifyingGlass(
                          PhosphorIconsStyle.regular,
                        ),
                      ),
                    ),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                  ),
                ),
              Expanded(
                child: !hasAny
                    ? _NoEligibleSources(
                        onChooseSources: () {
                          final router = GoRouter.of(context);
                          Navigator.of(context).pop();
                          router.pushNamed(RouteNames.sources);
                        },
                      )
                    : !hasVisible
                        ? Center(
                            child: Text(
                              'Aucun média ne correspond à cette recherche.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(
                              FacteurSpacing.space4,
                              0,
                              FacteurSpacing.space4,
                              FacteurSpacing.space6,
                            ),
                            children: [
                              ...tilesFor(
                                eligibleVisible,
                                (source) => resolvePremiumConnection(source)!,
                              ),
                              if (loginVisible.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: FacteurSpacing.space2,
                                    bottom: FacteurSpacing.space1,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Un autre site demande une connexion ?',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Connecte ton compte sur n’importe quel '
                                        'média que tu suis pour lire ses articles '
                                        'dans Facteur.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                              height: 1.4,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                ...tilesFor(
                                  loginVisible,
                                  (source) => forceGenericConnection(source)!,
                                ),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoEligibleSources extends StatelessWidget {
  const _NoEligibleSources({required this.onChooseSources});

  final VoidCallback onChooseSources;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
              size: 44,
              color: colors.textTertiary,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              'Aucun média payant suivi',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              'Suis d’abord un média payant dans Mes sources pour pouvoir '
              'connecter ton abonnement.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: FacteurSpacing.space6),
            OutlinedButton.icon(
              onPressed: onChooseSources,
              icon: Icon(PhosphorIcons.bookOpen(PhosphorIconsStyle.regular)),
              label: const Text('Choisir mes sources'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EligibleSourceTile extends ConsumerWidget {
  const _EligibleSourceTile({required this.source, required this.connection});

  final Source source;
  final PremiumConnection connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space2),
      child: Row(
        children: [
          SourceLogoAvatar(source: source, size: 40),
          const SizedBox(width: FacteurSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  connection.isGeneric
                      ? 'Connexion sur le site du média'
                      : 'Connexion guidée disponible',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          TextButton(
            onPressed: () => _connect(context, ref, connection),
            child: Text(connection.isGeneric ? 'Associer' : 'Connecter'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    PremiumConnection connection,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PremiumSourceConnection(
          source: source,
          connection: connection,
          onConnected: () => ref
              .read(userSourcesProvider.notifier)
              .connectSubscription(source.id),
        ),
      ),
    );
  }
}
