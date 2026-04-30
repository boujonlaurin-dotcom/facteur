import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Filter row with the trigger button on the RIGHT.
///
/// - Collapsed + no active filter: "Flux continu" label + thin grey rule fills
///   the left side ; "Filtres" pill sits on the right.
/// - Collapsed + active filter(s): empty space on the left ; pill shows count.
/// - Expanded: pills slide in to the left ; the trigger morphs into a pill of
///   the same shape with an × icon (primary, "selected" look).
class FilterCollapsiblePanel extends StatefulWidget {
  final int activeCount;
  final Widget chipsRow;

  const FilterCollapsiblePanel({
    super.key,
    required this.activeCount,
    required this.chipsRow,
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
    final label = hasActive ? 'Filtres · ${widget.activeCount}' : 'Filtres';

    return SizedBox(
      height: 32,
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
                  : (hasActive
                      ? const SizedBox.shrink(key: ValueKey('idle'))
                      : Padding(
                          key: const ValueKey('flux-continu'),
                          padding: const EdgeInsets.only(right: 12),
                          child: Row(
                            children: [
                              Text(
                                'Flux continu',
                                style: FacteurTypography.stamp(
                                        colors.textTertiary)
                                    .copyWith(letterSpacing: 1.2),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: colors.border.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        )),
            ),
          ),
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: (_expanded || hasActive)
                    ? colors.primary.withOpacity(0.12)
                    : Colors.transparent,
                border: (_expanded || hasActive)
                    ? Border.all(color: colors.primary)
                    : null,
                borderRadius: BorderRadius.circular(FacteurRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded
                        ? PhosphorIcons.x(PhosphorIconsStyle.bold)
                        : PhosphorIcons.funnel(PhosphorIconsStyle.regular),
                    size: 14,
                    color: (_expanded || hasActive)
                        ? colors.primary
                        : colors.textSecondary,
                  ),
                  if (!_expanded) ...[
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasActive
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
