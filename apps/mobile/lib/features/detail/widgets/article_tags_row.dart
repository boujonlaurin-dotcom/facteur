import 'package:flutter/material.dart';

import '../../../config/theme.dart';

class ArticleTagItem {
  const ArticleTagItem({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

class ArticleTagsRow extends StatelessWidget {
  const ArticleTagsRow({
    super.key,
    required this.items,
    required this.onOverflowTap,
  });

  final List<ArticleTagItem> items;
  final VoidCallback onOverflowTap;

  double _measureChipWidth(String text, TextStyle? style) {
    const horizontalPadding = 16.0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width + horizontalPadding;
  }

  int _visibleCount(List<double> widths, double availableWidth) {
    const spacing = 6.0;
    var usedWidth = 0.0;
    var count = 0;
    for (final width in widths) {
      final nextWidth = count == 0 ? width : usedWidth + spacing + width;
      if (nextWidth > availableWidth) break;
      usedWidth = nextWidth;
      count++;
    }
    return count;
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = context.facteurColors;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.textTertiary,
          fontWeight: FontWeight.w500,
        );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: style, maxLines: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final labelStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = items
            .map((item) => _measureChipWidth(item.label, labelStyle))
            .toList();
        var visibleCount = _visibleCount(widths, constraints.maxWidth);
        final total = items.length;

        if (visibleCount < total) {
          final overflowWidth = _measureChipWidth('+$total sujets', labelStyle);
          while (visibleCount > 0) {
            final candidateWidths = [
              ...widths.take(visibleCount),
              overflowWidth,
            ];
            if (_visibleCount(candidateWidths, constraints.maxWidth) ==
                candidateWidths.length) {
              break;
            }
            visibleCount--;
          }
        }

        final overflow = total - visibleCount;
        final overflowLabel = overflow == 1 ? '+1 sujet' : '+$overflow sujets';

        final visibleItems = items.take(visibleCount).toList();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < visibleItems.length; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              _chip(
                context,
                label: visibleItems[index].label,
                onTap: visibleItems[index].onTap,
              ),
            ],
            if (overflow > 0) ...[
              if (visibleItems.isNotEmpty) const SizedBox(width: 6),
              _chip(
                context,
                label: overflowLabel,
                onTap: onOverflowTap,
              ),
            ],
          ],
        );
      },
    );
  }
}
