import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/serein_colors.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../digest/providers/digest_provider.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/widgets/essentiel_pill.dart';
import '../../digest/widgets/bonnes_nouvelles_pill.dart';

/// Mini-carousel horizontal en tête du feed.
///
/// Toujours 2 cartes : « L'essentiel du jour » et « Les bonnes nouvelles
/// du jour ». L'ordre dépend du toggle Serein (Bonnes nouvelles en tête
/// quand activé).
class DigestEntryCard extends ConsumerWidget {
  const DigestEntryCard({super.key});

  static const double _carouselHeight = 170;
  static const double _horizontalPadding = 16;
  static const double _peek = 24;
  static const double _gap = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dual = ref.watch(dualDigestPreviewProvider);
    final isSerein = ref.watch(sereinToggleProvider).enabled;
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final normalCount = dual.normal?.items.length ?? 5;
    final sereinCount = dual.serein?.items.length ?? normalCount;
    final targetDate = dual.normal?.targetDate ?? DateTime.now();

    final width = MediaQuery.of(context).size.width -
        (_horizontalPadding * 2) -
        _peek;

    Future<void> openDigest({required bool requireSerein}) async {
      final original = ref.read(sereinToggleProvider).enabled;
      final notifier = ref.read(sereinToggleProvider.notifier);
      if (requireSerein != original) {
        notifier.setEnabledLocal(requireSerein);
      }
      await context.push(RoutePaths.digest);
      // Restore the user's persisted mode on return — visiting "Lecture
      // apaisée" must not change the global preference.
      if (requireSerein != original &&
          ref.read(sereinToggleProvider).enabled != original) {
        notifier.setEnabledLocal(original);
      }
    }

    final cardBackground =
        isDark ? colors.surface : const Color(0xFFFBF5EE);

    final essentielCard = SizedBox(
      width: width,
      child: _CarouselCard(
        backgroundColor: cardBackground,
        perforationColor: colors.primary,
        pill: EssentielPill(colors: colors, isDark: isDark),
        title: "L'essentiel du jour",
        titleColor: colors.textPrimary,
        captionColor: colors.textTertiary,
        articleCount: normalCount,
        targetDate: targetDate,
        onTap: () => openDigest(requireSerein: false),
      ),
    );

    final lectureApaiseeCard = SizedBox(
      width: width,
      child: _CarouselCard(
        backgroundColor: cardBackground,
        perforationColor: SereinColors.sereinColor,
        pill: BonnesNouvellesPill(isDark: isDark),
        title: 'Les bonnes nouvelles',
        titleColor: colors.textPrimary,
        captionColor: colors.textTertiary,
        articleCount: sereinCount,
        targetDate: targetDate,
        assetPath: 'assets/notifications/facteur_goodnews.png',
        onTap: () => openDigest(requireSerein: true),
      ),
    );

    final cards = isSerein
        ? [lectureApaiseeCard, essentielCard]
        : [essentielCard, lectureApaiseeCard];

    return SizedBox(
      height: _carouselHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, __) => const SizedBox(width: _gap),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }
}

class _CarouselCard extends StatelessWidget {
  final Color backgroundColor;
  final Color perforationColor;
  final Widget pill;
  final String title;
  final Color titleColor;
  final Color captionColor;
  final int articleCount;
  final DateTime targetDate;
  final VoidCallback onTap;
  final double avatarOpacity;
  final String assetPath;

  const _CarouselCard({
    required this.backgroundColor,
    required this.perforationColor,
    required this.pill,
    required this.title,
    required this.titleColor,
    required this.captionColor,
    required this.articleCount,
    required this.targetDate,
    required this.onTap,
    this.avatarOpacity = 1.0,
    this.assetPath = 'assets/notifications/facteur_avatar.png',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return FacteurCard(
      onTap: onTap,
      backgroundColor: backgroundColor,
      borderRadius: FacteurRadius.medium,
      padding: EdgeInsets.zero,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Subtle radial colour veil — top-right corner
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                width: 180,
                height: 120,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.0,
                    colors: [
                      perforationColor.withOpacity(0.10),
                      perforationColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 16,
            bottom: 16,
            child: _PerforationDots(color: perforationColor),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: avatarOpacity,
                child: Image.asset(
                  assetPath,
                  height: 130,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(top: 16, left: 28, child: pill),
          Positioned(
            top: 14,
            right: 14,
            child: Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
              size: 18,
              color: colors.textSecondary,
            ),
          ),
          Positioned(
            left: 28,
            right: 120,
            top: 52,
            child: Text(
              title,
              style: FacteurTypography.serifTitle(titleColor)
                  .copyWith(fontSize: 22, height: 1.15),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: 28,
            right: 120,
            bottom: 16,
            child: Text(
              '$articleCount articles · ${formatDigestDate(targetDate)}',
              style: FacteurTypography.stamp(captionColor).copyWith(
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colonne de dots décoratifs façon perforation de timbre.
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
