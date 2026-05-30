import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';

enum MainBottomNavDestination { essentiel, flaner }

/// Bottom nav persistante des deux onglets principaux (Essentiel / Flâner).
///
/// Style « point » historique de l'app (repris de `sticky_tab_bar.dart` `_Tab`)
/// posé sur une surface glassmorphique (reprise de `_ScrollToTopButton` dans
/// `flaner_screen.dart`) : aucune icône, juste un point orange sous l'onglet
/// actif et un label. Le flou laisse transparaître le contenu qui défile
/// derrière la barre.
class MainBottomNav extends StatelessWidget {
  final MainBottomNavDestination current;

  const MainBottomNav({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = context.isDarkMode;
    final fillColor = isDark
        ? colors.backgroundPrimary.withValues(alpha: 0.78)
        : const Color.fromRGBO(242, 232, 213, 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color.fromRGBO(0, 0, 0, 0.08);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: _FooterTab(
                      label: 'L’Essentiel',
                      selected:
                          current == MainBottomNavDestination.essentiel,
                      onTap: () => context.go(RoutePaths.fluxContinu),
                    ),
                  ),
                  Expanded(
                    child: _FooterTab(
                      label: 'Flâner',
                      selected: current == MainBottomNavDestination.flaner,
                      onTap: () => context.go(RoutePaths.flaner),
                    ),
                  ),
                ],
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
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colors.primary : Colors.transparent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 16,
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
