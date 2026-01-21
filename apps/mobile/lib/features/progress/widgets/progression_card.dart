import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../repositories/progress_repository.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/design/facteur_button.dart';

/// Carte insérée dynamiquement dans le feed pour proposer de suivre un sujet
/// après la lecture d'un article.
///
/// MVP: Quiz functionality is temporarily disabled. Users can still follow topics
/// to track interest, but the "Coming Soon" badge indicates Quiz feature is coming.
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

  Future<void> _handleFollowTopic() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(progressRepositoryProvider).followTopic(widget.topic);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFollowed = true;
        });
        NotificationService.showSuccess(
            'Thème "${widget.topic}" suivi ! Quiz bientôt disponibles.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        NotificationService.showError('Erreur : $e');
      }
    }
  }

  void _showComingSoonInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.facteurColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
              color: context.facteurColors.primary,
            ),
            const SizedBox(width: 8),
            const Text('Quiz bientôt disponibles'),
          ],
        ),
        content: Text(
          'Nous préparons des quiz personnalisés pour tester vos connaissances '
          'sur "${widget.topic}" et d\'autres sujets que vous suivez.\n\n'
          'En suivant ce thème, vous serez notifié dès leur disponibilité !',
          style: TextStyle(color: context.facteurColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Compris',
              style: TextStyle(color: context.facteurColors.primary),
            ),
          ),
        ],
      ),
    );
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
              // Coming Soon Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                      color: colors.primary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Bientôt',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _isFollowed
                    ? PhosphorIcons.checkCircle(PhosphorIconsStyle.fill)
                    : PhosphorIcons.lightbulb(PhosphorIconsStyle.fill),
                color: _isFollowed ? colors.success : colors.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isFollowed
                      ? 'Thème suivi !'
                      : 'Envie d\'aller plus loin sur "${widget.topic}" ?',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isFollowed
                ? 'Vous recevrez des quiz personnalisés dès qu\'ils seront disponibles.'
                : 'Suivez ce thème pour être notifié quand les quiz seront disponibles et tester votre progression.',
            style: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FacteurButton(
                  label: _isFollowed ? 'Thème suivi ✓' : 'Suivre ce thème',
                  isLoading: _isLoading,
                  onPressed: _isFollowed ? null : _handleFollowTopic,
                  icon: _isFollowed
                      ? PhosphorIcons.check(PhosphorIconsStyle.bold)
                      : PhosphorIcons.plus(PhosphorIconsStyle.bold),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _showComingSoonInfo,
                icon: Icon(
                  PhosphorIcons.info(PhosphorIconsStyle.regular),
                  color: colors.textTertiary,
                ),
                tooltip: 'En savoir plus',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
