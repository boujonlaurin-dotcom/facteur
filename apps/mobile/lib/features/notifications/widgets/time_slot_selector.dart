import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../core/api/notification_preferences_api_service.dart';

/// Sélecteur d'horaire (Matin 07:30 / Soir 19:00) en *pills*.
class TimeSlotSelector extends StatelessWidget {
  final NotifTimeSlot value;
  final ValueChanged<NotifTimeSlot> onChanged;

  const TimeSlotSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Pill(
            icon: '☀️',
            label: 'Matin',
            sub: '07:30',
            selected: value == NotifTimeSlot.morning,
            onTap: () => onChanged(NotifTimeSlot.morning),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: _Pill(
            icon: '🌙',
            label: 'Soir',
            sub: '19:00',
            selected: value == NotifTimeSlot.evening,
            onTap: () => onChanged(NotifTimeSlot.evening),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String icon;
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.icon,
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: FacteurSpacing.space3,
            horizontal: FacteurSpacing.space4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withOpacity(0.10)
                : colors.surface,
            border: Border.all(
              color: selected ? colors.primary : colors.surfaceElevated,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
          ),
          child: Column(
            children: [
              Text('$icon $label',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
