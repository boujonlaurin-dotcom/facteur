import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../widgets/halo_loader.dart';
import '../widgets/veille_widgets.dart';

/// Écran d'introduction au flow Veille — affiché au premier accès
/// (pas de config active, pas de mode édition). Cadre le pitch avant
/// le wizard en 4 étapes.
///
/// Layout single-page : header simplifié (close), illustration centrale
/// (HaloLoader animé), pitch, CTA primaire « C'est parti ».
class VeilleIntroScreen extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onStart;

  const VeilleIntroScreen({
    super.key,
    required this.onClose,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: Icon(
                  PhosphorIcons.x(),
                  size: 22,
                  color: const Color(0xFF5D5B5A),
                ),
                tooltip: 'Fermer',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const HaloLoader(),
                const SizedBox(height: 28),
                const VeilleAiEyebrow('Le facteur prépare ta veille'),
                const SizedBox(height: 14),
                Text(
                  'Une veille pensée pour toi',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: const Color(0xFF2C2A29),
                  ),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    'Choisis un thème, on s\'occupe de trouver les bons '
                    'angles, les bonnes sources, et de te livrer un digest '
                    'au rythme qui te convient.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFF5D5B5A),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: FacteurColors.veilleLineSoft, width: 1),
            ),
          ),
          child: VeilleCtaButton(
            label: "C'est parti",
            trailingIcon: PhosphorIcons.arrowRight(),
            onPressed: onStart,
          ),
        ),
      ],
    );
  }
}
