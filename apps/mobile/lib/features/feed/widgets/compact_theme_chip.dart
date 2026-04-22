import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import 'interest_filter_sheet.dart';

/// Compact pill chip showing emojis of top 3 followed macro-themes.
///
/// Inactive: 🔬🌍💰 +N ▾
/// Active:   🔬 ThemeName ✕
class CompactThemeChip extends StatelessWidget {
  final List<UserTopicProfile> followedTopics;
  final String? selectedSlug;
  final String? selectedName;
  final bool selectedIsTheme;
  final void Function(String? slug, String? name,
      {bool isTheme, bool isEntity}) onInterestChanged;

  const CompactThemeChip({
    super.key,
    required this.followedTopics,
    this.selectedSlug,
    this.selectedName,
    this.selectedIsTheme = false,
    required this.onInterestChanged,
  });

  bool get _isActive => selectedSlug != null;

  int get _totalFollowedThemes {
    final macros = <String>{};
    for (final topic in followedTopics) {
      final macro = getTopicMacroTheme(topic.slugParent ?? '');
      if (macro != null) macros.add(macro);
    }
    return macros.length;
  }

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
              key: ValueKey('theme_active_$selectedSlug'),
              name: selectedName ?? 'Thème',
              onClear: () {
                HapticFeedback.mediumImpact();
                onInterestChanged(null, null,
                    isTheme: false, isEntity: false);
              },
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            )
          : _InactiveChip(
              key: const ValueKey('theme_inactive'),
              totalCount: _totalFollowedThemes,
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            ),
    );
  }

  void _openSheet(BuildContext context) {
    InterestFilterSheet.show(
      context,
      currentTopicSlug: selectedSlug,
      currentIsTheme: selectedIsTheme,
      onInterestSelected: (slug, name, {bool isTheme = false, bool isEntity = false}) =>
          onInterestChanged(slug, name, isTheme: isTheme, isEntity: isEntity),
    );
  }
}

class _InactiveChip extends StatelessWidget {
  final int totalCount;
  final VoidCallback onTap;

  const _InactiveChip({
    super.key,
    required this.totalCount,
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: trackColor,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mes thèmes',
              style: TextStyle(
                  fontSize: 11, color: muted, fontWeight: FontWeight.w500),
            ),
            if (totalCount > 0) ...[
              const SizedBox(width: 4),
              Text(
                '· $totalCount',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
              size: 10,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  final String name;
  final VoidCallback onClear;
  final VoidCallback onTap;

  const _ActiveChip({
    super.key,
    required this.name,
    required this.onClear,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: primary.withOpacity(0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
