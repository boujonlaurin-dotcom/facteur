import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../repositories/progress_repository.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/design/facteur_button.dart';

/// Carte insérée dynamiquement dans le feed pour proposer de suivre un sujet
/// après la lecture d'un article.
class ProgressionCard extends ConsumerStatefulWidget {
  final String topic;
  final VoidCallback? onDismiss;

  const ProgressionCard({
    super.key,
    required this.topic,
    this.onDismiss,
  });

  @override
  ConsumerState<ProgressionCard> createState() => _ProgressionCardState();
}

class _ProgressionCardState extends ConsumerState<ProgressionCard> {
  bool _isFollowed = false;
  bool _isLoading = false;

  Future<void> _handleAction() async {
    if (_isFollowed) {
      // Naviguer vers le quiz
      context.goNamed(RouteNames.progress);
    } else {
      // Suivre le sujet
      setState(() => _isLoading = true);
      try {
        await ref.read(progressRepositoryProvider).followTopic(widget.topic);
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isFollowed = true;
          });
          NotificationService.showSuccess('Sujet suivi !');
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          NotificationService.showError('Erreur : $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFollowed
              ? colors.primary.withOpacity(0.3)
              : colors.surfaceElevated,
          width: _isFollowed ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isFollowed
                    ? PhosphorIcons.lightning(PhosphorIconsStyle.fill)
                    : PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                color: colors.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isFollowed
                      ? 'Parfait ! Maintenant, testez-vous.'
                      : 'Ne perdez pas le fil !',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (widget.onDismiss != null)
                IconButton(
                  icon: Icon(
                    PhosphorIcons.x(PhosphorIconsStyle.regular),
                    size: 20,
                    color: colors.textTertiary,
                  ),
                  onPressed: widget.onDismiss,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isFollowed
                ? 'Un quiz rapide sur "${widget.topic}" vous attend pour valider vos connaissances.'
                : 'Vous venez de lire sur "${widget.topic}". Suivez ce thème pour débloquer des quiz et progresser.',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FacteurButton(
              label: _isFollowed ? 'Lancer le Quiz' : 'Suivre ce sujet',
              isLoading: _isLoading,
              onPressed: _handleAction,
              icon: _isFollowed
                  ? PhosphorIcons.gameController(PhosphorIconsStyle.bold)
                  : PhosphorIcons.plus(PhosphorIconsStyle.bold),
            ),
          ),
        ],
      ),
    );
  }
}
