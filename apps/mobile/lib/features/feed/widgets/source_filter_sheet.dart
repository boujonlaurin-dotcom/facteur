import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';

class SourceFilterSheet extends ConsumerStatefulWidget {
  final String? currentSourceId;
  final ValueChanged<String> onSourceSelected;

  const SourceFilterSheet({
    super.key,
    this.currentSourceId,
    required this.onSourceSelected,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentSourceId,
    required ValueChanged<String> onSourceSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SourceFilterSheet(
        currentSourceId: currentSourceId,
        onSourceSelected: onSourceSelected,
      ),
    );
  }

  @override
  ConsumerState<SourceFilterSheet> createState() => _SourceFilterSheetState();
}

class _SourceFilterSheetState extends ConsumerState<SourceFilterSheet> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Source> _getFilteredSources(List<Source> allSources) {
    final followed = allSources
        .where((s) => (s.isTrusted || s.isCustom) && !s.isMuted)
        .toList();

    if (_searchQuery.isEmpty) {
      followed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return followed;
    }

    final query = _searchQuery.toLowerCase();
    final filtered = followed
        .where((s) => s.name.toLowerCase().contains(query))
        .toList();
    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filtrer par source',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher...',
                  hintStyle: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                    color: colors.textTertiary,
                    size: 20,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            PhosphorIcons.x(PhosphorIconsStyle.regular),
                            color: colors.textTertiary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Source list
            Flexible(
              child: sourcesAsync.when(
                data: (allSources) {
                  final sources = _getFilteredSources(allSources);

                  if (sources.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'Aucune source trouvée'
                            : 'Aucune source suivie',
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    shrinkWrap: true,
                    itemCount: sources.length,
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      final isSelected = source.id == widget.currentSourceId;

                      return _SourceItem(
                        source: source,
                        isSelected: isSelected,
                        colors: colors,
                        onTap: () {
                          widget.onSourceSelected(source.id);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Erreur de chargement',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceItem extends StatelessWidget {
  final Source source;
  final bool isSelected;
  final FacteurColors colors;
  final VoidCallback onTap;

  const _SourceItem({
    required this.source,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            // Logo
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                  ? FacteurImage(
                      imageUrl: source.logoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context) => Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                        color: colors.textTertiary,
                        size: 16,
                      ),
                      errorWidget: (context) => Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                        color: colors.textTertiary,
                        size: 16,
                      ),
                    )
                  : Icon(
                      PhosphorIcons.newspaper(PhosphorIconsStyle.fill),
                      color: colors.textTertiary,
                      size: 16,
                    ),
            ),
            const SizedBox(width: 12),

            // Name
            Expanded(
              child: Text(
                source.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Check mark
            if (isSelected)
              Icon(
                PhosphorIcons.check(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
