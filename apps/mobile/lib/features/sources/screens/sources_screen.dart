import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';

import '../providers/sources_providers.dart';
import '../widgets/source_list_item.dart';

class SourcesScreen extends ConsumerStatefulWidget {
  const SourcesScreen({super.key});

  @override
  ConsumerState<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends ConsumerState<SourcesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
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
          // Filtrer et trier
          var filteredSources = sources.toList();

          // Tri alphabétique
          filteredSources.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

          // Recherche
          if (_searchQuery.isNotEmpty) {
            filteredSources = filteredSources
                .where(
                  (s) => s.name.toLowerCase().contains(
                        _searchQuery.toLowerCase(),
                      ),
                )
                .toList();
          }

          if (filteredSources.isEmpty && _searchQuery.isEmpty) {
            return Center(
              child: Text(
                'Aucune source disponible',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            );
          }

          return Column(
            children: [
              // Barre de recherche
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Rechercher une source...',
                    prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                    filled: true,
                    fillColor: colors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                      vertical: FacteurSpacing.space3,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    hintStyle: TextStyle(color: colors.textSecondary),
                  ),
                  style: TextStyle(color: colors.textPrimary),
                  onTapOutside: (_) => FocusScope.of(context).unfocus(),
                ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredSources.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      if (_searchQuery.isNotEmpty)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Text(
                          "Indiquez-nous les sources auxquelles vous faites le plus confiance. Nous les privilégierons par défaut dans votre feed.",
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colors.textSecondary,
                                    height: 1.5,
                                  ),
                        ),
                      );
                    }
                    final source = filteredSources[index - 1];
                    return SourceListItem(
                      source: source,
                      onTap: () {
                        ref
                            .read(userSourcesProvider.notifier)
                            .toggleTrust(source.id, source.isTrusted);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
