import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/collection_model.dart';
import '../providers/collections_provider.dart';

/// Bottom sheet pour ajouter un article à des collections.
class CollectionPickerSheet extends ConsumerStatefulWidget {
  final String contentId;

  const CollectionPickerSheet({super.key, required this.contentId});

  /// Ouvre le picker en bottom sheet.
  static Future<void> show(BuildContext context, String contentId) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CollectionPickerSheet(contentId: contentId),
    );
  }

  @override
  ConsumerState<CollectionPickerSheet> createState() =>
      _CollectionPickerSheetState();
}

class _CollectionPickerSheetState
    extends ConsumerState<CollectionPickerSheet> {
  final Set<String> _selectedIds = {};
  bool _isCreating = false;
  final _createController = TextEditingController();
  final _createFocus = FocusNode();

  @override
  void dispose() {
    _createController.dispose();
    _createFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final collectionsAsync = ref.watch(collectionsProvider);

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Text(
              'Ajouter à une collection',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),

            // New collection button / inline input
            if (_isCreating)
              _buildCreateInput(colors)
            else
              _buildCreateButton(colors),
            const SizedBox(height: 8),

            // Divider
            Divider(color: colors.border.withValues(alpha: 0.3)),

            // Collections list
            collectionsAsync.when(
              data: (collections) =>
                  _buildCollectionsList(collections, colors),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur de chargement',
                    style: TextStyle(color: colors.textSecondary)),
              ),
            ),

            // Confirm button
            if (_selectedIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Confirmer (${_selectedIds.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton(FacteurColors colors) {
    return GestureDetector(
      onTap: () => setState(() => _isCreating = true),
      child: Row(
        children: [
          Icon(PhosphorIcons.plus(PhosphorIconsStyle.regular),
              color: colors.primary, size: 20),
          const SizedBox(width: 12),
          Text(
            'Nouvelle collection',
            style: TextStyle(
              color: colors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateInput(FacteurColors colors) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _createController,
            focusNode: _createFocus,
            autofocus: true,
            maxLength: 100,
            style: TextStyle(color: colors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Nom de la collection',
              hintStyle: TextStyle(color: colors.textTertiary),
              counterText: '',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            onSubmitted: (_) => _createAndSelect(),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _createAndSelect,
          child: Text('Créer', style: TextStyle(color: colors.primary)),
        ),
        IconButton(
          onPressed: () => setState(() {
            _isCreating = false;
            _createController.clear();
          }),
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular),
              size: 18, color: colors.textTertiary),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildCollectionsList(
      List<Collection> collections, FacteurColors colors) {
    if (collections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Aucune collection',
            style: TextStyle(color: colors.textTertiary, fontSize: 14),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final col = collections[index];
          final isSelected = _selectedIds.contains(col.id);

          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(col.id);
                } else {
                  _selectedIds.add(col.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  // Checkbox
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? colors.primary
                            : colors.textTertiary,
                        width: isSelected ? 2 : 1.5,
                      ),
                      color: isSelected
                          ? colors.primary
                          : Colors.transparent,
                    ),
                    child: isSelected
                        ? Icon(
                            PhosphorIcons.check(PhosphorIconsStyle.bold),
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  // Name + count
                  Expanded(
                    child: Text(
                      col.name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    '${col.itemCount}',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createAndSelect() async {
    final name = _createController.text.trim();
    if (name.isEmpty) return;

    try {
      final collection = await ref
          .read(collectionsProvider.notifier)
          .createCollection(name);
      setState(() {
        _isCreating = false;
        _createController.clear();
        _selectedIds.add(collection.id);
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      // Handle error (e.g., duplicate name)
    }
  }

  Future<void> _confirm() async {
    if (_selectedIds.isEmpty) return;

    final repo = ref.read(collectionsRepositoryProvider);
    for (final collectionId in _selectedIds) {
      await repo.addToCollection(collectionId, widget.contentId);
    }

    // Refresh collections to update counts
    ref.invalidate(collectionsProvider);

    if (mounted) Navigator.pop(context);
    HapticFeedback.mediumImpact();
  }
}
