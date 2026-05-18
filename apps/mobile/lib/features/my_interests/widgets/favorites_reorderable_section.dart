/// Story 22.1 — section « Favoris (n/3) » réordonnable.
///
/// Conçue pour fonctionner avec n'importe quel type d'item (intérêts ou sources)
/// via un builder. Cap d'affichage = 3 ; tout overflow est tronqué silencieusement
/// (la cap est imposée par le backend, ce widget reste défensif).
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/constants.dart';
import '../../../config/theme.dart';

class FavoritesReorderableSection<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final void Function(List<T> reordered) onReorder;
  final Key Function(T item) keyOf;
  final String emptyStateText;
  final EdgeInsetsGeometry padding;

  const FavoritesReorderableSection({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    required this.keyOf,
    this.emptyStateText =
        'Aucun favori — étoile un Thème ou un Sujet pour le retrouver ici.',
    this.padding = const EdgeInsets.symmetric(
      horizontal: FacteurSpacing.space4,
      vertical: FacteurSpacing.space2,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final clamped =
        items.length > kFavoriteCap ? items.sublist(0, kFavoriteCap) : items;

    return Padding(
      padding: padding,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.surfaceElevated),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FacteurSpacing.space4,
                FacteurSpacing.space3,
                FacteurSpacing.space4,
                FacteurSpacing.space1,
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.star(PhosphorIconsStyle.fill),
                    color: colors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Favoris',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${clamped.length}/$kFavoriteCap)',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (clamped.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space4,
                  FacteurSpacing.space2,
                  FacteurSpacing.space4,
                  FacteurSpacing.space3,
                ),
                child: Text(
                  emptyStateText,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: clamped.length,
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                itemBuilder: (context, index) {
                  final item = clamped[index];
                  return Padding(
                    key: keyOf(item),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space2,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: itemBuilder(context, item)),
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              PhosphorIcons.dotsSixVertical(
                                  PhosphorIconsStyle.regular),
                              color: colors.textTertiary,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  final reordered = [...clamped];
                  final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(adjusted, moved);
                  onReorder(reordered);
                },
              ),
          ],
        ),
      ),
    );
  }
}
