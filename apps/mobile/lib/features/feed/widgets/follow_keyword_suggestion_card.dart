import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';

/// Session-scoped set of search keywords (lowercased) the user has dismissed
/// the "follow as topic" suggestion for. Resets on app restart.
final dismissedFollowSuggestionsProvider =
    StateProvider<Set<String>>((_) => <String>{});

/// Subtle promo card shown below the feed header when a search keyword is
/// active, inviting the user to add it to their followed topics in 1 tap.
///
/// Hides itself automatically when:
/// - the keyword is empty / blank
/// - the keyword is already followed (case-insensitive name match)
/// - the user dismissed the suggestion for this keyword this session
class FollowKeywordSuggestionCard extends ConsumerWidget {
  final String keyword;

  const FollowKeywordSuggestionCard({super.key, required this.keyword});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final normalized = keyword.trim();
    if (normalized.isEmpty) return const SizedBox.shrink();

    final dismissed = ref.watch(dismissedFollowSuggestionsProvider);
    if (dismissed.contains(normalized.toLowerCase())) {
      return const SizedBox.shrink();
    }

    // Rebuild when followed topics list changes so the card disappears
    // right after a successful follow.
    ref.watch(customTopicsProvider);
    if (ref.read(customTopicsProvider.notifier).isFollowed(normalized)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space1,
        FacteurSpacing.space4,
        FacteurSpacing.space2,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space3,
          FacteurSpacing.space2,
          FacteurSpacing.space2,
          FacteurSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: colors.primaryMuted.withOpacity(0.35),
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: colors.primary.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              PhosphorIcons.bellSimpleRinging(PhosphorIconsStyle.regular),
              color: colors.primary,
              size: 18,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Expanded(
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: FacteurTypography.bodySmall(colors.textSecondary),
                  children: [
                    const TextSpan(text: 'Pour ne rien rater sur '),
                    TextSpan(
                      text: '« $normalized »',
                      style: FacteurTypography.bodySmall(colors.textPrimary)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ', ajoute-le à tes sujets.'),
                  ],
                ),
              ),
            ),
            const SizedBox(width: FacteurSpacing.space2),
            _FollowPill(onPressed: () => _handleFollow(context, ref, normalized)),
            const SizedBox(width: 2),
            InkResponse(
              radius: 16,
              onTap: () {
                ref.read(dismissedFollowSuggestionsProvider.notifier).update(
                      (s) => {...s, normalized.toLowerCase()},
                    );
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  PhosphorIcons.x(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleFollow(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final colors = context.facteurColors;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customTopicsProvider.notifier).followTopic(name);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('« $name » ajouté à tes sujets suivis'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Impossible d\'ajouter ce sujet pour le moment.'),
          backgroundColor: colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _FollowPill extends StatelessWidget {
  final VoidCallback onPressed;
  const _FollowPill({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(FacteurRadius.pill),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space3,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.plus(PhosphorIconsStyle.bold),
                size: 12,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                'Suivre',
                style: FacteurTypography.labelMedium(Colors.white)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
