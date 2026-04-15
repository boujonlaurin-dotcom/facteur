import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../models/theme_source_model.dart';
import '../providers/sources_providers.dart';

class ThemeExplorer extends ConsumerWidget {
  const ThemeExplorer({super.key});

  static const _defaultThemes = [
    FollowedTheme(slug: 'tech', name: 'Tech'),
    FollowedTheme(slug: 'actu-fr', name: 'Actu FR'),
    FollowedTheme(slug: 'produit', name: 'Produit'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final themesAsync = ref.watch(themesFollowedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIcons.target(PhosphorIconsStyle.regular),
                size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'Explorer par theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        themesAsync.when(
          data: (themes) {
            final displayThemes = themes.isEmpty ? _defaultThemes : themes;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: displayThemes
                    .map((theme) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildThemeChip(context, ref, theme),
                        ))
                    .toList(),
              ),
            );
          },
          loading: () => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                3,
                (_) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildPlaceholderChip(context),
                ),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildThemeChip(
      BuildContext context, WidgetRef ref, FollowedTheme theme) {
    final colors = context.facteurColors;

    return Hero(
      tag: 'theme_${theme.slug}',
      child: Material(
        color: Colors.transparent,
        child: ActionChip(
          label: Text(theme.name),
          labelStyle: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.textPrimary),
          backgroundColor: colors.surface,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          onPressed: () {
            ref
                .read(analyticsServiceProvider)
                .trackAddSourceThemeTap(theme.slug);
            context.push(
              '/settings/sources/theme/${theme.slug}',
              extra: theme.name,
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholderChip(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      width: 80,
      height: 36,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(100),
      ),
    );
  }
}
