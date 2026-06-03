import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/source_model.dart';

/// Avatar carré pour une source : logo si dispo, sinon initiales du nom.
/// Utilisé partout où l'on rend un identifiant visuel d'une source (carousel
/// pépites, modal détail, listes…).
class SourceLogoAvatar extends StatelessWidget {
  final String? logoUrl;
  final String name;
  final double size;
  final double radius;

  SourceLogoAvatar({
    super.key,
    required Source source,
    this.size = 56,
    this.radius = 12,
  })  : logoUrl = source.logoUrl,
        name = source.name;

  /// Variante sans `Source` complet — pour le hero des sections source de la
  /// Tournée (PR « Sources dans la Tournée ») qui ne porte que le
  /// `sourceLogoUrl` + le `label` (nom de la source).
  const SourceLogoAvatar.fromUrl({
    super.key,
    required this.logoUrl,
    required this.name,
    this.size = 56,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final url = logoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _Initials(
            name: name,
            size: size,
            radius: radius,
            colors: colors,
          ),
        ),
      );
    }
    return _Initials(
      name: name,
      size: size,
      radius: radius,
      colors: colors,
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final double size;
  final double radius;
  final FacteurColors colors;

  const _Initials({
    required this.name,
    required this.size,
    required this.radius,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
