import 'dart:async';
import 'dart:math' as math;

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
import '../../digest/widgets/lecture_apaisee_pill.dart';

/// Mini-carousel horizontal en tête du feed.
///
/// Toujours 2 cartes : « L'essentiel du jour » et « Une lecture apaisée ».
/// L'ordre dépend du toggle Serein (Lecture apaisée en tête quand activé).
class DigestEntryCard extends ConsumerStatefulWidget {
  const DigestEntryCard({super.key});

  static const double _carouselHeight = 170;
  static const double _horizontalPadding = 16;
  static const double _peek = 24;
  static const double _gap = 12;

  @override
  ConsumerState<DigestEntryCard> createState() => _DigestEntryCardState();
}

class _DigestEntryCardState extends ConsumerState<DigestEntryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _pulseDelay;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseDelay = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _pulse.forward();
    });
  }

  @override
  void dispose() {
    _pulseDelay?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dual = ref.watch(dualDigestPreviewProvider);
    final isSerein = ref.watch(sereinToggleProvider).enabled;
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final normalCount = dual.normal?.items.length ?? 5;
    final sereinCount = dual.serein?.items.length ?? normalCount;
    final targetDate = dual.normal?.targetDate ?? DateTime.now();

    final width = MediaQuery.of(context).size.width -
        (DigestEntryCard._horizontalPadding * 2) -
        DigestEntryCard._peek;

    void openDigest({required bool requireSerein}) {
      if (requireSerein != isSerein) {
        ref.read(sereinToggleProvider.notifier).toggle();
      }
      context.push(RoutePaths.digest);
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
        pill: LectureApaiseePill(isDark: isDark),
        title: 'Une lecture apaisée',
        titleColor: colors.textPrimary,
        captionColor: colors.textTertiary,
        articleCount: sereinCount,
        targetDate: targetDate,
        onTap: () => openDigest(requireSerein: true),
      ),
    );

    final cards = isSerein
        ? [lectureApaiseeCard, essentielCard]
        : [essentielCard, lectureApaiseeCard];

    return SizedBox(
      height: DigestEntryCard._carouselHeight,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final scale = 1.0 + 0.04 * math.sin(_pulse.value * 2 * math.pi);
          return Transform.scale(scale: scale, child: child);
        },
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: DigestEntryCard._horizontalPadding),
          physics: const BouncingScrollPhysics(),
          itemCount: cards.length,
          separatorBuilder: (_, __) =>
              const SizedBox(width: DigestEntryCard._gap),
          itemBuilder: (_, i) => cards[i],
        ),
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
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                height: 130,
                fit: BoxFit.contain,
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
                  .copyWith(fontSize: 24, height: 1.15),
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
