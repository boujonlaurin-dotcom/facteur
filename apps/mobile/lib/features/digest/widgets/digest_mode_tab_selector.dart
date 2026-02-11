import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/digest_mode.dart';

/// Sélecteur segmenté premium pour les 3 modes du digest.
///
/// Un vrai segmented control avec un indicateur animé qui glisse
/// d'un onglet à l'autre. Fond semi-transparent, mode sélectionné
/// mis en évidence avec couleur, bordure lumineuse et ombre.
/// Icônes only — le label en dessous fournit le contexte.
class DigestModeSegmentedControl extends StatelessWidget {
  final DigestMode selectedMode;
  final ValueChanged<DigestMode> onModeChanged;
  final bool isRegenerating;

  const DigestModeSegmentedControl({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.isRegenerating = false,
  });

  @override
  Widget build(BuildContext context) {
    final selectedIndex = DigestMode.values.indexOf(selectedMode);
    final modeColor = selectedMode.effectiveColor(const Color(0xFFC0392B));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Taille de chaque segment : la largeur totale divisée en 3
        final totalWidth = constraints.maxWidth;
        final segmentWidth = totalWidth / DigestMode.values.length;

        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              // Indicateur animé (slider) qui glisse entre les segments
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: selectedIndex * segmentWidth + 3,
                top: 3,
                bottom: 3,
                width: segmentWidth - 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: modeColor.withValues(alpha: 0.45),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: modeColor.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                ),
              ),
              // Les segments (icônes) par-dessus
              Row(
                children: DigestMode.values.map((mode) {
                  final isSelected = mode == selectedMode;

                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: isRegenerating
                          ? null
                          : () {
                              if (mode != selectedMode) {
                                HapticFeedback.lightImpact();
                                onModeChanged(mode);
                              }
                            },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(fontSize: isSelected ? 20 : 18),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: isSelected ? 1.0 : 0.45,
                            child: Icon(
                              mode.icon,
                              size: isSelected ? 22 : 19,
                              color: isSelected
                                  ? mode.effectiveColor(
                                      const Color(0xFFC0392B))
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
