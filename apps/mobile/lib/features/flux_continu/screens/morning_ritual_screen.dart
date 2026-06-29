import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:facteur/config/constants.dart';
import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/feed/widgets/profile_avatar_button.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/morning_ritual_qa_provider.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/flux_continu/widgets/tournee_composer_sheet.dart';
import 'package:facteur/features/gamification/widgets/streak_indicator.dart';
import 'package:facteur/shared/widgets/loaders/loading_view.dart';
import 'package:facteur/widgets/design/facteur_logo.dart';

/// Rituel matinal « Ton édition vient d'arriver » (Story 28.1, finition 28.2).
///
/// Enchaînement (le même pour l'ouverture quotidienne **et** la sortie
/// d'onboarding) :
///
/// ```
/// LOADER (enveloppe + citation, le temps que l'édition se calcule)
///   → RITUEL (greeting + sommaire qui se peuple à cadence régulière)
///   → glisse vers le haut → SLIDE HAUT → FEED (déjà préchargé, zéro loader)
/// ```
///
/// Le loader **précède** le rituel : il achète le temps de calcul des thèmes,
/// si bien qu'au moment où le rituel s'affiche la majorité des chips sont
/// prêtes et cascadent vite. Si l'édition n'est pas prête au plafond
/// ([_maxWaitFor]), on file au feed **sans** marquer « vu » (décision PO #4 :
/// le rituel revient au prochain open).
class MorningRitualScreen extends ConsumerStatefulWidget {
  /// Sortie d'onboarding : l'édition est calculée *à froid* (plus lente qu'un
  /// matin où le flux est préchargé au boot) → plafond du loader élargi pour
  /// garantir l'affichage du rituel plutôt qu'un skip vers le feed.
  final bool fromOnboarding;

  const MorningRitualScreen({super.key, this.fromOnboarding = false});

  @override
  ConsumerState<MorningRitualScreen> createState() =>
      _MorningRitualScreenState();
}

enum _Phase { loading, ritual, exiting }

class _MorningRitualScreenState extends ConsumerState<MorningRitualScreen>
    with SingleTickerProviderStateMixin {
  /// Plancher d'ambiance du loader d'intro (le temps que les thèmes se
  /// calculent et que les chips soient prêtes à cascader vite).
  static const Duration _introFloor = Duration(milliseconds: 2200);

  /// Délai d'apparition de la citation éditoriale dans le loader.
  static const Duration _editorialReveal = Duration(milliseconds: 600);

  /// Plafond de résilience : au-delà, repli vers le feed sans marquer « vu ».
  /// Plus large en sortie d'onboarding (édition calculée à froid).
  Duration get _maxWaitFor =>
      widget.fromOnboarding ? const Duration(seconds: 10) : const Duration(seconds: 6);

  Timer? _floorTimer;
  Timer? _maxWaitTimer;
  late final DateTime _mountedAt;

  late final AnimationController _exitController;
  late final Animation<Offset> _slideOut;
  late final Animation<double> _fadeOut;

  _Phase _phase = _Phase.loading;
  bool _floorElapsed = false;
  bool _editionReady = false;
  bool _shownTracked = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    _floorTimer = Timer(_introFloor, () {
      _floorElapsed = true;
      _maybeReveal();
    });
    _maxWaitTimer = Timer(_maxWaitFor, _forwardIfNotReady);
    _exitController = AnimationController(
      vsync: this,
      duration: FacteurDurations.slow,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishOpen();
      });
    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1),
    ).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOutCubic),
    );
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _floorTimer?.cancel();
    _maxWaitTimer?.cancel();
    _exitController.dispose();
    super.dispose();
  }

  /// Révèle le rituel dès que les deux conditions sont réunies : édition prête
  /// **et** plancher d'ambiance écoulé (ou reduceMotion → immédiat).
  void _maybeReveal({bool reduceMotion = false}) {
    if (!mounted || _phase != _Phase.loading) return;
    if (_editionReady && (_floorElapsed || reduceMotion)) {
      _revealRitual();
    }
  }

  void _revealRitual() {
    if (!mounted || _phase != _Phase.loading) return;
    _maxWaitTimer?.cancel();
    _floorTimer?.cancel();
    if (!_shownTracked) {
      _shownTracked = true;
      unawaited(ref.read(analyticsServiceProvider).trackMorningRitualShown(
            dayKey: TourneeProgressService.dayKey(DateTime.now()),
          ));
      // « Vu » dès la **révélation** (et non au tap CTA) : si l'utilisateur
      // quitte sans ouvrir puis se reconnecte le même jour, l'enveloppe ne
      // réapparaît pas. (Décision PO #4 préservée : le repli « pas prête »
      // — `_forwardIfNotReady` — ne marque toujours pas « vu ».)
      unawaited(
        ref.read(tourneeProgressServiceProvider).setMorningRitualShownToday(),
      );
    }
    setState(() => _phase = _Phase.ritual);
  }

  /// Plafond atteint sans édition prête : repli vers le feed **sans** marquer
  /// « vu » (le rituel revient au prochain open — décision PO #4).
  void _forwardIfNotReady() {
    if (!mounted || _phase != _Phase.loading) return;
    unawaited(
      ref.read(analyticsServiceProvider).trackMorningRitualSkippedNotReady(
            dayKey: TourneeProgressService.dayKey(DateTime.now()),
          ),
    );
    _go(RoutePaths.fluxContinu);
  }

  void _trackOpened() {
    unawaited(ref.read(analyticsServiceProvider).trackMorningRitualOpened(
          dayKey: TourneeProgressService.dayKey(DateTime.now()),
          waitedMs: DateTime.now().difference(_mountedAt).inMilliseconds,
        ));
  }

  /// Tap (enveloppe ou indice) : slide doux vers le haut, puis feed (déjà
  /// préchargé → arrivée instantanée). reduceMotion → go direct.
  void _open() {
    if (_phase == _Phase.exiting) return;
    if (MediaQuery.of(context).disableAnimations) {
      _trackOpened();
      _finishOpen();
      return;
    }
    _commitOpen();
  }

  /// Lance la sortie (slide haut) depuis la position courante du contrôleur —
  /// utilisé par le tap **et** par la fin d'un balayage qui franchit le seuil.
  void _commitOpen() {
    if (_phase == _Phase.exiting) return;
    _trackOpened();
    setState(() => _phase = _Phase.exiting);
    _exitController.forward();
  }

  /// Balayage **progressif** : la page suit le doigt en temps réel (le
  /// contrôleur de sortie est piloté à la main, 0 = repos, 1 = sortie complète).
  void _onDragUpdate(DragUpdateDetails details) {
    if (_phase == _Phase.exiting) return;
    if (MediaQuery.of(context).disableAnimations) return;
    // Distance de référence pour une sortie complète : ~40 % de la hauteur.
    final target = MediaQuery.of(context).size.height * 0.4;
    if (target <= 0) return;
    final delta = -(details.primaryDelta ?? 0) / target; // vers le haut → +
    _exitController.value = (_exitController.value + delta).clamp(0.0, 1.0);
  }

  /// Relâché : franchit-on le seuil (progression > 30 % ou fling vers le haut) ?
  /// Oui → on termine la sortie ; non → retour élastique à la position de repos.
  void _onDragEnd(DragEndDetails details) {
    if (_phase == _Phase.exiting) return;
    final velocity = details.primaryVelocity ?? 0; // négatif = vers le haut
    final commit = velocity < -300 || _exitController.value > 0.3;
    if (!commit) {
      _exitController.reverse();
      return;
    }
    if (MediaQuery.of(context).disableAnimations) {
      _trackOpened();
      _finishOpen();
      return;
    }
    _commitOpen();
  }

  void _finishOpen() {
    if (_navigated || !mounted) return;
    _navigated = true;
    // Le flag « vu » est déjà posé à la révélation (cf. _revealRitual) → pas
    // d'await ici, on file au feed sans délai.
    context.go(RoutePaths.fluxContinu);
  }

  void _go(String path) {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final fluxState = ref.watch(fluxContinuProvider).valueOrNull;
    final digest = ref.watch(digestProvider).valueOrNull;
    // Override QA (staging/dev) : permet de valider l'état « pas prête » à la
    // demande. Sans effet en prod (le toggle qui le bascule n'y est pas monté).
    final forceNotReady = ref.watch(debugForceMorningRitualNotReadyProvider);
    final gateReady = isEditionReady(fluxState, digest);
    final ready = !forceNotReady && gateReady;

    // « Connu pas-prêt » : on SAIT que le rituel ne se révélera pas — soit le
    // toggle QA force le repli, soit le flux a chargé du contenu réel
    // (non-skeleton, sections non vides) mais le gate le refuse (digest périmé /
    // mauvais jour). Tant que le flux est encore skeleton/null, l'état reste
    // « inconnu » (vrai chargement) → on n'éteint rien (flux matin nominal).
    final fluxLoaded =
        fluxState != null && !fluxState.isSkeleton && fluxState.sections.isNotEmpty;
    final knownNotReady = forceNotReady || (fluxLoaded && !gateReady);

    // Suit l'état du gate ; déclenche la révélation hors-build (post-frame)
    // pour ne jamais appeler setState pendant le build.
    if (_phase == _Phase.loading) {
      _editionReady = ready;
      if (ready && (_floorElapsed || reduceMotion)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeReveal(reduceMotion: reduceMotion);
        });
      }
    } else if (_phase == _Phase.ritual && forceNotReady) {
      // Le rituel est déjà révélé mais le toggle QA « pas prête » est basculé sur
      // une instance d'écran conservée en mémoire → on file au feed pour que la
      // QA puisse rejouer le repli sans reload. Restreint à `forceNotReady` (pas
      // au `knownNotReady` général) : un digest périmé arrivant *après* la
      // révélation ne doit pas éjecter l'utilisateur d'un rituel déjà ouvert.
      // Inerte en prod (le toggle n'y est jamais monté).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == _Phase.ritual) _go(RoutePaths.fluxContinu);
      });
    }

    // Diagnostic QA (staging/dev) : trace le détail du gate à chaque rebuild
    // pour identifier sur l'appareil le maillon qui bloque la révélation.
    const qaMode = kDebugMode || AppUpdateConstants.updateChannel == 'beta';
    final readinessDebug =
        qaMode ? morningRitualReadinessDebug(fluxState, digest) : null;
    if (readinessDebug != null) {
      debugPrint('MorningRitual gate · $readinessDebug · force=$forceNotReady');
    }

    Widget body;
    if (_phase == _Phase.loading) {
      body = _IntroLoader(
        key: const ValueKey('morning-loader'),
        revealEditorialAfter: _editorialReveal,
        // Dans le flux « connu pas-prêt » (repli vers le feed), on n'affiche pas
        // l'enveloppe : ce n'est pas un rituel, juste un court loader transitoire.
        showEnvelope: !knownNotReady,
      );
    } else {
      // Sommaire calculé seulement en phase rituel : inutile sous le loader (qui
      // ne l'affiche pas) et sinon recalculé à chaque émission flux/digest.
      final editionDate = digest?.targetDate ?? DateTime.now();
      final entries = fluxState == null
          ? const <EditionSummaryEntry>[]
          : editionSummaryEntries(
              fluxState.sections,
              grilleSlotIndex: fluxState.grilleSlotIndex,
            );
      Widget ritual = _RitualBody(
        key: const ValueKey('morning-ritual'),
        dateLabel: formatFrenchLongDate(editionDate),
        entries: entries,
        reduceMotion: reduceMotion,
        onOpen: _open,
        onPersonalize: () => showTourneeComposerSheet(context),
      );
      // Balayage vers le haut (n'importe où sur le rituel) qui **suit le doigt**.
      // Le tap sur l'enveloppe ou l'indice reste un repli accessible (cf. onOpen).
      ritual = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: ritual,
      );
      // Transition pilotée par `_exitController` en continu : à la valeur 0 elle
      // est neutre (offset zéro, opacité pleine), ce qui permet au balayage de la
      // faire progresser en temps réel avant tout `forward()`.
      ritual = SlideTransition(
        position: _slideOut,
        child: FadeTransition(opacity: _fadeOut, child: ritual),
      );
      body = ritual;
    }

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : FacteurDurations.medium,
            child: body,
          ),
          if (readinessDebug != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Text(
                  'QA · $readinessDebug${forceNotReady ? " · FORCED-NOT-READY" : ""}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    color: Color(0xFF9E9E9E),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Loader d'intro du rituel : enveloppe (centrepiece cohérent loader ↔ rituel)
/// **en tête de la colonne centrée** du [LoadingView] (FacteurLoader + citation
/// éditoriale), au lieu d'être épinglée en haut — l'enveloppe et le loader
/// forment ainsi un seul bloc vertical-centré, à une hauteur proche de celle du
/// rituel révélé (plus de double-centre ni de saut de position entre les deux
/// phases). Couvre le temps de calcul des thèmes de l'édition.
class _IntroLoader extends StatelessWidget {
  final Duration revealEditorialAfter;

  /// Affiche l'enveloppe en tête du loader (centrepiece cohérent loader ↔
  /// rituel). Désactivé dans le flux « connu pas-prêt » : pas de rituel à venir,
  /// donc pas d'enveloppe — juste un court loader avant le repli vers le feed.
  final bool showEnvelope;

  const _IntroLoader({
    super.key,
    required this.revealEditorialAfter,
    this.showEnvelope = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RitualHeader(),
          Expanded(
            // Enveloppe décorative (onTap null) en tête de la colonne centrée du
            // loader : même bloc que le FacteurLoader + citation.
            child: LoadingView(
              revealEditorialAfter: revealEditorialAfter,
              leading: showEnvelope ? const _EnvelopeHero() : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RitualBody extends StatelessWidget {
  final String dateLabel;
  final List<EditionSummaryEntry> entries;
  final bool reduceMotion;
  final VoidCallback onOpen;
  final VoidCallback onPersonalize;

  const _RitualBody({
    super.key,
    required this.dateLabel,
    required this.entries,
    required this.reduceMotion,
    required this.onOpen,
    required this.onPersonalize,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _RitualHeader(),
          Expanded(
            child: MorningRitualContent(
              dateLabel: dateLabel,
              entries: entries,
              reduceMotion: reduceMotion,
              onOpen: onOpen,
              onPersonalize: onPersonalize,
            ),
          ),
        ],
      ),
    );
  }
}

/// Corps du rituel **sans** le header (logo/streak/avatar) — greeting + sommaire
/// + CTA. Provider-free et donc directement testable en widget test, sans avoir
/// à monter les providers du header (streak/profil/lettres).
///
/// Le sommaire est rendu dès que [entries] est non vide : le rituel n'est
/// affiché qu'une fois l'édition prête (le gate vit désormais dans le loader),
/// donc plus de double gate ici — les chips se peuplent au fil des sections.
class MorningRitualContent extends StatelessWidget {
  final String dateLabel;
  final List<EditionSummaryEntry> entries;
  final bool reduceMotion;
  final VoidCallback onOpen;
  final VoidCallback onPersonalize;

  const MorningRitualContent({
    super.key,
    required this.dateLabel,
    required this.entries,
    required this.reduceMotion,
    required this.onOpen,
    required this.onPersonalize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Greeting + enveloppe : instantanés (jamais gatés par les données).
          Text(
            'Salut,',
            textAlign: TextAlign.center,
            style: FacteurTypography.serifTitle(colors.textPrimary)
                .copyWith(fontSize: 30, height: 1.1),
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            'Ton essentiel du $dateLabel t\'attend.',
            textAlign: TextAlign.center,
            style: FacteurTypography.bodyLarge(colors.textSecondary),
          ),
          const SizedBox(height: FacteurSpacing.space6),
          _EnvelopeHero(onTap: onOpen),
          const SizedBox(height: FacteurSpacing.space6),
          _SwipeUpHint(onTap: onOpen, reduceMotion: reduceMotion),
          const SizedBox(height: FacteurSpacing.space8),
          _EditionSummary(
            entries: entries,
            reduceMotion: reduceMotion,
            onPersonalize: onPersonalize,
          ),
        ],
      ),
    );
  }
}

/// Indice d'ouverture : chevron vers le haut + libellé, animé d'un va-et-vient
/// vertical doux (nudge) qui invite à **glisser vers le haut**. Tape = repli
/// accessible (ouvre aussi). `reduceMotion` → statique, sans boucle.
class _SwipeUpHint extends StatefulWidget {
  final VoidCallback onTap;
  final bool reduceMotion;

  const _SwipeUpHint({required this.onTap, required this.reduceMotion});

  @override
  State<_SwipeUpHint> createState() => _SwipeUpHintState();
}

class _SwipeUpHintState extends State<_SwipeUpHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bob;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _bob = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (!widget.reduceMotion) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: 'Ouvrir mon essentiel',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bob,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, -6 * _bob.value),
                child: Opacity(opacity: 0.5 + 0.5 * _bob.value, child: child),
              ),
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 34,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space1),
            Text(
              'Glisse vers le haut',
              style: FacteurTypography.labelLarge(colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header léger (mêmes widgets que `_SharedTopHeader` mais décoratif : l'avatar
/// n'ouvre pas les réglages pendant le rituel).
class _RitualHeader extends StatelessWidget {
  const _RitualHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space6,
        vertical: FacteurSpacing.space3,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          FacteurLogo(size: 22, showIcon: false),
          Align(
            alignment: Alignment.centerLeft,
            child: StreakIndicator(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ProfileAvatarButton.display(),
          ),
        ],
      ),
    );
  }
}

/// Aperçu de l'édition : phrase grisée d'intro, chips colorées des sections
/// (+ chip « Ma veille » à étoile) **qui se peuplent une à une**, suivies de
/// l'engrenage de personnalisation, sur un filigrane facteur discret, puis
/// « Reçue à 7h00 ».
class _EditionSummary extends StatelessWidget {
  final List<EditionSummaryEntry> entries;
  final bool reduceMotion;
  final VoidCallback onPersonalize;

  const _EditionSummary({
    required this.entries,
    required this.reduceMotion,
    required this.onPersonalize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tu y trouveras le meilleur de...',
          textAlign: TextAlign.center,
          style: FacteurTypography.bodyMedium(colors.textSecondary),
        ),
        const SizedBox(height: FacteurSpacing.space3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Stack(
            children: [
              // Filigrane facteur (asset existant) derrière les chips.
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.15,
                    child: Image.asset(
                      'assets/notifications/facteur_bike.png',
                      width: 124,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              _PopulatingChips(
                entries: entries,
                reduceMotion: reduceMotion,
                onPersonalize: onPersonalize,
              ),
            ],
          ),
        ),
        const SizedBox(height: FacteurSpacing.space3),
        Text(
          'Reçue à 7h00',
          style: FacteurTypography.bodySmall(colors.textTertiary),
        ),
      ],
    );
  }
}

/// Wrap de chips qui se révèlent **une à une, à cadence régulière** (~500 ms),
/// comme si la lettre du jour s'écrivait. Le rythme est **découplé des salves
/// du flux** : peu importe que les sections arrivent groupées (squelette → base
/// → complet), une pompe interne en révèle exactement une par intervalle, dans
/// l'ordre du feed. L'engrenage de personnalisation est révélé **après** la
/// dernière chip. `reduceMotion` → tout apparaît immédiatement, sans cadence.
class _PopulatingChips extends StatefulWidget {
  final List<EditionSummaryEntry> entries;
  final bool reduceMotion;
  final VoidCallback onPersonalize;

  const _PopulatingChips({
    required this.entries,
    required this.reduceMotion,
    required this.onPersonalize,
  });

  @override
  State<_PopulatingChips> createState() => _PopulatingChipsState();
}

class _PopulatingChipsState extends State<_PopulatingChips> {
  /// Clé interne de l'engrenage (révélé en dernier, après les chips).
  static const String _gearKey = ' gear';

  /// Cadence régulière entre deux révélations : un thème toutes les ~500 ms,
  /// quel que soit l'ordre/la salve d'arrivée des sections. Volontairement posée
  /// et sereine — « la lettre du jour qui s'écrit ».
  static const Duration _revealInterval = Duration(milliseconds: 500);

  final Set<String> _revealed = <String>{};
  Timer? _pump;

  @override
  void initState() {
    super.initState();
    if (widget.reduceMotion) {
      _revealAll();
      return;
    }
    // 1re chip tout de suite (pré-build, donc sans `setState`), puis la pompe
    // prend le relais à cadence régulière.
    final first = _firstPending();
    if (first != null) _revealed.add(first);
    _scheduleNext();
  }

  @override
  void didUpdateWidget(_PopulatingChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      setState(_revealAll);
      return;
    }
    // De nouvelles sections sont peut-être arrivées : relance la pompe si elle
    // était au repos (le garde anti-doublon évite d'empiler deux timers).
    _scheduleNext();
  }

  @override
  void dispose() {
    _pump?.cancel();
    super.dispose();
  }

  void _revealAll() {
    for (final e in widget.entries) {
      _revealed.add(e.label);
    }
    _revealed.add(_gearKey);
  }

  /// Prochaine clé à révéler, dans l'ordre du feed (sections d'abord, engrenage
  /// en dernier). `null` quand tout est déjà révélé.
  String? _firstPending() {
    for (final e in widget.entries) {
      if (!_revealed.contains(e.label)) return e.label;
    }
    if (!_revealed.contains(_gearKey)) return _gearKey;
    return null;
  }

  void _scheduleNext() {
    if (_pump?.isActive ?? false) return;
    if (_firstPending() == null) {
      _pump = null;
      return;
    }
    _pump = Timer(_revealInterval, () {
      _pump = null;
      if (!mounted) return;
      final next = _firstPending();
      if (next != null) setState(() => _revealed.add(next));
      _scheduleNext();
    });
  }

  @override
  Widget build(BuildContext context) {
    final animate = !widget.reduceMotion;
    final chips = <Widget>[
      for (final entry in widget.entries)
        if (_revealed.contains(entry.label))
          _ChipReveal(
            key: ValueKey('chip-${entry.label}'),
            animate: animate,
            child: _SectionChip(entry: entry),
          ),
      if (_revealed.contains(_gearKey))
        _ChipReveal(
          key: const ValueKey('chip-gear'),
          animate: animate,
          child: _GearChip(onTap: widget.onPersonalize),
        ),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: chips,
    );
  }
}

/// Apparition d'une chip : fade + léger scale (0.92→1, easeOutBack) + translate
/// vers le haut, jouée une seule fois au montage. `animate: false` → rendu nu.
class _ChipReveal extends StatelessWidget {
  final Widget child;
  final bool animate;

  const _ChipReveal({super.key, required this.child, required this.animate});

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutBack,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// Chip d'une section du sommaire : pastille colorée (`accent`) + libellé.
/// Variante veille : étoile `primary` + libellé `w600` + fond `primary`.
class _SectionChip extends StatelessWidget {
  final EditionSummaryEntry entry;

  const _SectionChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isVeille = entry.isVeille;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isVeille
            ? colors.primary.withValues(alpha: 0.09)
            : entry.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isVeille)
            Icon(Icons.star, size: 11, color: colors.primary)
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: entry.accent,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 5),
          Text(
            entry.label,
            style: FacteurTypography.labelLarge(colors.textPrimary).copyWith(
              fontSize: 12.5,
              height: 1.0,
              fontWeight: isVeille ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Engrenage de personnalisation en fin de chips → ouvre « Composer ma Tournée ».
class _GearChip extends StatelessWidget {
  final VoidCallback onTap;

  const _GearChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: 'Personnaliser ma Tournée',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.tune, size: 17, color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// Enveloppe du jour — centrepiece du rituel. SVG d'enveloppe cachetée (papier
/// crème, rabat, timbre pointillé, cachet de cire `primary`) avec un « F »
/// Fraunces superposé pour un rendu net, et une ombre portée discrète.
///
/// Quand [onTap] est fourni (phase rituel), l'enveloppe est **cliquable** : un
/// appui l'enfonce légèrement (haptique « cachet »), et au relâché elle rebondit
/// — un petit « pop » satisfaisant — avant de filer au feed via [onTap]. Sans
/// [onTap] (loader), elle est purement décorative.
class _EnvelopeHero extends StatefulWidget {
  final VoidCallback? onTap;

  const _EnvelopeHero({this.onTap});

  static const double _width = 236;
  static const double _height = _width * 188 / 260; // ≈ 170.6

  @override
  State<_EnvelopeHero> createState() => _EnvelopeHeroState();
}

class _EnvelopeHeroState extends State<_EnvelopeHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;
  late final Animation<double> _pressCurve;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
      reverseDuration: const Duration(milliseconds: 320),
    );
    // Enfoncement net à l'appui, rebond (léger dépassement) au relâché.
    _pressCurve = CurvedAnimation(
      parent: _press,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _press.forward();
  void _onTapCancel() => _press.reverse();
  void _onTapUp(TapUpDetails _) {
    HapticFeedback.heavyImpact();
    _press.reverse();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final envelope = SizedBox(
      width: _EnvelopeHero._width,
      height: _EnvelopeHero._height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ombre portée discrète sous l'enveloppe.
          Container(
            margin: const EdgeInsets.fromLTRB(10, 14, 10, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
          ),
          SvgPicture.string(
            _envelopeSvg(_hex(colors.primary)),
            width: _EnvelopeHero._width,
            height: _EnvelopeHero._height,
          ),
          // Cachet « F » net (la lettre est retirée du SVG et superposée ici).
          Align(
            alignment: const Alignment(0, 0.13),
            child: Text(
              'F',
              style: FacteurTypography.serifTitle(Colors.white)
                  .copyWith(fontSize: 26, height: 1.0),
            ),
          ),
        ],
      ),
    );

    if (widget.onTap == null) return envelope;

    return Semantics(
      button: true,
      label: 'Ouvrir mon essentiel',
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: _pressCurve,
          builder: (context, child) => Transform.scale(
            scale: 1 - 0.06 * _pressCurve.value,
            child: child,
          ),
          child: envelope,
        ),
      ),
    );
  }
}

/// Hex `#RRGGBB` d'une [Color] pour injection dans la chaîne SVG (le thème
/// n'étant pas lisible depuis `SvgPicture.string`, on remplace `var(--primary)`
/// par la valeur réelle — gère aussi le dark mode).
String _hex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// SVG de l'enveloppe cachetée (maquette `01 - Hook.html`, viewBox 0 0 260 188).
/// [primary] injecté pour le timbre et le cachet de cire (les 2 `var(--primary)`
/// d'origine).
String _envelopeSvg(String primary) => '''
<svg viewBox="0 0 260 188" xmlns="http://www.w3.org/2000/svg">
  <rect x="6" y="14" width="248" height="160" rx="12" ry="12"
        fill="#FCF8F0" stroke="rgba(60,40,20,0.28)" stroke-width="1.5"/>
  <path d="M 6 14 L 130 104 L 254 14" fill="none"
        stroke="rgba(60,40,20,0.28)" stroke-width="1.5" stroke-linejoin="miter"/>
  <path d="M 6 14 L 130 104 L 130 14 Z" fill="rgba(60,40,20,0.04)"/>
  <line x1="40" y1="134" x2="118" y2="134" stroke="rgba(60,40,20,0.20)" stroke-width="2" stroke-linecap="round"/>
  <line x1="40" y1="148" x2="152" y2="148" stroke="rgba(60,40,20,0.20)" stroke-width="2" stroke-linecap="round"/>
  <line x1="40" y1="162" x2="96" y2="162" stroke="rgba(60,40,20,0.20)" stroke-width="2" stroke-linecap="round"/>
  <rect x="200" y="30" width="34" height="28" fill="$primary" stroke="#FCF8F0"
        stroke-width="2" stroke-dasharray="3 3"/>
  <circle cx="217" cy="44" r="5" fill="#FCF8F0" opacity="0.85"/>
  <circle cx="130" cy="106" r="28" fill="$primary"/>
  <circle cx="130" cy="106" r="28" fill="none" stroke="rgba(0,0,0,0.12)" stroke-width="2"/>
</svg>''';
