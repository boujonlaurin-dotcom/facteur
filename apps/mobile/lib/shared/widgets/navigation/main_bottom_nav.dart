import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Bottom nav persistante des deux onglets principaux (Essentiel / Flâner).
///
/// Posée dans le shell partagé (`MainShell`) — elle ne navigue pas elle-même :
/// elle remonte les taps via [onSelect] et c'est le shell qui décide (changement
/// d'onglet vs scroll-to-top sur re-tap de l'onglet actif).
///
/// Style « point » historique de l'app (repris de `sticky_tab_bar.dart` `_Tab`)
/// posé sur une surface glassmorphique premium : coins supérieurs arrondis, flou
/// qui laisse transparaître le contenu défilant derrière, hairline + ombre douce.
class MainBottomNav extends StatelessWidget {
  /// Index de l'onglet actif (0 = L'Essentiel, 1 = Flâner).
  final int currentIndex;

  /// Appelé au tap d'un onglet (actif ou non). Le shell arbitre la suite.
  final ValueChanged<int> onSelect;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  static const BorderRadius _topRadius = BorderRadius.vertical(
    top: Radius.circular(20),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final fillColor = isDark
        ? context.facteurColors.backgroundPrimary.withValues(alpha: 0.80)
        : const Color.fromRGBO(242, 232, 213, 0.86);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color.fromRGBO(0, 0, 0, 0.08);

    return DecoratedBox(
      // Ombre douce projetée vers le haut pour décoller la barre du contenu.
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _topRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: _topRadius,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 50,
                child: Row(
                  children: [
                    Expanded(
                      child: _FooterTab(
                        label: 'L’Essentiel',
                        selected: currentIndex == 0,
                        onTap: () => onSelect(0),
                      ),
                    ),
                    Expanded(
                      child: _FooterTab(
                        label: 'Flâner',
                        selected: currentIndex == 1,
                        onTap: () => onSelect(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FooterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colors.primary : Colors.transparent,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? colors.primary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
