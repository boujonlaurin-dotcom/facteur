import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

// ⚠️ Swap volontaire vs la maquette : les prénoms y sont inversés (la photo
// étiquetée DJANGO est en réalité Laurin, et vice versa). Convention retenue :
// le nom de fichier = la vraie personne, et les labels affichés suivent le
// nom de fichier. Ne pas « corriger » en réalignant sur la maquette.
const _laurinAsset = 'assets/images/founders/laurin.jpg';
const _djangoAsset = 'assets/images/founders/django.jpg';

/// Collage des deux fondateurs pour l'écran Soutien : photos légèrement
/// rotées, clip organique (radii asymétriques), étiquette mono sous chacune.
class FounderCollage extends StatelessWidget {
  /// Côté des photos. 128 sur l'écran Soutien (pleine page) ; réduit dans une
  /// bottom sheet où le collage n'est qu'une amorce (cf. `CallInviteSheet`).
  final double photoSize;

  const FounderCollage({super.key, this.photoSize = 128});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _FounderPolaroid(
          asset: _djangoAsset,
          label: 'DJANGO',
          rotation: -0.05,
          size: photoSize,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(48),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(44),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space4),
        Padding(
          // Décalage vertical proportionnel : le collage garde son décentrage
          // quelle que soit la taille des photos.
          padding: EdgeInsets.only(bottom: photoSize * 0.14),
          child: _FounderPolaroid(
            asset: _laurinAsset,
            label: 'LAURIN',
            rotation: 0.06,
            size: photoSize,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(46),
              bottomLeft: Radius.circular(42),
              bottomRight: Radius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}

class _FounderPolaroid extends StatelessWidget {
  final String asset;
  final String label;
  final double rotation;
  final double size;
  final BorderRadius borderRadius;

  const _FounderPolaroid({
    required this.asset,
    required this.label,
    required this.rotation,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Transform.rotate(
      angle: rotation,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: FounderPhoto(asset: asset, size: size),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            label,
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Duo miniature (photos rondes qui se chevauchent) pour la tuile Soutien
/// des Réglages.
class FounderMiniDuo extends StatelessWidget {
  const FounderMiniDuo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      width: size * 1.6,
      height: size,
      child: Stack(
        children: [
          _circle(_djangoAsset, colors.surface),
          Positioned(
            left: size * 0.6,
            child: _circle(_laurinAsset, colors.surface),
          ),
        ],
      ),
    );
  }

  Widget _circle(String asset, Color ringColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
      ),
      child: ClipOval(child: FounderPhoto(asset: asset, size: size)),
    );
  }
}

/// Photo d'un fondateur avec fallback gracieux (monogramme sur fond papier)
/// tant que les vraies photos ne sont pas livrées dans les assets.
class FounderPhoto extends StatelessWidget {
  final String asset;
  final double size;

  const FounderPhoto({super.key, required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        width: size,
        height: size,
        color: colors.primary.withValues(alpha: 0.15),
        alignment: Alignment.center,
        child: Text(
          asset.contains('laurin') ? 'L' : 'D',
          style: GoogleFonts.fraunces(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}
