import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../models/source_model.dart';
import '../providers/sources_providers.dart';
import '../widgets/source_detail_modal.dart';

class ThemeSourcesScreen extends ConsumerStatefulWidget {
  final String themeSlug;
  final String? themeName;

  const ThemeSourcesScreen({
    super.key,
    required this.themeSlug,
    this.themeName,
  });

  @override
  ConsumerState<ThemeSourcesScreen> createState() => _ThemeSourcesScreenState();
}

class _ThemeSourcesScreenState extends ConsumerState<ThemeSourcesScreen> {
  final Set<String> _trustedIds = {};
  final Set<String> _pendingIds = {};

  Future<void> _toggleTrust(Source source) async {
    if (_pendingIds.contains(source.id)) return;

    setState(() => _pendingIds.add(source.id));

    try {
      final repository = ref.read(sourcesRepositoryProvider);
      final wasTrusted =
          source.isTrusted || _trustedIds.contains(source.id);

      if (wasTrusted) {
        await repository.untrustSource(source.id);
        setState(() => _trustedIds.remove(source.id));
      } else {
        await repository.trustSource(source.id);
        setState(() => _trustedIds.add(source.id));
        if (mounted) {
          NotificationService.showSuccess(
              'Source ajoutee ! Ses contenus apparaitront dans ton feed.');
        }
      }

      ref.invalidate(userSourcesProvider);
      ref.invalidate(trendingSourcesProvider);
    } catch (e) {
      if (mounted) {
        NotificationService.showError('Erreur : $e');
      }
    } finally {
      if (mounted) {
        setState(() => _pendingIds.remove(source.id));
      }
    }
  }

  void _showSourceModal(Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SourceDetailModal(
        source: source,
        onToggleTrust: () => _toggleTrust(source),
        onCopyFeedUrl: source.isCustom && (source.url?.isNotEmpty ?? false)
            ? () async {
                await Clipboard.setData(ClipboardData(text: source.url!));
                if (mounted) {
                  NotificationService.showSuccess(
                      'URL du flux copiee dans le presse-papiers !');
                }
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(sourcesByThemeProvider(widget.themeSlug));
    final displayName = widget.themeName ?? widget.themeSlug;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: Hero(
          tag: 'theme_${widget.themeSlug}',
          child: Material(
            color: Colors.transparent,
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
        ),
      ),
      body: sourcesAsync.when(
        data: (response) {
          if (response.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.regular),
                        size: 48, color: colors.textTertiary),
                    const SizedBox(height: 16),
                    Text(
                      'Aucune source pour ce theme.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (response.curated.isNotEmpty) ...[
                _buildSectionHeader(
                    context, 'Sources curees', response.curated.length),
                const SizedBox(height: 8),
                ...response.curated.map((s) => _buildSourceTile(context, s)),
                const SizedBox(height: 24),
              ],
              if (response.candidates.isNotEmpty) ...[
                _buildSectionHeader(
                    context, 'Candidates', response.candidates.length),
                const SizedBox(height: 8),
                ...response.candidates.map((s) => _buildSourceTile(context, s)),
                const SizedBox(height: 24),
              ],
              if (response.community.isNotEmpty) ...[
                _buildSectionHeader(context, 'Decouvertes par la communaute',
                    response.community.length),
                const SizedBox(height: 8),
                ...response.community.map((s) => _buildSourceTile(context, s)),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIcons.warningCircle(PhosphorIconsStyle.regular),
                    size: 48, color: colors.error),
                const SizedBox(height: 16),
                Text(
                  'Impossible de charger les sources.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(sourcesByThemeProvider(widget.themeSlug)),
                  child: const Text('Reessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    final colors = context.facteurColors;
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceTile(BuildContext context, Source source) {
    final colors = context.facteurColors;
    final isTrusted = source.isTrusted || _trustedIds.contains(source.id);
    final isPending = _pendingIds.contains(source.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTrusted
              ? colors.primary.withOpacity(0.3)
              : colors.border,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLogo(source, colors),
        title: Text(
          source.name,
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          source.description?.isNotEmpty == true
              ? source.description!
              : source.getTypeLabel(),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isPending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isTrusted
                ? Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                    color: colors.success)
                : IconButton(
                    icon: Icon(
                        PhosphorIcons.plusCircle(PhosphorIconsStyle.regular),
                        color: colors.primary),
                    onPressed: () => _toggleTrust(source),
                  ),
        onTap: () => _showSourceModal(source),
      ),
    );
  }

  Widget _buildLogo(Source source, FacteurColors colors) {
    if (source.logoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          source.logoUrl!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildLogoFallback(colors),
        ),
      );
    }
    return _buildLogoFallback(colors);
  }

  Widget _buildLogoFallback(FacteurColors colors) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
          size: 20, color: colors.primary),
    );
  }
}
