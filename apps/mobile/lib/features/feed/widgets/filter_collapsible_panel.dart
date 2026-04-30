import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// "Filtrer" button + inline expand panel.
///
/// Collapsed: a pill button labelled "Filtres" (with active count when ≥1
/// filter is set). Expanded: the [chipsRow] is rendered below the button
/// using AnimatedSize.
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: hasActive
                    ? colors.primary.withOpacity(0.12)
                    : Colors.transparent,
                border: hasActive
                    ? Border.all(color: colors.primary)
                    : null,
                borderRadius: BorderRadius.circular(FacteurRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.funnel(PhosphorIconsStyle.regular),
                    size: 14,
                    color: hasActive ? colors.primary : colors.textSecondary,
                  ),
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
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                      size: 11,
                      color: hasActive
                          ? colors.primary
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: widget.chipsRow,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
