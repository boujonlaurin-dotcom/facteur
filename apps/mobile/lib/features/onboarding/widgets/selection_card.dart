import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';

/// Carte de sélection pour les questions de l'onboarding
/// States: Default, Selected, Pressed
class SelectionCard extends StatefulWidget {
  final String label;
  final String? emoji;
  final bool isSelected;
  final VoidCallback onTap;
  final String? subtitle;

  const SelectionCard({
    super.key,
    required this.label,
    this.emoji,
    this.isSelected = false,
    required this.onTap,
    this.subtitle,
  });

  @override
  State<SelectionCard> createState() => _SelectionCardState();
}

class _SelectionCardState extends State<SelectionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  void _handleTap() {
    // Feedback haptic
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
                border: Border.all(
                  color:
                      widget.isSelected ? colors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  // Emoji
                  if (widget.emoji != null) ...[
                    Text(
                      widget.emoji!,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: FacteurSpacing.space3),
                  ],

                  // Contenu texte
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: widget.isSelected
                                        ? colors.textPrimary
                                        : colors.textPrimary,
                                  ),
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: FacteurSpacing.space1),
                          Text(
                            widget.subtitle!,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Indicateur de sélection
                  if (widget.isSelected)
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    )
                  else
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colors.textTertiary,
                          width: 2,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Carte de sélection binaire (2 options côte à côte)
class BinarySelectionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const BinarySelectionCard({
    super.key,
    required this.emoji,
    required this.label,
    this.subtitle,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color: isSelected ? colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: FacteurSpacing.space1),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
