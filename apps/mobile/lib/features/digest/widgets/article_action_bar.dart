import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../repositories/digest_repository.dart';

/// Action bar with 3 buttons for digest card interactions
/// Read, Save, and Not Interested
class ArticleActionBar extends StatelessWidget {
  final DigestItem item;
  final ValueChanged<String> onAction;

  const ArticleActionBar({
    super.key,
    required this.item,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary.withValues(alpha: 0.5),
        border: Border(
          top: BorderSide(color: colors.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space2,
      ),
      child: Row(
        children: [
          // Read button
          Expanded(
            child: _ActionButton(
              icon: PhosphorIcons.check(),
              label: 'Lu',
              isActive: item.isRead,
              activeColor: colors.success,
              onTap: () => onAction('read'),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          // Save button
          Expanded(
            child: _ActionButton(
              icon: PhosphorIcons.bookmark(),
              label: 'Sauver',
              isActive: item.isSaved,
              activeColor: colors.primary,
              onTap: () => onAction('save'),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          // Not Interested button
          Expanded(
            child: _ActionButton(
              icon: PhosphorIcons.eyeSlash(),
              label: 'Pas pour moi',
              isActive: item.isDismissed,
              activeColor: colors.textSecondary,
              onTap: () => onAction('not_interested'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual action button with animated state changes
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? Colors.white : colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isActive ? Colors.white : colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
