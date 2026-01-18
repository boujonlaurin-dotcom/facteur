import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../core/ui/notification_service.dart';

/// Écran d'ajout de source (placeholder)
class AddSourceScreen extends StatefulWidget {
  const AddSourceScreen({super.key});

  @override
  State<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends State<AddSourceScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Ajouter une source',
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Colle l\'URL d\'un flux RSS, d\'une chaîne YouTube ou d\'un podcast.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://...',
                prefixIcon: Icon(
                  PhosphorIcons.link(PhosphorIconsStyle.regular),
                ),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            const SizedBox(height: 24),

            PrimaryButton(
              label: 'Détecter la source',
              onPressed: () {
                // TODO: Implémenter la détection
                NotificationService.showInfo('Fonctionnalité à venir');
              },
            ),

            const SizedBox(height: 32),

            // Exemples
            Text(
              'Exemples d\'URLs supportées :',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            _ExampleUrl(
              icon: PhosphorIcons.rss(PhosphorIconsStyle.regular),
              label: 'Flux RSS',
              example: 'https://example.com/feed.xml',
            ),
            const SizedBox(height: 8),
            _ExampleUrl(
              icon: PhosphorIcons.youtubeLogo(PhosphorIconsStyle.regular),
              label: 'Chaîne YouTube',
              example: 'https://youtube.com/@channel',
            ),
            const SizedBox(height: 8),
            _ExampleUrl(
              icon: PhosphorIcons.headphones(PhosphorIconsStyle.regular),
              label: 'Podcast RSS',
              example: 'https://example.com/podcast.rss',
            ),
          ],
        ),
      ),
    );
  }
}

class _ExampleUrl extends StatelessWidget {
  final IconData icon;
  final String label;
  final String example;

  const _ExampleUrl({
    required this.icon,
    required this.label,
    required this.example,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.textSecondary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(
              example,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
