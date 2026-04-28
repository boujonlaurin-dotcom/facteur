import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../core/api/notification_preferences_api_service.dart';

/// Sélecteur de préset (Minimaliste / Curieux) — partagé modal d'activation
/// + écran Profil > Notifications.
class PresetSelector extends StatelessWidget {
  final NotifPreset value;
  final ValueChanged<NotifPreset> onChanged;

  const PresetSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PresetTile(
          icon: '🌱',
          label: 'Minimaliste',
          tagline: "L'essentiel, une fois par jour.",
          description: "Un message quotidien. Jamais plus !",
          selected: value == NotifPreset.minimaliste,
          onTap: () => onChanged(NotifPreset.minimaliste),
        ),
        const SizedBox(height: FacteurSpacing.space3),
        _PresetTile(
          icon: '🔭',
          label: 'Curieux',
          tagline: "L'essentiel & des recos de pépites.",
          description:
              "Message quotidien + 1 pépite recommandée par les Fact·eur·isses.",
          selected: value == NotifPreset.curieux,
          onTap: () => onChanged(NotifPreset.curieux),
        ),
      ],
    );
  }
}

class _PresetTile extends StatelessWidget {
  final String icon;
  final String label;
  final String tagline;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.icon,
    required this.label,
    required this.tagline,
    required this.description,
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
          padding: const EdgeInsets.all(FacteurSpacing.space4),
          decoration: BoxDecoration(
            color: selected ? colors.primary.withOpacity(0.08) : colors.surface,
            border: Border.all(
              color: selected ? colors.primary : colors.surfaceElevated,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tagline,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Radio<bool>(
                value: true,
                groupValue: selected,
                onChanged: (_) => onTap(),
                activeColor: colors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
