import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'source_filter_sheet.dart';

class SourceFilterChip extends StatelessWidget {
  final String? selectedSourceId;
  final String? selectedSourceName;
  final ValueChanged<String?> onSourceChanged;

  const SourceFilterChip({
    super.key,
    this.selectedSourceId,
    this.selectedSourceName,
    required this.onSourceChanged,
  });

  bool get _isActive => selectedSourceId != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isActive) {
      return _buildActiveChip(context, colorScheme);
    }
    return _buildInactiveChip(context, colorScheme);
  }

  Widget _buildInactiveChip(BuildContext context, ColorScheme colorScheme) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Source',
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
            size: 12,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ],
      ),
      selected: false,
      onSelected: (_) => _openSheet(context),
      showCheckmark: false,
      backgroundColor: Colors.transparent,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  Widget _buildActiveChip(BuildContext context, ColorScheme colorScheme) {
    return InputChip(
      label: Text(
        selectedSourceName ?? 'Source',
        style: TextStyle(
          color: colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      selected: true,
      selectedColor: colorScheme.primary,
      showCheckmark: false,
      deleteIcon: Icon(
        PhosphorIcons.x(PhosphorIconsStyle.bold),
        size: 14,
        color: colorScheme.onPrimary,
      ),
      onDeleted: () => onSourceChanged(null),
      onPressed: () => _openSheet(context),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      visualDensity: VisualDensity.standard,
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
