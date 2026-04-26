import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Tooltip léger affiché dans la colonne FAB de l'article, à côté du bouton
/// Sauvegarder. Remplace l'ancien `NoteWelcomeTooltip`.
///
/// Style compact (pas un full-banner) parce qu'il vit dans une colonne de FABs
/// étroite. Animation fade+slide à l'apparition, fade au dismiss.
class ArticleSaveNotesTooltip extends StatefulWidget {
  const ArticleSaveNotesTooltip({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<ArticleSaveNotesTooltip> createState() =>
      _ArticleSaveNotesTooltipState();
}

class _ArticleSaveNotesTooltipState extends State<ArticleSaveNotesTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return GestureDetector(
      onTap: _dismiss,
      behavior: HitTestBehavior.opaque,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: FacteurSpacing.space2,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Sauvegardez cet article et ajoutez-y des notes personnelles.',
                    style: FacteurTypography.bodyMedium(colors.textPrimary),
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
