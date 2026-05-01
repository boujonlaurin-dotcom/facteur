import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
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
              remainingCount: followedSources.length - _topSources.length,
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
  final VoidCallback onTap;
  final List<Source> topSources;
  final int remainingCount;

  const _InactiveChip({
    super.key,
    required this.onTap,
    required this.topSources,
    required this.remainingCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FacteurRadius.full),
          color: colors.surface,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Mes sources',
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
              size: 10,
              color: colors.textSecondary,
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
    final colors = context.facteurColors;
    final primary = colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FacteurRadius.full),
          color: primary.withOpacity(0.12),
          border: Border.all(color: primary),
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
