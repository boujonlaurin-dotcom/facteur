import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/ui/notification_service.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';

const Color _terracotta = Color(0xFFE07A5F);

/// Bottom sheet for adding a niche topic / entity subscription.
class EntityAddSheet extends ConsumerStatefulWidget {
  final String? themeSlug;

  const EntityAddSheet({super.key, this.themeSlug});

  static void show(BuildContext context, {String? themeSlug}) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: EntityAddSheet(themeSlug: themeSlug),
        ),
      ),
    );
  }

  @override
  ConsumerState<EntityAddSheet> createState() => _EntityAddSheetState();
}

class _EntityAddSheetState extends ConsumerState<EntityAddSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<DisambiguationSuggestion>? _suggestions;
  int? _followingIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.length < 2) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(topicRepositoryProvider);
      final suggestions = await repo.disambiguate(
        name,
        theme: widget.themeSlug,
      );

      if (!mounted) return;

      if (suggestions.isEmpty) {
        // No suggestions at all — follow as plain topic
        await ref
            .read(customTopicsProvider.notifier)
            .followTopic(name, slugParent: widget.themeSlug);
        if (mounted) {
          Navigator.of(context).pop();
          NotificationService.showInfo('"$name" ajouté à vos intérêts');
        }
      } else {
        // Show confirmation/disambiguation UI (even for 1 suggestion)
        setState(() {
          _suggestions = suggestions;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data;
        final msg = (detail is Map && detail['detail'] is String)
            ? detail['detail'] as String
            : 'Erreur lors de la recherche';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur inattendue lors de la recherche'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted && _suggestions == null) setState(() => _loading = false);
    }
  }

  Future<void> _followSuggestion(
    DisambiguationSuggestion s,
    int index,
  ) async {
    setState(() => _followingIndex = index);
    try {
      final notifier = ref.read(customTopicsProvider.notifier);
      if (s.entityType != null) {
        await notifier.followEntity(s.canonicalName, s.entityType!, slugParent: s.slugParent);
      } else {
        await notifier.followTopic(s.canonicalName, slugParent: s.slugParent);
      }
      if (mounted) {
        Navigator.of(context).pop();
        NotificationService.showInfo(
          '"${s.canonicalName}" ajouté à vos intérêts',
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data;
        final msg = (detail is Map && detail['detail'] is String)
            ? detail['detail'] as String
            : 'Erreur lors de l\'ajout';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur inattendue lors de l\'ajout'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _followingIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SafeArea(
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

            if (_suggestions != null)
              _buildDisambiguationView(colors, textTheme)
            else
              _buildInputView(colors, textTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputView(FacteurColors colors, TextTheme textTheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          'Ajouter un sujet personnalisé',
          style: textTheme.displaySmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Personne, organisation, événement, lieu...',
          style: textTheme.bodySmall?.copyWith(
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),

        // Text field
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Ex: Emmanuel Macron, OpenAI, Tour de France...',
            hintStyle: textTheme.bodyMedium?.copyWith(
              color: colors.textTertiary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),

        // Submit button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    PhosphorIcons.plus(),
                    size: 16,
                    color: Colors.white,
                  ),
            label: Text(
              _loading ? 'Recherche...' : 'Suivre',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _terracotta,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _terracotta.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisambiguationView(FacteurColors colors, TextTheme textTheme) {
    final suggestions = _suggestions!;
    final searchedName = _controller.text.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          suggestions.length == 1
              ? 'Confirmez votre choix'
              : 'Précisez votre choix',
          style: textTheme.displaySmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          suggestions.length == 1
              ? 'Résultat pour "$searchedName"'
              : 'Plusieurs résultats pour "$searchedName"',
          style: textTheme.bodySmall?.copyWith(
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),

        // Suggestion rows
        ...List.generate(suggestions.length, (index) {
          final s = suggestions[index];
          final isFollowing = _followingIndex == index;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.canonicalName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.entityType != null) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color:
                                colors.textTertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            getEntityTypeLabel(s.entityType!),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                      if (s.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          s.description,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isFollowing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _terracotta,
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _followingIndex != null
                        ? null
                        : () => _followSuggestion(s, index),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            ),
          );
        }),

        const SizedBox(height: FacteurSpacing.space2),

        // Back to input
        Center(
          child: TextButton.icon(
            onPressed: _followingIndex != null
                ? null
                : () => setState(() => _suggestions = null),
            icon: Icon(
              PhosphorIcons.arrowLeft(),
              size: 14,
              color: colors.textTertiary,
            ),
            label: Text(
              'Modifier ma recherche',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
