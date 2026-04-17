import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'search_filter_sheet.dart';

/// Compact pill chip for search — matches CompactSourceChip / CompactThemeChip design.
///
/// Inactive: 🔍 (magnifying glass icon only)
/// Active:   🔍 keyword ✕
class CompactSearchChip extends StatelessWidget {
  final String? activeKeyword;
  final ValueChanged<String?> onSearchChanged;

  const CompactSearchChip({
    super.key,
    this.activeKeyword,
    required this.onSearchChanged,
  });

  bool get _isActive =>
      activeKeyword != null && activeKeyword!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: _isActive
          ? _ActiveChip(
              key: ValueKey('search_active_$activeKeyword'),
              keyword: activeKeyword!,
              onClear: () {
                HapticFeedback.mediumImpact();
                onSearchChanged(null);
              },
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            )
          : _InactiveChip(
              key: const ValueKey('search_inactive'),
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            ),
    );
  }

  void _openSheet(BuildContext context) {
    SearchFilterSheet.show(
      context,
      currentKeyword: activeKeyword,
      onSearchSubmitted: (keyword) => onSearchChanged(keyword),
    );
  }
}

class _InactiveChip extends StatelessWidget {
  final VoidCallback onTap;

  const _InactiveChip({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = colorScheme.onSurface.withOpacity(0.5);
    final trackColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.05);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: trackColor,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.65,
              child: Icon(
                PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                size: 16,
                color: muted,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Actus ↗',
              style: TextStyle(
                fontSize: 12,
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String keyword;
  final VoidCallback onClear;
  final VoidCallback onTap;

  const _ActiveChip({
    super.key,
    required this.keyword,
    required this.onClear,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: primary.withOpacity(0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                  size: 14,
                  color: primary,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    keyword,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClear,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
              child: Icon(
                PhosphorIcons.x(PhosphorIconsStyle.bold),
                size: 13,
                color: primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
