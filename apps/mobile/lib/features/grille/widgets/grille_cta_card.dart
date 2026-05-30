import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/grille_provider.dart';
import 'carte_cta.dart';

/// Carte d'entrée de La Grille câblée au provider — à insérer en fin de Tournée.
///
/// `ConsumerStatefulWidget` autonome : watch `grilleProvider` (pré-warm du
/// `GET today`), choisit l'état visuel (neuf / déjà-joué), émet
/// `trackGrilleCtaShown/Tapped` et pousse `/grille`. En loading/erreur, ne rend
/// **rien** (`SizedBox.shrink`) pour ne pas perturber la carte de clôture.
class GrilleCtaCard extends ConsumerStatefulWidget {
  const GrilleCtaCard({super.key});

  @override
  ConsumerState<GrilleCtaCard> createState() => _GrilleCtaCardState();
}

class _GrilleCtaCardState extends ConsumerState<GrilleCtaCard> {
  String? _shownState;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(grilleProvider).value?.today;
    if (today == null) return const SizedBox.shrink();

    final state = today.isFinished ? CarteCtaState.deja : CarteCtaState.neuf;
    final stateLabel = state == CarteCtaState.deja ? 'deja' : 'neuf';

    // Émet « shown » une fois par état affiché.
    if (_shownState != stateLabel) {
      _shownState = stateLabel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(analyticsServiceProvider).trackGrilleCtaShown(state: stateLabel);
        }
      });
    }

    return CarteCta(
      state: state,
      today: today,
      onOpen: () {
        ref.read(analyticsServiceProvider).trackGrilleCtaTapped(state: stateLabel);
        context.pushNamed(RouteNames.grille);
      },
    );
  }
}
