import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../../widgets/sunflower_icon.dart';
import '../models/community_carousel_model.dart';

/// Horizontal carousel section showing community 🌻 recommendations.
///
/// Appears in the digest when there are community-recommended articles.
/// Displays articles as horizontal scrollable cards with source name
/// and sunflower count badge (if >= 2).
class CommunityCarouselSection extends StatefulWidget {
  final List<CommunityCarouselItem> items;
  final void Function(CommunityCarouselItem item) onArticleTap;
  final void Function(CommunityCarouselItem item)? onSunflowerTap;

  const CommunityCarouselSection({
    super.key,
    required this.items,
    required this.onArticleTap,
    this.onSunflowerTap,
  });

  @override
  State<CommunityCarouselSection> createState() =>
      _CommunityCarouselSectionState();
}

class _CommunityCarouselSectionState extends State<CommunityCarouselSection> {
  final PageController _pageController =
      PageController(viewportFraction: 0.85);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              const Text('🌻', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Recos de la communauté',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        // Carousel
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _CommunityCard(
                  item: item,
                  colors: colors,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onArticleTap(item);
                  },
                  onSunflowerTap: widget.onSunflowerTap != null
                      ? () => widget.onSunflowerTap!(item)
                      : null,
                ),
              );
            },
          ),
        ),
        // Page indicators
        if (widget.items.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.items.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: index == _currentPage ? 20 : 8,
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: index == _currentPage
                        ? SunflowerIcon.sunflowerYellow
                        : colors.textSecondary.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final CommunityCarouselItem item;
  final AppColors colors;
  final VoidCallback onTap;
  final VoidCallback? onSunflowerTap;

  const _CommunityCard({
    required this.item,
    required this.colors,
    required this.onTap,
    this.onSunflowerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.textSecondary.withOpacity(0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (item.thumbnailUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  item.thumbnailUrl!,
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 90,
                    color: colors.textSecondary.withOpacity(0.1),
                    child: Center(
                      child: Icon(
                        Icons.article_outlined,
                        color: colors.textSecondary.withOpacity(0.3),
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            // Content
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ),
                    // Footer: source + sunflower count
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        if (item.sunflowerCount >= 2) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: SunflowerIcon.sunflowerYellow
                                  .withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🌻',
                                    style: TextStyle(fontSize: 10)),
                                const SizedBox(width: 2),
                                Text(
                                  '${item.sunflowerCount}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: SunflowerIcon.sunflowerBrown,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
