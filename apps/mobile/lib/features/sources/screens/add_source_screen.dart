import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../shared/widgets/buttons/primary_button.dart';
import '../../../core/ui/notification_service.dart';
import '../providers/sources_providers.dart';
import '../widgets/source_preview_card.dart';

/// Écran d'ajout de source
class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _previewData;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _detectSource() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      NotificationService.showError('L\'URL ne peut pas être vide');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final data = await repository.detectSource(url);

      setState(() {
        _previewData = data;
      });
    } catch (e) {
      NotificationService.showError(
          'Impossible de trouver une source valide à cette adresse');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmSource() async {
    if (_previewData == null) return;

    setState(() => _isLoading = true);

    try {
      final url = _previewData!['feed_url'] as String;
      final name = _previewData!['name'] as String?;

      final repository = ref.read(sourcesRepositoryProvider);
      await repository.addCustomSource(url, name: name);

      if (mounted) {
        NotificationService.showSuccess(
            'Source ajoutée ! Ses articles apparaîtront dans ton feed d\'ici 1 à 2 minutes.');
        // Refresh sources list
        ref.invalidate(userSourcesProvider);
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError('Erreur lors de l\'ajout : $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _reset() {
    setState(() {
      _previewData = null;
      _urlController.clear();
    });
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_previewData != null)
              SourcePreviewCard(
                data: _previewData!,
                onConfirm: _confirmSource,
                onCancel: _reset,
                isLoading: _isLoading,
              )
            else ...[
              Text(
                'Colle l\'URL d\'un flux RSS ou d\'un journal en ligne (Substack, Le Monde, etc.).',
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
                enabled: !_isLoading,
                style: Theme.of(context).textTheme.bodyMedium,
                onSubmitted: (_) => _detectSource(),
              ),

              const SizedBox(height: 24),

              PrimaryButton(
                label: 'Détecter la source',
                onPressed: _isLoading ? null : _detectSource,
                isLoading: _isLoading,
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
                label: 'Flux RSS / Newsletter',
                example: 'https://monjournal.substack.com/feed',
              ),
              const SizedBox(height: 8),
              _ExampleUrl(
                icon: PhosphorIcons.globe(PhosphorIconsStyle.regular),
                label: 'Site Web (Smart Detect)',
                example: 'https://www.lemonde.fr',
              ),
            ],
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
