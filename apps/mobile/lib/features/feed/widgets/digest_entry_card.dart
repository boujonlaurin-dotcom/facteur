import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../digest/providers/digest_provider.dart';

/// Mini-carousel horizontal en tête du feed contenant la carte
/// "L'essentiel du jour". La structure ListView permet d'accueillir d'autres
/// cartes (mode serein, etc.) sans changer la mise en page parente.
class DigestEntryCard extends ConsumerWidget {
  const DigestEntryCard({super.key});

  static const double _carouselHeight = 156;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final digest = ref.watch(digestProvider).valueOrNull;
    final articleCount = digest?.items.length ?? 5;
    final targetDate = digest?.targetDate ?? DateTime.now();

    return SizedBox(
      height: _carouselHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        children: [
          _DigestCard(
            articleCount: articleCount,
            targetDate: targetDate,
            onTap: () => context.push(RoutePaths.digest),
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

    return SizedBox(
      width: 220,
      child: FacteurCard(
        onTap: onTap,
        backgroundColor: isDark
            ? colors.surface
            : const Color(0xFFFBF5EE),
        borderRadius: FacteurRadius.medium,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(isDark ? 0.18 : 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "L'ESSENTIEL",
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "L'essentiel du jour",
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '$articleCount articles · ${_formatDate(targetDate)}',
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const List<String> _frMonthsAbbr = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];

  static String _formatDate(DateTime date) {
    return '${date.day} ${_frMonthsAbbr[date.month - 1]}';
  }
}
