import 'dart:async';

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
import '../widgets/grille_victory.dart';
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

  /// Soumet la ligne en cours + trace l'évènement (validation via « Entrée »).
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

    final complete = state.draft.length == today.longueur && !state.submitting;

    return Column(
      children: [
        GAppBar(
          showBack: true,
          streak: today.streak,
          onHelp: _openIntro,
          onReveal: () => _confirmReveal(today),
        ),
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
              // Rappel discret du lien avec l'actu, après 2 essais infructueux.
              if (today.nbEssais >= 2 && !today.isFinished)
                _buildActusHint(context, today),
              const SizedBox(height: 10),
              AzertyKeyboard(
                states: keyboardStates,
                enabled: !state.submitting,
                highlightEnter: complete,
                // Plus d'auto-validation : la saisie n'ajoute que la lettre,
                // la validation se fait uniquement via la touche « Entrée ».
                onKey: notifier.addLetter,
                onBackspace: notifier.removeLetter,
                onEnter: () => _submitGuess(today),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Mini-CTA « le mot est dans l'actu du jour » + lien vers le flux continu.
  Widget _buildActusHint(BuildContext context, GrilleTodayResponse today) {
    final c = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _goToActus(today),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(PhosphorIcons.lightbulb(), size: 13, color: c.textTertiary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Indice : le mot est dans l’actu du jour — ',
                style: FacteurTypography.bodySmall(c.textTertiary)
                    .copyWith(fontSize: 12),
              ),
            ),
            Text(
              'aller lire',
              style: FacteurTypography.bodySmall(c.primary).copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigue vers les Actus du jour (flux continu) + trace l'évènement.
  void _goToActus(GrilleTodayResponse today) {
    ref.read(analyticsServiceProvider).trackGrilleActusTapped(
          numero: today.numero,
        );
    context.go(RoutePaths.fluxContinu);
  }

  /// Confirme « donner sa langue au chat » puis révèle le mot.
  Future<void> _confirmReveal(GrilleTodayResponse today) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Donner sa langue au chat ?'),
        content: const Text(
          'Le mot du jour te sera révélé. Pas de défaite — mais cette grille '
          'ne comptera pas au classement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continuer à jouer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Révéler le mot'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(grilleProvider.notifier).reveal();
    if (!mounted) return;
    unawaited(ref.read(analyticsServiceProvider).trackGrilleRevealed(
          numero: today.numero,
        ));
    // Aiguille vers l'écran Résultat (mode révélé).
    setState(() => _reviewing = true);
  }

  String _statusMessage(GrilleState state) {
    switch (state.invalidReason) {
      case 'longueur':
        return 'Il manque des lettres.';
      case 'hors_dictionnaire':
        return 'Mot absent du dictionnaire.';
      default:
        if (state.draft.length == state.today.longueur) {
          return 'Mot complet ? Appuie sur Entrée pour valider.';
        }
        return 'Première lettre offerte — complète le mot, puis Entrée.';
    }
  }

  // ── Phase Résultat ───────────────────────────────────────────────────────
  Widget _buildResult(BuildContext context, GrilleState state) {
    final today = state.today;
    final revealed = today.isRevealed;
    final won = state.justFinished && today.isSolved;

    return Stack(
      children: [
        Column(
          children: [
            GAppBar(showBack: true, streak: today.streak),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: GrilleResultView(
                  today: today,
                  animateReveal: state.justFinished,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Column(
                children: [
                  GrilleButton(
                    label: 'Lire les actus du jour',
                    icon: PhosphorIcons.newspaper(),
                    onPressed: () => _goToActus(today),
                  ),
                  const SizedBox(height: 4),
                  GrilleButton(
                    label: 'Partager ma grille',
                    style: GrilleButtonStyle.ghost,
                    icon: PhosphorIcons.shareNetwork(),
                    onPressed: () => context.pushNamed(RouteNames.grilleShare),
                  ),
                  // Le classement est masqué pour une grille « langue au chat »
                  // (non classée).
                  if (!revealed) ...[
                    const SizedBox(height: 4),
                    GrilleButton(
                      label: 'Voir le classement du jour',
                      style: GrilleButtonStyle.ghost,
                      onPressed: () =>
                          context.pushNamed(RouteNames.grilleLeaderboard),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (won) const Positioned.fill(child: GrilleVictory(active: true)),
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
