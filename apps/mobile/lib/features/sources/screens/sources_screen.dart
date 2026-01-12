import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';

import '../providers/sources_providers.dart';
import '../widgets/source_list_item.dart';

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources de confiance'),
        actions: [],
      ),
      body: sourcesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Erreur: $err')),
        data: (sources) {
          if (sources.isEmpty) {
            return Center(
              child: Text(
                'Aucune source disponible',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Text(
                    "Indiquez-nous les sources auxquelles vous faites le plus confiance. Nous les privilégierons par défaut dans votre feed.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                  ),
                );
              }
              final source = sources[index - 1];
              return SourceListItem(
                source: source,
                onTap: () {
                  ref
                      .read(userSourcesProvider.notifier)
                      .toggleTrust(source.id, source.isTrusted);
                },
              );
            },
          );
        },
      ),
    );
  }
}
