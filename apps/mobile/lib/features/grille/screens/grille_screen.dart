import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../shared/widgets/loaders/editorial_loader_card.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../models/grille_models.dart';
import '../providers/grille_intro_provider.dart';
import '../providers/grille_provider.dart';
import '../repositories/grille_repository.dart';
import '../widgets/azerty_keyboard.dart';
import '../widgets/g_app_bar.dart';
import '../widgets/grille_button.dart';
import '../widgets/grille_deja_joue_view.dart';
import '../widgets/grille_intro_sheet.dart';
import '../widgets/grille_masthead.dart';
import '../widgets/grille_result_view.dart';
import '../widgets/grille_status_line.dart';
import '../widgets/mot_grid.dart';

/// Écran principal de La Grille — aiguille entre Jeu, Résultat et Déjà-joué
/// selon le statut serveur et le flag transitoire `justFinished`.
class GrilleScreen extends ConsumerStatefulWidget {
  const GrilleScreen({super.key});

  @override
  ConsumerState<GrilleScreen> createState() => _GrilleScreenState();
}

class _GrilleScreenState extends ConsumerState<GrilleScreen> {
  /// « Revoir ma grille » depuis l'écran Déjà-joué.
  bool _reviewing = false;
  bool _openTracked = false;
  bool _introChecked = false;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final async = ref.watch(grilleProvider);

    ref.listen<AsyncValue<GrilleState>>(grilleProvider, (prev, next) {
      final data = next.valueOrNull;
      if (data != null && !_openTracked) {
        _openTracked = true;
        ref.read(analyticsServiceProvider).trackGrilleOpened(
              numero: data.today.numero,
              statut: data.today.statut,
            );
      }
      // Intro one-shot : au 1er chargement de données, si jamais vue, on
      // l'affiche une fois puis on la marque comme vue.
      if (data != null && !_introChecked) {
        _introChecked = true;
        _maybeShowIntro();
      }
      final wasFinished = prev?.valueOrNull?.justFinished ?? false;
      if (data != null && data.justFinished && !wasFinished) {
        ref.read(analyticsServiceProvider).trackGrilleCompleted(
              numero: data.today.numero,
              statut: data.today.statut,
              nbEssais: data.today.nbEssais,
            );
      }
    });

    return Scaffold(
      backgroundColor: c.backgroundPrimary,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: EditorialLoaderCard()),
          error: (e, _) => _buildError(context, e),
          data: (state) => _buildContent(context, state),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    if (error is GrilleNotFoundException) {
      final c = context.facteurColors;
      return Column(
        children: [
          GAppBar(showBack: true, onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Center(
                child: Text(
                  'Pas de grille aujourd’hui — je t’en poste une toute neuve demain matin.',
                  textAlign: TextAlign.center,
                  style: FacteurTypography.bodyLarge(c.textSecondary),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return FriendlyErrorView(
      error: error,
      onRetry: () => ref.read(grilleProvider.notifier).refresh(),
    );
  }

  /// Affiche l'intro « Comment jouer » une seule fois (1er lancement).
  Future<void> _maybeShowIntro() async {
    final seen = await ref.read(grilleIntroSeenProvider.future);
    if (seen || !mounted) return;
    await _openIntro();
    await markGrilleIntroSeen();
    ref.invalidate(grilleIntroSeenProvider);
  }

  /// Ouvre l'intro à la demande (icône « ? »).
  Future<void> _openIntro() async {
    if (!mounted) return;
    await GrilleIntroSheet.show(context);
  }

  /// Soumet la ligne en cours + trace l'évènement (chemin commun à
  /// l'auto-validation et à la touche « Entrer »).
  void _submitGuess(GrilleTodayResponse today) {
    final notifier = ref.read(grilleProvider.notifier);
    final essai = today.nbEssais + 1;
    notifier.submitGuess().then((_) {
      if (!mounted) return;
      final after = ref.read(grilleProvider).valueOrNull;
      ref.read(analyticsServiceProvider).trackGrilleGuessSubmitted(
            numero: today.numero,
            essai: essai,
            valide: after?.invalidReason == null,
            raison: after?.invalidReason,
          );
    });
  }

  Widget _buildContent(BuildContext context, GrilleState state) {
    final today = state.today;
    if (!today.isFinished) {
      return _buildJeu(context, state);
    }
    final showResult = state.justFinished || _reviewing;
    if (showResult) {
      return _buildResult(context, state);
    }
    return _buildDejaJoue(context, today);
  }

  // ── Phase Jeu ────────────────────────────────────────────────────────────
  Widget _buildJeu(BuildContext context, GrilleState state) {
    final today = state.today;
    final notifier = ref.read(grilleProvider.notifier);
    final keyboardStates = ref.watch(grilleKeyboardStatesProvider);

    return Column(
      children: [
        GAppBar(showBack: true, streak: today.streak, onHelp: _openIntro),
        GrilleMasthead(
          numero: today.numero,
          date: today.dateAffichee,
          longueur: today.longueur,
          premiereLettre: today.premiereLettre,
          essaisMax: today.essaisMax,
          essai: today.nbEssais + 1,
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MotGrid(
                longueur: today.longueur,
                essaisMax: today.essaisMax,
                premiereLettre: today.premiereLettre,
                essais: today.essais,
                draft: state.draft,
                revealRow: state.revealRow,
                shakeNonce: state.invalidNonce,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          child: Column(
            children: [
              GrilleStatusLine(
                message: _statusMessage(state),
                isError: state.invalidReason != null,
              ),
              const SizedBox(height: 10),
              AzertyKeyboard(
                states: keyboardStates,
                enabled: !state.submitting,
                onKey: (k) {
                  notifier.addLetter(k);
                  // Auto-validation : dès que le mot est complet, on soumet
                  // sans passer par « Entrer ».
                  final s = ref.read(grilleProvider).valueOrNull;
                  if (s != null &&
                      !s.submitting &&
                      !s.today.isFinished &&
                      s.draft.length == s.today.longueur) {
                    _submitGuess(s.today);
                  }
                },
                onBackspace: notifier.removeLetter,
                onEnter: () => _submitGuess(today),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusMessage(GrilleState state) {
    switch (state.invalidReason) {
      case 'longueur':
        return 'Tape les ${state.today.longueur} lettres.';
      case 'hors_dictionnaire':
        return 'Ce mot n’est pas distribué — essaie un autre.';
      default:
        return 'Première lettre offerte — le mot part dès la dernière lettre.';
    }
  }

  // ── Phase Résultat ───────────────────────────────────────────────────────
  Widget _buildResult(BuildContext context, GrilleState state) {
    return Column(
      children: [
        GAppBar(showBack: true, streak: state.today.streak),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: GrilleResultView(
              today: state.today,
              animateReveal: state.justFinished,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: Column(
            children: [
              GrilleButton(
                label: 'Partager ma grille',
                icon: PhosphorIcons.shareNetwork(),
                onPressed: () => context.pushNamed(RouteNames.grilleShare),
              ),
              const SizedBox(height: 4),
              GrilleButton(
                label: 'Voir le classement du jour',
                style: GrilleButtonStyle.ghost,
                onPressed: () => context.pushNamed(RouteNames.grilleLeaderboard),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Phase Déjà-joué ──────────────────────────────────────────────────────
  Widget _buildDejaJoue(BuildContext context, GrilleTodayResponse today) {
    return Column(
      children: [
        GAppBar(showBack: true, streak: today.streak),
        Expanded(child: GrilleDejaJoueView(today: today)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          child: GrilleButton(
            label: 'Revoir ma grille du jour',
            style: GrilleButtonStyle.ghost,
            onPressed: () => setState(() => _reviewing = true),
          ),
        ),
      ],
    );
  }
}
