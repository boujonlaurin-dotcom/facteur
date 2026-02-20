import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/saved_summary_provider.dart';

/// Clé pour persister le dismiss du nudge (24h cooldown).
const _dismissKey = 'saved_nudge_dismissed_at';

/// Provider qui vérifie si le nudge a été dismiss récemment (< 24h).
final savedNudgeDismissedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final dismissedAt = prefs.getInt(_dismissKey);
  if (dismissedAt == null) return false;
  final elapsed =
      DateTime.now().millisecondsSinceEpoch - dismissedAt;
  return elapsed < const Duration(hours: 24).inMilliseconds;
});

/// Nudge contextuel "articles sauvegardés non lus" affiché dans le feed.
///
/// Suit le pattern de [PersonalizationNudge] (même structure Container + icon + texte + CTA).
class SavedNudge extends ConsumerWidget {
  /// Message contextuel à afficher (ex: "Tu as 5 articles sauvegardés non lus").
  final String message;

  const SavedNudge({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.duotone),
                color: colors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vos sauvegardes',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _dismiss(ref),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.regular),
                    size: 18,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  _dismiss(ref);
                  context.go(RoutePaths.saved);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary.withValues(alpha: 0.1),
                  foregroundColor: colors.primary,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Voir mes sauvegardes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dismissKey, DateTime.now().millisecondsSinceEpoch);
    ref.invalidate(savedNudgeDismissedProvider);
    ref.invalidate(savedSummaryProvider);
  }
}
