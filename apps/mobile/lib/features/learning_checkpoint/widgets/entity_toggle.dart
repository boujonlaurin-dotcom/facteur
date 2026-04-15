import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

enum EntityToggleKind { mute, follow }

/// Toggle 2 états `🔕 Masquer` / `🔔 Suivre`.
/// Pré-actif par défaut. Tap désactive = équivalent à un `dismiss` individuel
/// (cf. spec format-visuel §Toggle).
class EntityToggle extends StatelessWidget {
  final EntityToggleKind kind;
  final bool preActive;
  final ValueChanged<bool> onChange;

  const EntityToggle({
    super.key,
    required this.kind,
    required this.preActive,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final icon = kind == EntityToggleKind.mute
        ? PhosphorIcons.bellSlash(PhosphorIconsStyle.regular)
        : PhosphorIcons.bell(PhosphorIconsStyle.regular);
    final label = kind == EntityToggleKind.mute ? 'Masquer' : 'Suivre';

    final bg = preActive ? colors.primary.withOpacity(0.1) : colors.surface;
    final fg = preActive ? colors.primary : colors.textTertiary;

    return Semantics(
      button: true,
      toggled: preActive,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InkWell(
          onTap: () => onChange(!preActive),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: fg.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 14),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
