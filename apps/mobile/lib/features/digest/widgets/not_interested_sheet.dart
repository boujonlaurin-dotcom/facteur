import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';
import '../repositories/digest_repository.dart';

/// Bottom sheet for confirming not_interested action
/// Explains that the source will be muted
class NotInterestedSheet extends StatelessWidget {
  final DigestItem item;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const NotInterestedSheet({
    super.key,
    required this.item,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      padding: const EdgeInsets.only(
        top: 24,
        bottom: 40,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header icon
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.eyeSlash(PhosphorIconsStyle.bold),
                color: colors.textSecondary,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Masquer ce type de contenu ?',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            '${item.source.name} sera temporairement moins visible dans votre flux.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Source display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.backgroundPrimary,
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                // Source logo placeholder
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                  child: item.source.logoUrl != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.small),
                          child: Image.network(
                            item.source.logoUrl!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                PhosphorIcons.globe(),
                                color: colors.textTertiary,
                                size: 20,
                              );
                            },
                          ),
                        )
                      : Icon(
                          PhosphorIcons.globe(),
                          color: colors.textTertiary,
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.source.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.source.theme != null)
                        Text(
                          _getThemeLabel(item.source.theme!),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              // Cancel button
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    side: BorderSide(color: colors.border),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.small),
                    ),
                  ),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Confirm button
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FacteurRadius.small),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirmer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _getThemeLabel(String slug) {
    const translations = {
      'tech': 'Tech',
      'international': 'International',
      'science': 'Science',
      'culture': 'Culture',
      'politics': 'Politique',
      'society': 'Société',
      'environment': 'Environnement',
      'economy': 'Économie',
    };
    return translations[slug.toLowerCase()] ?? slug;
  }
}

/// Helper function to show the NotInterestedSheet
Future<bool> showNotInterestedSheet(
    BuildContext context, DigestItem item) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => NotInterestedSheet(
      item: item,
      onConfirm: () => Navigator.pop(context, true),
      onCancel: () => Navigator.pop(context, false),
    ),
  );

  return result ?? false;
}
