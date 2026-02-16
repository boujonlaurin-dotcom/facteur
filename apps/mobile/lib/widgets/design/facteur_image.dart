import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Cross-platform network image: uses native <img> tag on web (CORS-exempt),
/// CachedNetworkImage on mobile (disk caching).
class FacteurImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context)? errorWidget;

  const FacteurImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder?.call(context) ?? const SizedBox.shrink();
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget?.call(context) ?? const SizedBox.shrink();
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder != null
          ? (context, url) => placeholder!.call(context)
          : null,
      errorWidget: (context, url, error) =>
          errorWidget?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
