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

  /// Top 3 macro-theme emojis, deduplicated by macro-theme,
  /// sorted by highest priorityMultiplier in each group.
  List<String> get _topEmojis {
    // Group by macro-theme, keep best priorityMultiplier per group
    final macroThemeBest = <String, double>{};
    for (final topic in followedTopics) {
      final macro = getTopicMacroTheme(topic.slugParent ?? '');
      if (macro == null) continue;
      final current = macroThemeBest[macro] ?? 0.0;
      if (topic.priorityMultiplier > current) {
        macroThemeBest[macro] = topic.priorityMultiplier;
      }
    }

    // Sort by priorityMultiplier desc
    final sorted = macroThemeBest.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(3)
        .map((e) => getMacroThemeEmoji(e.key))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int get _totalFollowedThemes {
    final macros = <String>{};
    for (final topic in followedTopics) {
      final macro = getTopicMacroTheme(topic.slugParent ?? '');
      if (macro != null) macros.add(macro);
    }
    return macros.length;
  }

  /// Emoji for the currently selected filter.
  String get _activeEmoji {
    if (selectedIsTheme && selectedSlug != null) {
      // Theme slug → find the macro-theme label via macroThemeToApiSlug reverse
      final macroLabel = macroThemeToApiSlug.entries
          .where((e) => e.value == selectedSlug)
          .firstOrNull
          ?.key;
      if (macroLabel != null) return getMacroThemeEmoji(macroLabel);
    }
    if (selectedSlug != null) {
      final macro = getTopicMacroTheme(selectedSlug!);
      if (macro != null) return getMacroThemeEmoji(macro);
    }
    return '';
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
              emoji: _activeEmoji,
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
              emojis: _topEmojis,
              remainingCount:
                  _totalFollowedThemes > 3 ? _totalFollowedThemes - 3 : 0,
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
  final List<String> emojis;
  final int remainingCount;
  final VoidCallback onTap;

  const _InactiveChip({
    super.key,
    required this.emojis,
    required this.remainingCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = colorScheme.onSurface.withValues(alpha: 0.5);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

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
            if (emojis.isEmpty) ...[
              Text(
                'Thèmes',
                style: TextStyle(
                    fontSize: 12, color: muted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 2),
            ] else ...[
              Opacity(
                opacity: 0.65,
                child: Text(
                  emojis.join(''),
                  style: const TextStyle(fontSize: 14, letterSpacing: 1),
                ),
              ),
              const SizedBox(width: 4),
              if (remainingCount > 0) ...[
                Text(
                  '+$remainingCount',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                const SizedBox(width: 2),
              ],
            ],
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
  final String emoji;
  final String name;
  final VoidCallback onClear;
  final VoidCallback onTap;

  const _ActiveChip({
    super.key,
    required this.emoji,
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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: primary.withValues(alpha: 0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty)
              Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: primary,
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
