import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../widgets/design/facteur_image.dart';
import '../../sources/models/source_model.dart';
import 'source_filter_sheet.dart';

/// Compact pill chip showing an avatar stack of top 3 followed sources.
///
/// Inactive: [logo1 logo2 logo3] +N ▾
/// Active:   [logo] SourceName ✕
class CompactSourceChip extends StatelessWidget {
  final List<Source> followedSources;
  final String? selectedSourceId;
  final String? selectedSourceName;
  final String? selectedSourceLogoUrl;
  final ValueChanged<String?> onSourceChanged;

  const CompactSourceChip({
    super.key,
    required this.followedSources,
    this.selectedSourceId,
    this.selectedSourceName,
    this.selectedSourceLogoUrl,
    required this.onSourceChanged,
  });

  bool get _isActive => selectedSourceId != null;

  /// Top 3 favorites sorted: real logo first, then hasSubscription, then priorityMultiplier desc.
  List<Source> get _topSources {
    final sorted = [...followedSources];
    sorted.sort((a, b) {
      // 1. Prefer sources with a real logo image
      final aHasLogo = a.logoUrl != null && a.logoUrl!.isNotEmpty;
      final bHasLogo = b.logoUrl != null && b.logoUrl!.isNotEmpty;
      if (aHasLogo != bHasLogo) return bHasLogo ? 1 : -1;
      // 2. Then hasSubscription
      if (a.hasSubscription != b.hasSubscription) {
        return b.hasSubscription ? 1 : -1;
      }
      // 3. Then priorityMultiplier desc
      return b.priorityMultiplier.compareTo(a.priorityMultiplier);
    });
    return sorted.take(3).toList();
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
              key: ValueKey('source_active_$selectedSourceId'),
              sourceLogoUrl: selectedSourceLogoUrl,
              sourceName: selectedSourceName ?? 'Source',
              onClear: () {
                HapticFeedback.mediumImpact();
                onSourceChanged(null);
              },
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            )
          : _InactiveChip(
              key: const ValueKey('source_inactive'),
              topSources: _topSources,
              remainingCount: followedSources.length > 3
                  ? followedSources.length - 3
                  : 0,
              onTap: () {
                HapticFeedback.mediumImpact();
                _openSheet(context);
              },
            ),
    );
  }

  void _openSheet(BuildContext context) {
    SourceFilterSheet.show(
      context,
      currentSourceId: selectedSourceId,
      onSourceSelected: (sourceId) => onSourceChanged(sourceId),
    );
  }
}

class _InactiveChip extends StatelessWidget {
  final List<Source> topSources;
  final int remainingCount;
  final VoidCallback onTap;

  const _InactiveChip({
    super.key,
    required this.topSources,
    required this.remainingCount,
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
            if (topSources.isEmpty) ...[
              Text(
                'Sources',
                style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 2),
            ] else ...[
              // Avatar stack — overlap adapts to screen width
              Builder(builder: (context) {
                final screenW = MediaQuery.of(context).size.width;
                // step ranges from 13 (small, ~320px) to 16 (large, ≥430px)
                final step = (screenW / 35).clamp(13.0, 16.0);
                final stackW = 18.0 + (topSources.length - 1) * step;
                return Opacity(
                  opacity: 0.65,
                  child: SizedBox(
                    width: stackW,
                    height: 18,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (int i = 0; i < topSources.length; i++)
                          Positioned(
                            left: i * step,
                            child: _SourceAvatar(
                              source: topSources[i],
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(width: 6),
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
  final String? sourceLogoUrl;
  final String sourceName;
  final VoidCallback onClear;
  final VoidCallback onTap;

  const _ActiveChip({
    super.key,
    this.sourceLogoUrl,
    required this.sourceName,
    required this.onClear,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: primary.withOpacity(0.12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sourceLogoUrl != null && sourceLogoUrl!.isNotEmpty)
              _SourceAvatar(
                logoUrl: sourceLogoUrl!,
                size: 18,
              ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                sourceName,
                style: TextStyle(
                  fontSize: 13,
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

/// Circular avatar with white border for stack separation.
class _SourceAvatar extends StatelessWidget {
  final Source? source;
  final String? logoUrl;
  final double size;

  const _SourceAvatar({
    this.source,
    this.logoUrl,
    required this.size,
  });

  String get _url => logoUrl ?? source?.logoUrl ?? '';
  String get _initial => source?.name.isNotEmpty == true ? source!.name[0] : '?';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        color: colorScheme.surfaceContainerHighest,
      ),
      child: ClipOval(
        child: _url.isNotEmpty
            ? FacteurImage(
                imageUrl: _url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_) => _placeholder(colorScheme),
              )
            : _placeholder(colorScheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
    );
  }
}
