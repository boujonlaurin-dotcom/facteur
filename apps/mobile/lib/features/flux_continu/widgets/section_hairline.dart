import 'package:flutter/material.dart';

/// 1-pixel gradient separator between Flux Continu sections.
///
/// Tones from transparent → border → transparent so the seam reads as a
/// quiet seam rather than a sharp line.
class SectionHairline extends StatelessWidget {
  final EdgeInsetsGeometry margin;

  const SectionHairline({
    super.key,
    this.margin = const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
  });

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).dividerColor.withValues(alpha: 0.6);
    return Container(
      margin: margin,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.transparent, base, Colors.transparent],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
