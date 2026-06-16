import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Filter row with an expandable chips area.
///
/// - Collapsed: [collapsedContentBuilder] fills the left side and is handed the
///   filter trigger so callers can place it inside that content (e.g. as the
///   last scrollable item of favorite topic tabs). With no builder, a
///   "FLUX CONTINU" rule fills the space and the trigger sits on the right.
/// - Expanded: pills slide in to the left ; the trigger morphs into a pill of
///   the same shape with an × icon (primary, "selected" look).
class FilterCollapsiblePanel extends StatefulWidget {
  final int activeCount;
  final Widget chipsRow;
  final Widget? leadingTrigger;
  final Widget Function(Widget filterTrigger)? collapsedContentBuilder;

  const FilterCollapsiblePanel({
    super.key,
    required this.activeCount,
    required this.chipsRow,
    this.leadingTrigger,
    this.collapsedContentBuilder,
  });

  @override
  State<FilterCollapsiblePanel> createState() => _FilterCollapsiblePanelState();
}

class _FilterCollapsiblePanelState extends State<FilterCollapsiblePanel> {
  bool _expanded = false;

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasActive = widget.activeCount > 0;
    final filterTrigger = _FilterTriggerButton(
      expanded: _expanded,
      activeCount: widget.activeCount,
      onTap: _toggle,
    );
    final collapsedContent = widget.collapsedContentBuilder;

    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: _expanded
                  ? Padding(
                      key: const ValueKey('chips'),
                      padding: const EdgeInsets.only(right: 8),
                      child: widget.chipsRow,
                    )
                  : (collapsedContent != null
                      ? KeyedSubtree(
                          key: const ValueKey('collapsed-builder'),
                          child: collapsedContent(filterTrigger),
                        )
                      : (hasActive
                          ? const SizedBox.shrink(key: ValueKey('idle'))
                          : Padding(
                              key: const ValueKey('flux-continu'),
                              padding: const EdgeInsets.only(right: 12),
                              child: Row(
                                children: [
                                  Text(
                                    'FLUX CONTINU',
                                    style: FacteurTypography.stamp(
                                            colors.textTertiary)
                                        .copyWith(letterSpacing: 1.2),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: colors.border
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ))),
            ),
          ),
          if (collapsedContent != null && !_expanded)
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: colors.border.withValues(alpha: 0.6),
            ),
          if (widget.leadingTrigger != null) ...[
            widget.leadingTrigger!,
            const SizedBox(width: 4),
          ],
          if (_expanded || collapsedContent == null) filterTrigger,
        ],
      ),
    );
  }
}

class _FilterTriggerButton extends StatelessWidget {
  final bool expanded;
  final int activeCount;
  final VoidCallback onTap;

  const _FilterTriggerButton({
    required this.expanded,
    required this.activeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasActive = activeCount > 0;
    final selected = expanded || hasActive;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 34,
        padding: EdgeInsets.symmetric(
          horizontal: hasActive && !expanded ? 12 : 9,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          border: selected ? Border.all(color: colors.primary) : null,
          borderRadius: BorderRadius.circular(FacteurRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded
                  ? PhosphorIcons.x(PhosphorIconsStyle.bold)
                  : PhosphorIcons.funnel(PhosphorIconsStyle.regular),
              size: 16,
              color: selected ? colors.primary : colors.textSecondary,
            ),
            if (!expanded && hasActive) ...[
              const SizedBox(width: 5),
              Text(
                '$activeCount',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
