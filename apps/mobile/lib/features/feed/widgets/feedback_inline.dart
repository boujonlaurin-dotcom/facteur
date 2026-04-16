import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Terracotta accent — shared "removal" semantic with [SwipeToOpenCard].
const Color _terracotta = Color(0xFFE07A5F);

/// Compact inline banner that replaces a feed card after a left-swipe dismiss.
///
/// Renders ~80px tall with a neutral border and three chips asking the user
/// *why* they dismissed the article (construire ses préférences, pas juste
/// masquer) :
/// - "Moins voir cette source" → opens ArticleSheet on the source section
/// - "Moins voir ce thème" → opens ArticleSheet on the topic section
/// - "Déjà vu" → simply resolves the inline (no sheet)
///
/// An "Annuler" text button (to the right of the title) re-surfaces the card
/// (calls `unhideContent` + clears the pending feedback entry). A small X
/// button resolves silently without feedback.
///
/// All resolution logic (removing from feed state, opening sheets) lives in
/// the parent — this widget just fires callbacks.
class FeedbackInline extends StatefulWidget {
  final VoidCallback onSelectSource;
  final VoidCallback onSelectTopic;
  final VoidCallback onSelectAlreadySeen;
  final VoidCallback onUndo;
  final VoidCallback onClose;

  const FeedbackInline({
    super.key,
    required this.onSelectSource,
    required this.onSelectTopic,
    required this.onSelectAlreadySeen,
    required this.onUndo,
    required this.onClose,
  });

  @override
  State<FeedbackInline> createState() => _FeedbackInlineState();
}

class _FeedbackInlineState extends State<FeedbackInline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Semantics(
        container: true,
        label: 'Article masqué. Indiquez pourquoi pour affiner votre flux, '
            'ou annulez pour le faire réapparaître.',
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Améliore ton flux',
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onUndo();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.arrowCounterClockwise(
                                PhosphorIconsStyle.bold),
                            size: 13,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Annuler',
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onClose();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.bold),
                        size: 14,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    label: 'Moins voir cette source',
                    onTap: widget.onSelectSource,
                    colors: colors,
                    textTheme: textTheme,
                  ),
                  _Chip(
                    label: 'Moins voir ce thème',
                    onTap: widget.onSelectTopic,
                    colors: colors,
                    textTheme: textTheme,
                  ),
                  _Chip(
                    label: 'Déjà vu',
                    onTap: widget.onSelectAlreadySeen,
                    colors: colors,
                    textTheme: textTheme,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final FacteurColors colors;
  final TextTheme textTheme;

  const _Chip({
    required this.label,
    required this.onTap,
    required this.colors,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _terracotta.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
