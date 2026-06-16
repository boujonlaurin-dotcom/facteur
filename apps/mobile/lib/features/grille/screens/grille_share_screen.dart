import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../models/grille_models.dart';
import '../providers/grille_provider.dart';
import '../utils/grille_share_text.dart';
import '../widgets/g_app_bar.dart';
import '../widgets/grille_button.dart';
import '../widgets/grille_share_card.dart';

/// Écran de partage (`GMotPartage`). MVP : **texte + lien via Clipboard**
/// (built-in, aucune dépendance `share_plus`). La feuille reste affichée à
/// l'écran ; l'export image (chip « Image ») est différé en follow-up.
class GrilleShareScreen extends ConsumerWidget {
  const GrilleShareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.facteurColors;
    final today = ref.watch(grilleProvider).valueOrNull?.today;

    return Scaffold(
      backgroundColor: c.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            const GAppBar(showBack: true),
            Expanded(
              child: today == null
                  ? const SizedBox.shrink()
                  : _buildBody(context, ref, today),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, GrilleTodayResponse today) {
    final c = context.facteurColors;
    final score = grilleShareScore(today);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.frameCorners(),
                      size: 14,
                      color: c.textTertiary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'VOICI L’IMAGE PARTAGÉE',
                      style: GoogleFonts.courierPrime(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: c.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                GrilleShareCard(
                  numero: today.numero,
                  dateCourt: today.dateCourt,
                  score: score,
                  essais: today.essais,
                ),
                const SizedBox(height: 20),
                _targets(context, ref, today),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            children: [
              GrilleButton(
                label: 'Partager',
                icon: PhosphorIcons.shareNetwork(),
                onPressed: () => _shareText(context, ref, today),
              ),
              const SizedBox(height: 4),
              GrilleButton(
                label: 'Défier un·e ami·e',
                style: GrilleButtonStyle.ghost,
                onPressed: () => _shareLink(context, ref, today),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Chips de partage. « Image » est masquée (export différé) → Texte · Lien.
  Widget _targets(BuildContext context, WidgetRef ref, GrilleTodayResponse today) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _chip(
          context,
          icon: PhosphorIcons.textT(),
          label: 'Texte',
          onTap: () => _shareText(context, ref, today),
        ),
        const SizedBox(width: 10),
        _chip(
          context,
          icon: PhosphorIcons.link(),
          label: 'Lien',
          onTap: () => _shareLink(context, ref, today),
        ),
      ],
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final c = context.facteurColors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(FacteurRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: c.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: FacteurTypography.labelLarge(c.textSecondary)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareText(
      BuildContext context, WidgetRef ref, GrilleTodayResponse today) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: buildGrilleShareText(today)));
    unawaited(ref.read(analyticsServiceProvider).trackGrilleShared(
          numero: today.numero,
          medium: 'texte',
        ));
    messenger.showSnackBar(
      const SnackBar(content: Text('Grille copiée — colle-la où tu veux !')),
    );
  }

  Future<void> _shareLink(
      BuildContext context, WidgetRef ref, GrilleTodayResponse today) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: buildGrilleShareLink(today)));
    unawaited(ref.read(analyticsServiceProvider).trackGrilleShared(
          numero: today.numero,
          medium: 'lien',
        ));
    messenger.showSnackBar(
      const SnackBar(content: Text('Lien copié — défie un·e ami·e !')),
    );
  }
}
