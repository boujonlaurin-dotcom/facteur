import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../custom_topics/providers/personalization_provider.dart';
import '../../feed/models/content_model.dart';
import '../../feed/repositories/personalization_repository.dart';

const Color _terracotta = Color(0xFFE07A5F);

/// Bottom sheet listing entities from an article with follow/unfollow
/// and mute/unmute actions.
class ArticleEntitiesSheet extends ConsumerWidget {
  final Content content;

  const ArticleEntitiesSheet({super.key, required this.content});

  static void show(BuildContext context, Content content) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ArticleEntitiesSheet(content: content),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final topicsAsync = ref.watch(customTopicsProvider);
    final topics = topicsAsync.valueOrNull ?? [];
    final perso = ref.watch(personalizationProvider).valueOrNull;
    final mutedTopics = perso?.mutedTopics ?? {};

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.60,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),

              // Title
              Text(
                'Sujets de cet article',
                style: textTheme.displaySmall?.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space4),

              // Entity rows
              ...content.entities.map((entity) {
                final isFollowed = topics.any(
                  (t) =>
                      t.canonicalName?.toLowerCase() ==
                      entity.text.toLowerCase(),
                );
                final isMuted =
                    mutedTopics.contains(entity.text.toLowerCase());

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      // Entity name
                      Expanded(
                        child: Opacity(
                          opacity: isMuted ? 0.5 : 1.0,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entity.text,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (entity.label.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.textTertiary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    getEntityTypeLabel(entity.label),
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colors.textTertiary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Actions: Follow/Followed + Mute/Unmute
                      if (isMuted)
                        // Muted state: show unmute button
                        GestureDetector(
                          onTap: () async {
                            final repo =
                                ref.read(personalizationRepositoryProvider);
                            try {
                              await repo
                                  .unmuteTopic(entity.text.toLowerCase());
                              ref.invalidate(personalizationProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Erreur'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.textTertiary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  PhosphorIcons.eyeSlash(
                                      PhosphorIconsStyle.regular),
                                  size: 14,
                                  color: colors.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Masqué',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.textTertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        // Mute button (eye-slash)
                        GestureDetector(
                          onTap: () async {
                            final repo =
                                ref.read(personalizationRepositoryProvider);
                            try {
                              await repo
                                  .muteTopic(entity.text.toLowerCase());
                              ref.invalidate(personalizationProvider);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Erreur lors du masquage'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Icon(
                              PhosphorIcons.eyeSlash(
                                  PhosphorIconsStyle.regular),
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),

                        // Follow / Followed indicator
                        if (isFollowed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _terracotta.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  PhosphorIcons.check(
                                      PhosphorIconsStyle.bold),
                                  size: 14,
                                  color: _terracotta,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Suivi',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: _terracotta,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: () {
                              ref
                                  .read(customTopicsProvider.notifier)
                                  .followEntity(entity.text, entity.label);
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: Icon(
                              PhosphorIcons.plus(PhosphorIconsStyle.bold),
                              size: 14,
                              color: _terracotta,
                            ),
                            label: Text(
                              'Suivre',
                              style: textTheme.labelSmall?.copyWith(
                                color: _terracotta,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              }),

              const SizedBox(height: FacteurSpacing.space2),
            ],
          ),
        ),
      ),
    );
  }
}
