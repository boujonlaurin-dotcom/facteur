/// Decides how many lines of title and description should be shown on an
/// article preview card.
///
/// When a card has no image, we allow the title to grow up to 5 lines and
/// shrink the description progressively so the overall card height stays
/// close to a card that shows an image (title 3 lines + no description).
class ArticleTitleLayout {
  static const double titleLineHeight = 20.0 * 1.2;
  static const double descLineHeight = 15.0 * 1.3;

  static const double _titleCharPx = 10.0;
  static const double _descCharPx = 8.0;

  static int titleMaxLines({required bool hasImage}) => hasImage ? 3 : 5;

  static int estimateTitleLines({
    required String title,
    required double availableWidth,
    required bool hasImage,
  }) {
    if (title.trim().isEmpty) return 1;
    final perLine =
        (availableWidth / _titleCharPx).clamp(1.0, double.infinity);
    final lines = (title.length / perLine).ceil();
    return lines.clamp(1, titleMaxLines(hasImage: hasImage));
  }

  /// Standard feed card: 3→2L, 4→1L, 5→0L. Hidden when image is present.
  static int descriptionMaxLines({
    required int estimatedTitleLines,
    required bool hasImage,
    required bool hasDescription,
  }) {
    if (hasImage || !hasDescription) return 0;
    if (estimatedTitleLines <= 3) return 2;
    if (estimatedTitleLines == 4) return 1;
    return 0;
  }

  /// Carousel variant (`alwaysShowDescription = !imageVisible`): 3→4L, 4→2L, 5→1L.
  static int descriptionMaxLinesForCarousel({
    required int estimatedTitleLines,
    required bool hasImage,
    required bool hasDescription,
  }) {
    if (hasImage || !hasDescription) return 0;
    if (estimatedTitleLines <= 3) return 4;
    if (estimatedTitleLines == 4) return 2;
    return 1;
  }

  static int estimateDescriptionLines({
    required String description,
    required double availableWidth,
    required int maxLines,
  }) {
    if (maxLines <= 0 || description.trim().isEmpty) return 0;
    final perLine =
        (availableWidth / _descCharPx).clamp(1.0, double.infinity);
    final lines = (description.length / perLine).ceil();
    return lines.clamp(1, maxLines);
  }
}
