import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_stamp.dart';
import '../../soutien/providers/premium_gate_provider.dart';
import '../../soutien/soutien_copy.dart';
import '../widgets/veille_widgets.dart';

/// Écran d'introduction au flow Veille — affiché au premier accès
/// (pas de config active, pas de mode édition). Cadre le pitch avant
/// le wizard en 3 étapes.
///
/// La création de veille est réservée aux Fact·eur·isses : pour les free,
/// le CTA est verrouillé et mène au mur veille (porte 2 du Soutien).
class VeilleIntroScreen extends ConsumerWidget {
  final VoidCallback onClose;
  final VoidCallback onStart;

  const VeilleIntroScreen({
    super.key,
    required this.onClose,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canCreate =
        ref.watch(premiumGateProvider.select((g) => g.canCreateVeille));
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
                const SizedBox(height: 40),
                Icon(
                  PhosphorIcons.binoculars(PhosphorIconsStyle.duotone),
                  size: 72,
                  color: const Color(0xFF2C3E50),
                ),
                const SizedBox(height: 28),
                if (!canCreate) ...[
                  const FacteurStamp(
                    text: SoutienCopy.veilleGateStamp,
                    isNew: true,
                  ),
                  const SizedBox(height: 14),
                ],
                const VeilleAiEyebrow('Ta veille personnalisée'),
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
                    'Configure une veille sur-mesure — elle s\'ajoutera à '
                    'ta Tournée du jour avec ses propres sujets, sources et '
                    'angles.',
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
          child: canCreate
              ? VeilleCtaButton(
                  label: "C'est parti",
                  trailingIcon: PhosphorIcons.arrowRight(),
                  onPressed: onStart,
                )
              : VeilleCtaButton(
                  label: SoutienCopy.veilleGateCta,
                  leadingIcon: PhosphorIcons.lockSimple(),
                  onPressed: () => context.pushNamed(RouteNames.veilleWall),
                ),
        ),
      ],
    );
  }
}
