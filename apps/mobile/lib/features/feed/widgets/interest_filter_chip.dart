import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'interest_filter_sheet.dart';

class InterestFilterChip extends StatelessWidget {
  final String? selectedTopicSlug;
  final String? selectedTopicName;
  final bool selectedIsTheme;
  final void Function(String? slug, String? name, {bool isTheme, bool isEntity})
      onInterestChanged;

  const InterestFilterChip({
    super.key,
    this.selectedTopicSlug,
    this.selectedTopicName,
    this.selectedIsTheme = false,
    required this.onInterestChanged,
  });

  bool get _isActive => selectedTopicSlug != null;

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
            'Mes intérêts',
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
        selectedTopicName ?? 'Intérêt',
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
      onDeleted: () => onInterestChanged(null, null, isTheme: false, isEntity: false),
      onPressed: () => _openSheet(context),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  void _openSheet(BuildContext context) {
    InterestFilterSheet.show(
      context,
      currentTopicSlug: selectedTopicSlug,
      currentIsTheme: selectedIsTheme,
      onInterestSelected: (slug, name, {bool isTheme = false, bool isEntity = false}) =>
          onInterestChanged(slug, name, isTheme: isTheme, isEntity: isEntity),
    );
  }
}
