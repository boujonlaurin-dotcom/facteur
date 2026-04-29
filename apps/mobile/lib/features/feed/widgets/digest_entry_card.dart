import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../digest/providers/digest_provider.dart';
import '../../digest/widgets/essentiel_pill.dart';

/// Mini-carousel horizontal en tête du feed contenant la carte
/// "L'essentiel du jour". La structure ListView permet d'accueillir d'autres
/// cartes (mode serein, etc.) sans changer la mise en page parente.
class DigestEntryCard extends ConsumerWidget {
  const DigestEntryCard({super.key});

  static const double _carouselHeight = 170;
  static const double _horizontalPadding = 16;
  static const double _peek = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(digestProvider).valueOrNull;
    final articleCount = digest?.items.length ?? 5;
    final targetDate = digest?.targetDate ?? DateTime.now();
    final width = MediaQuery.of(context).size.width -
        (_horizontalPadding * 2) -
        _peek;

    return SizedBox(
      height: _carouselHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        physics: const BouncingScrollPhysics(),
        children: [
          SizedBox(
            width: width,
            child: _DigestCard(
              articleCount: articleCount,
              targetDate: targetDate,
              onTap: () => context.push(RoutePaths.digest),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigestCard extends StatelessWidget {
  final int articleCount;
  final DateTime targetDate;
  final VoidCallback onTap;

  const _DigestCard({
    required this.articleCount,
    required this.targetDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FacteurCard(
      onTap: onTap,
      backgroundColor:
          isDark ? colors.surface : const Color(0xFFFBF5EE),
      borderRadius: FacteurRadius.medium,
      padding: EdgeInsets.zero,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Perforation gauche : colonne pleine de dots oranges
          // façon timbre, du haut vers le bas de la carte.
          Positioned(
            left: 10,
            top: 16,
            bottom: 16,
            child: _PerforationDots(color: colors.primary),
          ),
          // Illustration facteur, ancrée bottom-right (flush coin).
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                height: 130,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Pill "L'ESSENTIEL" en haut à gauche.
          Positioned(
            top: 16,
            left: 28,
            child: EssentielPill(colors: colors, isDark: isDark),
          ),
          // Titre + caption en bas à gauche.
          Positioned(
            left: 28,
            right: 120,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "L'essentiel du jour",
                  style: FacteurTypography.serifTitle(colors.textPrimary)
                      .copyWith(fontSize: 24, height: 1.15),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '$articleCount articles · ${formatDigestDate(targetDate)}',
                  style:
                      FacteurTypography.stamp(colors.textTertiary).copyWith(
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Colonne de dots décoratifs façon perforation de timbre. Le nombre de dots
/// est calculé à partir de la hauteur disponible pour remplir tout le côté.
class _PerforationDots extends StatelessWidget {
  final Color color;
  static const double _dotSize = 3;
  static const double _spacing = 6;

  const _PerforationDots({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final unit = _dotSize + _spacing;
        final count = height <= 0 ? 0 : ((height + _spacing) / unit).floor();
        return SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < count; i++)
                Container(
                  width: _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.85),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

