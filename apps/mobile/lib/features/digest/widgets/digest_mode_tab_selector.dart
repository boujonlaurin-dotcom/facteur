import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/digest_mode.dart';

/// Compact iOS-style segmented control for the 3 digest modes.
///
/// Dark pill container with a lighter sliding indicator behind the
/// selected segment. Icons only. Designed to fit in the top-right
/// of the card header (~130×36px).
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

  static const double _width = 132;
  static const double _height = 36;
  static const double _padding = 3;
  static const int _count = 3; // DigestMode.values.length
  static const double _segmentWidth = (_width - _padding * 2) / _count;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = DigestMode.values.indexOf(selectedMode);
    final modeColor = selectedMode.effectiveColor(const Color(0xFFC0392B));

    // Le sélecteur est toujours sur fond sombre (carte digest always-dark)
    // → toujours utiliser les teintes blanches, sans brancher sur isDark.
    return SizedBox(
      width: _width,
      height: _height,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            // Sliding indicator
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: _padding + selectedIndex * _segmentWidth,
              top: _padding,
              bottom: _padding,
              width: _segmentWidth,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: modeColor.withValues(alpha: 0.30),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: modeColor.withValues(alpha: 0.15),
                      blurRadius: 8,
                      spreadRadius: -1,
                    ),
                  ],
                ),
              ),
            ),
            // Icon segments
            Row(
              children: [
                SizedBox(width: _padding),
                ...DigestMode.values.map((mode) {
                  final isSelected = mode == selectedMode;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isRegenerating
                        ? null
                        : () {
                            if (mode != selectedMode) {
                              HapticFeedback.lightImpact();
                              onModeChanged(mode);
                            }
                          },
                    child: SizedBox(
                      width: _segmentWidth,
                      height: _height,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            mode.icon,
                            key: ValueKey('${mode.key}_$isSelected'),
                            size: isSelected ? 19 : 17,
                            color: isSelected
                                ? mode.effectiveColor(const Color(0xFFC0392B))
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                SizedBox(width: _padding),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
