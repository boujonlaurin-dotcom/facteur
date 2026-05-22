/// Story 22.1 — section « Favoris » réordonnable.
///
/// Cap retiré (Story 22.2) : l'utilisateur peut épingler autant de favoris
/// qu'il veut. Les `kFavoriteCap` (3) premiers items, par position, sont
/// matérialisés visuellement comme appartenant à la « Tournée du jour » via
/// un divider + caption au-dessus du (kFavoriteCap)-ième item.
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
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
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Les $kFavoriteCap premiers (ordre modifiable) sont dans votre Tournée du jour.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
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
                itemCount: items.length,
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final inTour = index < kFavoriteCap;
                  final isTourBoundary =
                      index == kFavoriteCap && items.length > kFavoriteCap;
                  return Column(
                    key: keyOf(item),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isTourBoundary)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            FacteurSpacing.space4,
                            FacteurSpacing.space2,
                            FacteurSpacing.space4,
                            FacteurSpacing.space1,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: colors.surfaceElevated,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Hors Tournée du jour',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.textTertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Divider(
                                  color: colors.surfaceElevated,
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space2,
                        ),
                        child: Opacity(
                          opacity: inTour ? 1.0 : 0.55,
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
                        ),
                      ),
                    ],
                  );
                },
                onReorder: (oldIndex, newIndex) {
                  final reordered = [...items];
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
