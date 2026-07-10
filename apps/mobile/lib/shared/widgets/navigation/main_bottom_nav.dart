import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Bottom nav persistante des deux onglets principaux (Essentiel / Flâner).
///
/// Posée dans le chrome partagé des pages racines — elle ne navigue pas
/// elle-même : elle remonte les taps via [onSelect] et le parent décide
/// (changement d'onglet vs scroll-to-top sur re-tap de l'onglet actif).
///
/// Style « point » historique de l'app (repris de `sticky_tab_bar.dart` `_Tab`)
/// posé sur une surface glassmorphique premium : coins supérieurs arrondis, flou
/// qui laisse transparaître le contenu défilant derrière, hairline + ombre douce.
class MainBottomNav extends StatelessWidget {
  /// Index de l'onglet actif (0 = L'Essentiel, 1 = Flâner).
  final int currentIndex;

  /// Appelé au tap d'un onglet (actif ou non). Le parent arbitre la suite.
  final ValueChanged<int> onSelect;

  /// Ancre optionnelle du tour guidé posée sur l'onglet « L'Essentiel ».
  final GlobalKey? essentielTabAnchorKey;

  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.essentielTabAnchorKey,
  });

  static const BorderRadius _topRadius = BorderRadius.vertical(
    top: Radius.circular(20),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    // Sur le web (CanvasKit), le footer est animé par un AnimatedSlide au scroll
    // (cf. main_shell.dart). Animer un widget qui contient un BackdropFilter force
    // une re-rasterisation du flou à chaque frame → animation saccadée. On rend
    // donc le fond quasi-opaque et on retire le blur sur web ; le natif garde le
    // glassmorphisme (coût absorbé par Skia/Impeller).
    final fillColor = isDark
        ? context.facteurColors.backgroundPrimary
            .withValues(alpha: kIsWeb ? 0.97 : 0.80)
        : const Color.fromRGBO(242, 232, 213, kIsWeb ? 0.98 : 0.86);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color.fromRGBO(0, 0, 0, 0.08);

    final content = Container(
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
                child: KeyedSubtree(
                  key: essentielTabAnchorKey,
                  child: _FooterTab(
                    label: 'L’Essentiel',
                    selected: currentIndex == 0,
                    onTap: () => onSelect(0),
                  ),
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
    );

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
        // Web : pas de BackdropFilter (fond quasi-opaque) pour un slide fluide.
        child: kIsWeb
            ? content
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: content,
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
