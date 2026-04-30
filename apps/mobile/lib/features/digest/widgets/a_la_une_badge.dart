import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Badge « À LA UNE · N sources » réservé au sujet rang 1 multi-sources.
///
/// Affiché uniquement quand l'API expose `is_une=true` ET `source_count >= 2`
/// (cf. logique côté `editorial/curation.py` : ≥2 sources convergentes pour
/// décerner le badge À la Une — sinon le rang 1 est rendu comme un sujet
/// ordinaire).
///
/// Couleur terracotta dédiée (≠ couleur Essentiel ≠ couleur Bonnes nouvelles)
/// pour rendre le badge tangiblement distinct sans imiter une « breaking
/// news ».
class ALaUneBadge extends StatelessWidget {
  static const Color _accent = Color(0xFFB8530A);

  final int sourceCount;

  const ALaUneBadge({super.key, required this.sourceCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withOpacity(0.12),
        border: Border.all(color: _accent, width: 1.2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.newspaper(PhosphorIconsStyle.bold),
            size: 12,
            color: _accent,
          ),
          const SizedBox(width: 5),
          Text(
            'À LA UNE · $sourceCount sources',
            style: const TextStyle(
              color: _accent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
