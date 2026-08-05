import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shimmer/shimmer.dart';

import 'package:facteur/config/routes.dart';
import 'package:facteur/config/serein_colors.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/pending_feed_section_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/flux_continu/utils/theme_color_mapping.dart';
import 'package:facteur/features/flux_continu/widgets/edition_timeline_sheet.dart';
import 'package:facteur/features/flux_continu/widgets/manage_favorites_sheet.dart';
import 'package:facteur/features/flux_continu/widgets/my_interests_intro.dart';
import 'package:facteur/features/gamification/providers/streak_celebration_provider.dart';
import 'package:facteur/shared/widgets/loaders/loading_view.dart';

/// Rituel matinal « Ton édition vient d'arriver » (Story 28.1, finition 28.2).
///
/// Enchaînement (le même pour l'ouverture quotidienne **et** la sortie
/// d'onboarding) :
///
/// ```
/// LOADER (enveloppe + citation, plancher d'ambiance ~2,2 s)
///   → RITUEL (greeting + carrousel + sommaire des sections du jour)
///   → glisse vers le haut → SLIDE HAUT → FEED (L'Essentiel)
/// ```
///
/// La lettre est le **point d'entrée strict et unique** vers L'Essentiel : elle
/// se révèle dès la fin du plancher d'ambiance ([_introFloor]) et **jamais** ne
/// file au feed si le contenu tarde (plus de repli/plafond — décision PO). Le
/// sommaire des sections rend l'échafaudage des sections « de base » (favoris +
/// Actus du jour + Bonnes Nouvelles) en shimmer et hydrate en direct.
class MorningRitualScreen extends ConsumerStatefulWidget {
  const MorningRitualScreen({super.key});

  @override
  ConsumerState<MorningRitualScreen> createState() =>
      _MorningRitualScreenState();
}

enum _Phase { loading, ritual, exiting }

class _MorningRitualScreenState extends ConsumerState<MorningRitualScreen>
    with TickerProviderStateMixin {
  /// Plancher d'ambiance du loader d'intro : signature du rituel + laisse le
  /// squelette des sections s'afficher avant la révélation (valeur ajustable).
  static const Duration _introFloor = Duration(milliseconds: 2200);

  /// Délai d'apparition de la citation éditoriale dans le loader.
  static const Duration _editorialReveal = Duration(milliseconds: 600);

  Timer? _floorTimer;
  late final DateTime _mountedAt;

  late final AnimationController _exitController;
  late final Animation<Offset> _slideOut;
  late final Animation<double> _fadeOut;

  _Phase _phase = _Phase.loading;
  bool _shownTracked = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    _floorTimer = Timer(_introFloor, _revealRitual);
    _exitController = AnimationController(
      vsync: this,
      duration: FacteurDurations.slow,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finishOpen();
      });
    final exitCurve = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeInOutCubic,
    );
    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -1),
    ).animate(exitCurve);
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(exitCurve);
  }

  @override
  void dispose() {
    _floorTimer?.cancel();
    _exitController.dispose();
    super.dispose();
  }

  /// Révèle le rituel dès la fin du plancher d'ambiance (ou immédiatement en
  /// reduceMotion). La révélation ne dépend **plus** de l'arrivée du contenu :
  /// le sommaire s'affiche avec l'échafaudage des sections (shimmer) et hydrate
  /// en direct — jamais de saut vers le feed.
  void _revealRitual() {
    if (!mounted || _phase != _Phase.loading) return;
    _floorTimer?.cancel();
    if (!_shownTracked) {
      _shownTracked = true;
      // Trace **analytics seule** : la lettre ne gate plus rien (décision PO
      // 02/08/2026), donc plus aucun flag « vu aujourd'hui » à poser. L'écran
      // n'est atteint qu'en fin d'onboarding ou par le rewind des éditions
      // passées, jamais comme sas quotidien.
      unawaited(ref.read(analyticsServiceProvider).trackMorningRitualShown(
            dayKey: TourneeProgressService.dayKey(DateTime.now()),
          ));
    }
    setState(() => _phase = _Phase.ritual);
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
    // Point de passage **unique** de toutes les ouvertures (CTA / enveloppe /
    // section) : signale au feed que la lettre vient d'être ouverte, pour que la
    // flamme du header y célèbre le streak (grow + incrément) pendant que le
    // feed finit de charger. Le gate 1×/jour-tournée (côté header) décide s'il
    // joue réellement.
    ref.read(pendingStreakCelebrationProvider.notifier).state = true;
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

  /// Ouverture « Ouvrir ta tournée » / tap enveloppe : file au feed sans
  /// deep-link de section (feed en haut). Ouvre la lettre **centrée** (le
  /// carrousel a déjà écrit `selectedEditionDateProvider` au settle).
  void _openTournee() {
    ref.read(pendingFeedSectionKeyProvider.notifier).state = null;
    _open();
  }

  /// Tap sur une ligne du deep-dive « file droit vers une section » : pose la
  /// clé de section à révéler puis ouvre le feed. La liste des sections reflète
  /// toujours la tournée **du jour** (live), donc on force le retour à
  /// « Aujourd'hui » (une lettre passée est en lecture seule sans ces sections).
  void _openSection(String sectionKey) {
    ref.read(selectedEditionDateProvider.notifier).state = const EditionToday();
    ref.read(pendingFeedSectionKeyProvider.notifier).state = sectionKey;
    _open();
  }

  void _finishOpen() {
    if (_navigated || !mounted) return;
    _navigated = true;
    // Le flag « vu » est déjà posé à la révélation (cf. _revealRitual) → pas
    // d'await ici, on file au feed sans délai.
    context.go(RoutePaths.fluxContinu);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // La révélation ne dépend plus que du temps : le plancher d'ambiance
    // ([_floorTimer]) la déclenche, ou immédiatement en reduceMotion (le timer
    // n'aurait pas d'utilité). Post-frame → jamais de setState pendant le build.
    if (_phase == _Phase.loading && reduceMotion) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealRitual());
    }

    Widget body;
    if (_phase == _Phase.loading) {
      body = const _IntroLoader(
        key: ValueKey('morning-loader'),
        revealEditorialAfter: _editorialReveal,
      );
    } else {
      // Le titre daté est calculé par [_RitualGreeting] (qui écoute la lettre
      // centrée via `selectedEditionDateProvider`), plus par une étiquette figée.
      final Widget ritual = _RitualBody(
        key: const ValueKey('morning-ritual'),
        reduceMotion: reduceMotion,
        onOpenTournee: _openTournee,
        onOpenSection: _openSection,
      );
      // Transition pilotée par `_exitController` : slide doux vers le haut +
      // fondu à l'ouverture (tap CTA / enveloppe / section). À la valeur 0 elle
      // est neutre (offset zéro, opacité pleine).
      body = SlideTransition(
        position: _slideOut,
        child: FadeTransition(opacity: _fadeOut, child: ritual),
      );
    }

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : FacteurDurations.medium,
        child: body,
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

  const _IntroLoader({
    super.key,
    required this.revealEditorialAfter,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            // Enveloppe décorative (onTap null) en tête de la colonne centrée du
            // loader : même bloc que le FacteurLoader + citation.
            child: LoadingView(
              revealEditorialAfter: revealEditorialAfter,
              leading: const _EnvelopeHero(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rituel matinal refondu (maquette « Lettre du jour ») : **page d'accueil
/// scrollable** offrant deux chemins d'entrée dans la tournée — le bouton
/// primaire « Ouvrir ta tournée » et la liste « Ou file droit vers une
/// section ». Le carrousel de lettres (Aujourd'hui / Hier / Cette semaine) est
/// conservé, allégé (sous-titre + enveloppe par slide), avec tous ses nudges de
/// changement de jour (points + « Glisse pour rattraper les jours passés »). La
/// pilule « Mode serein » reste collée en bas via un `Stack` + dégradé.
class _RitualBody extends StatelessWidget {
  final bool reduceMotion;
  final VoidCallback onOpenTournee;
  final void Function(String sectionKey) onOpenSection;

  const _RitualBody({
    super.key,
    required this.reduceMotion,
    required this.onOpenTournee,
    required this.onOpenSection,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Marge éditoriale haute (le header retiré fournissait ~44px) :
                // évite que le titre daté ne colle à la status-bar.
                const SizedBox(height: FacteurSpacing.space6),
                const _RitualGreeting(),
                const SizedBox(height: FacteurSpacing.space3),
                _EditionCarousel(
                  reduceMotion: reduceMotion,
                  onOpen: onOpenTournee,
                ),
                const SizedBox(height: FacteurSpacing.space4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space6),
                  child: _OpenTourneeCta(onTap: onOpenTournee),
                ),
                const SizedBox(height: FacteurSpacing.space6),
                _DeepDiveListHost(onOpenSection: onOpenSection),
                // Laisse passer la pilule Serein sticky (dégradé + pilule + intro).
                const SizedBox(height: 112),
              ],
            ),
          ),
          // « Mode serein » collé en bas : la pilule reçoit les taps, le fond
          // dégradé (bg-primary) est traversant (pointer-events none). Hauteur
          // relevée (92→118) pour couvrir l'intro « Pas d'humeur… » posée
          // au-dessus de la pilule en mode par défaut.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 118,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.backgroundPrimary.withValues(alpha: 0),
                      colors.backgroundPrimary,
                    ],
                    stops: const [0, 0.42],
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: FacteurSpacing.space6,
            child: Center(child: _SereinCta()),
          ),
        ],
      ),
    );
  }
}

/// Bloc titre daté + sous-titre du rituel (remplace le « Salut, » figé). Écoute
/// la lettre centrée (`selectedEditionDateProvider`) et affiche sa date longue FR
/// capitalisée (« Mardi 26 juin »), ou « Cette semaine » pour la rétro hebdo. Le
/// titre est robuste au crop (serif ~27px, `maxLines: 1` + `FittedBox`). Le
/// sous-titre est statique (« Ton essentiel t'attend ! »). `ConsumerWidget` privé
/// pour garder [_RitualBody] provider-free.
class _RitualGreeting extends ConsumerWidget {
  const _RitualGreeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final selection = ref.watch(selectedEditionDateProvider);
    final title = switch (selection) {
      EditionToday() =>
        _capitalizeFirst(formatFrenchLongDate(editionTodayDate())),
      EditionPastDay(:final date) =>
        _capitalizeFirst(formatFrenchLongDate(date)),
      EditionWeek() => 'Cette semaine',
    };
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: FacteurTypography.serifTitle(colors.textPrimary)
                  .copyWith(fontSize: 27, height: 1.05, letterSpacing: -0.5),
            ),
          ),
        ),
        const SizedBox(height: FacteurSpacing.space1),
        Text(
          'Ton essentiel t\'attend !',
          textAlign: TextAlign.center,
          style: FacteurTypography.bodyLarge(colors.textSecondary),
        ),
      ],
    );
  }
}

/// Majuscule sur la première lettre (les libellés de date FR arrivent en bas de
/// casse : « mardi 26 juin » → « Mardi 26 juin »).
String _capitalizeFirst(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Pont Riverpod : lit les sections de la tournée **du jour**
/// (`fluxContinuProvider`) et les passe, provider-free, à [SectionDeepDiveList]
/// (directement testable). Rend l'échafaudage **même en squelette** : les
/// coquilles portent déjà label/emoji/accent et l'ordre correct (favoris →
/// Actus → Bonnes), et [_SectionRow] shimmer les sections encore vides — le
/// contenu hydrate en place. On ne tombe sur `SizedBox.shrink()` que si vraiment
/// aucune section (compte nul, même en squelette). Fournit aussi le callback
/// « Gérer » (config de l'Essentiel) pour garder la liste provider-free.
class _DeepDiveListHost extends ConsumerWidget {
  final void Function(String sectionKey) onOpenSection;

  const _DeepDiveListHost({required this.onOpenSection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flux = ref.watch(fluxContinuProvider).valueOrNull;
    // Ni le rappel d'alertes ni la carte carrousel (Story 32.1) ne sont des
    // destinations de lecture : ce sont des cartes auto-portées sans page dédiée
    // (cf. `nextSectionAfter`), donc pas de ligne « ouvrir la section » ici.
    final sections = (flux?.sections ?? const <FluxSection>[])
        .where((s) => s is! AlertsSection && s is! CarouselSection)
        .toList(growable: false);
    if (sections.isEmpty) return const SizedBox.shrink();
    return SectionDeepDiveList(
      sections: sections,
      onOpenSection: onOpenSection,
      onTapManage: () => showManageFavoritesSheet(
        context,
        entry: ManageFavoritesEntry.essentiel,
      ),
    );
  }
}

/// Carrousel horizontal de lettres (EPIC « Lettre du jour ») — `PageView` sur
/// [editionPillModel] (`[Cette semaine, Hier, Aujourd'hui]`), centré sur
/// **Aujourd'hui** (page la plus à droite). Refonte maquette : slides **pleine
/// largeur** (viewportFraction 1.0, sans scale) dans un `SizedBox` de hauteur
/// fixe (enveloppe seule). Au settle, la sélection centrée est écrite dans
/// [selectedEditionDateProvider] (le CTA/enveloppe valident cette lettre). Tous
/// les nudges de changement de jour sont conservés : CTA voisins ← / → autour de
/// la rangée de points ([_CarouselNavRow]) + libellé « Glisse pour rattraper les
/// jours passés » (`onTap` = repli accessible ouvrant la timeline).
class _EditionCarousel extends ConsumerStatefulWidget {
  final bool reduceMotion;
  final VoidCallback onOpen;

  const _EditionCarousel({
    required this.reduceMotion,
    required this.onOpen,
  });

  @override
  ConsumerState<_EditionCarousel> createState() => _EditionCarouselState();
}

class _EditionCarouselState extends ConsumerState<_EditionCarousel> {
  /// Hauteur du `PageView` : enveloppe (≈171) + marge de centrage. Fixe pour
  /// borner le PageView dans la page scrollable (un PageView exige une contrainte
  /// verticale bornée). Réduite (268→190) depuis le retrait du sous-titre par
  /// slide (chaque slide = enveloppe seule).
  static const double _kPageHeight = 190;

  late final List<EditionSelection> _pages;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _pages = editionPillModel();
    final todayIndex = _pages.indexWhere((s) => s is EditionToday);
    _controller = PageController(
      initialPage: todayIndex < 0 ? 0 : todayIndex,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Une fois la page **stabilisée** (settle, jamais à chaque tick), la sélection
  /// centrée devient la sélection courante : `editionEssentielProvider` (keyé
  /// dessus) reflète la carte centrée, et le CTA/enveloppe valident cette lettre.
  void _onPageChanged(int index) {
    final selection = _pages[index];
    ref.read(selectedEditionDateProvider.notifier).state = selection;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      children: [
        SizedBox(
          height: _kPageHeight,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: _onPageChanged,
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              // Chaque slide se limite désormais à l'enveloppe (provider-free,
              // testable) : today et voisins sont identiques, seul le libellé
              // sémantique et le titre daté (hors carrousel) les distinguent.
              return Semantics(
                label: editionPillLabel(_pages[index]),
                child: MorningRitualContent(
                  reduceMotion: widget.reduceMotion,
                  onOpen: widget.onOpen,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: FacteurSpacing.space4),
        _CarouselNavRow(controller: _controller, pages: _pages),
        const SizedBox(height: FacteurSpacing.space2),
        // Nudge temporalité conservé (exigence PO) : libellé discret pleine
        // largeur, `onTap` = repli accessible ouvrant la timeline complète.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => EditionTimelineSheet.show(context),
          child: Semantics(
            button: true,
            label: 'Voir toutes les lettres',
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: FacteurSpacing.space6, vertical: 2),
              child: Text(
                'Glisse pour rattraper les jours passés',
                textAlign: TextAlign.center,
                style: FacteurTypography.bodySmall(colors.textTertiary)
                    .copyWith(fontSize: 11.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Points de pagination du carrousel de lettres (nudge « moyen » — point 1) :
/// Page courante du carrousel, `initialPage` tant que le [PageController] n'a
/// pas de dimensions (premier paint) — partagé par les points et le scale.
double _controllerPage(PageController controller) {
  if (controller.hasClients && controller.position.haveDimensions) {
    return controller.page ?? controller.initialPage.toDouble();
  }
  return controller.initialPage.toDouble();
}

/// une rangée de [count] points qui révèle d'un coup d'œil qu'il y a plusieurs
/// lettres. Le point de la page courante est plein/large (`colors.primary`), les
/// autres atténués (`textTertiary`). Chaque point est **tapable** →
/// `animateToPage` (découverte + navigation directe vers une lettre).
class _CarouselDots extends StatelessWidget {
  final PageController controller;
  final int count;

  const _CarouselDots({required this.controller, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = _controllerPage(controller).round();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.animateToPage(
                  i,
                  duration: FacteurDurations.medium,
                  curve: Curves.easeInOut,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: FacteurDurations.fast,
                    width: i == current ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == current
                          ? colors.primary
                          : colors.textTertiary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(FacteurRadius.pill),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Rangée de navigation du carrousel : CTA voisin gauche (← lettre plus
/// **ancienne**, index inférieur) · rangée de points centrée · CTA voisin droit
/// (lettre plus **récente**, index supérieur →). Chaque CTA affiche le **libellé
/// réel** de la lettre voisine ([editionPillLabel]) et navigue au tap
/// (`animateToPage`, cohérent avec le tap sur un point). Le côté sans voisin
/// garde son espace (les deux `Expanded` symétriques laissent les points centrés)
/// pour ne pas décaler la rangée entre les lettres.
class _CarouselNavRow extends StatelessWidget {
  final PageController controller;
  final List<EditionSelection> pages;

  const _CarouselNavRow({required this.controller, required this.pages});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current =
            _controllerPage(controller).round().clamp(0, pages.length - 1);
        final leftLabel =
            current > 0 ? editionPillLabel(pages[current - 1]) : null;
        final rightLabel = current < pages.length - 1
            ? editionPillLabel(pages[current + 1])
            : null;
        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: leftLabel == null
                      ? const SizedBox.shrink()
                      : _NeighborCta(
                          label: leftLabel,
                          isLeft: true,
                          onTap: () => controller.animateToPage(
                            current - 1,
                            duration: FacteurDurations.medium,
                            curve: Curves.easeInOut,
                          ),
                        ),
                ),
              ),
              _CarouselDots(controller: controller, count: pages.length),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: rightLabel == null
                      ? const SizedBox.shrink()
                      : _NeighborCta(
                          label: rightLabel,
                          isLeft: false,
                          onTap: () => controller.animateToPage(
                            current + 1,
                            duration: FacteurDurations.medium,
                            curve: Curves.easeInOut,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Affordance « lettre voisine » : reprend le traitement de la double-flèche
/// « Rattraper » ([EditionRewindTrigger]) — glyphe Phosphor ⏪/⏩ **en couleur
/// `primary`** + libellé date en `primary` poids fort (au lieu du chevron gris
/// peu lisible). Borné (`Flexible` + `maxLines: 1` + ellipsis) pour ne jamais
/// crop/overflow sur 360–390px. [isLeft] = lettre plus **ancienne** (⏪ à
/// gauche) ; sinon lettre plus **récente** (⏩ à droite). Haptique de sélection
/// au tap (miroir de [EditionRewindTrigger]).
class _NeighborCta extends StatelessWidget {
  final String label;
  final bool isLeft;
  final VoidCallback onTap;

  const _NeighborCta({
    required this.label,
    required this.isLeft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final glyph = Icon(
      isLeft
          ? PhosphorIcons.rewind(PhosphorIconsStyle.fill)
          : PhosphorIcons.fastForward(PhosphorIconsStyle.fill),
      size: 15,
      color: colors.primary,
    );
    final text = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FacteurTypography.bodySmall(colors.primary)
            .copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
    return Semantics(
      button: true,
      label: isLeft ? 'Lettre précédente : $label' : 'Lettre suivante : $label',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: isLeft
                ? [glyph, const SizedBox(width: 4), text]
                : [text, const SizedBox(width: 4), glyph],
          ),
        ),
      ),
    );
  }
}

/// Slide du carrousel : **enveloppe seule** (le titre daté et le sous-titre ont
/// migré vers l'en-tête [_RitualGreeting] ; le bouton « Ouvrir ta tournée » gère
/// l'ouverture). Identique pour today et voisins — seul le libellé sémantique du
/// carrousel les distingue. Provider-free, donc directement testable sans monter
/// les providers du header.
class MorningRitualContent extends StatelessWidget {
  final bool reduceMotion;
  final VoidCallback onOpen;

  const MorningRitualContent({
    super.key,
    required this.reduceMotion,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Center(child: _EnvelopeHero(onTap: onOpen)),
    );
  }
}

/// Bouton primaire « Ouvrir ta tournée » (maquette) — pleine largeur, fond
/// `primary`, libellé + flèche ↗. Remplace le geste swipe-up : `onTap` ouvre le
/// feed (sans section cible). Enfoncement doux à l'appui (scale 0.98).
class _OpenTourneeCta extends StatefulWidget {
  final VoidCallback onTap;

  const _OpenTourneeCta({required this.onTap});

  @override
  State<_OpenTourneeCta> createState() => _OpenTourneeCtaState();
}

class _OpenTourneeCtaState extends State<_OpenTourneeCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: 'Ouvrir ta tournée',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.mediumImpact();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: FacteurDurations.fast,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ouvrir ta tournée',
                  style: FacteurTypography.labelLarge(Colors.white)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                const Icon(Icons.arrow_outward_rounded,
                    size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Liste « Ou accède directement à » (maquette). Divider mono uppercase + lien
/// discret « Gérer » (config Essentiel) à droite + une [_SectionRow] par section
/// de la tournée du jour. Le lien est volontairement plat/inline ici (pas la
/// pilule accentuée du feed) pour ne pas voler la vedette au CTA principal.
/// Provider-free (reçoit [sections] + [onOpenSection] + [onTapManage]) pour être
/// directement testable ; le pont Riverpod vit dans [_DeepDiveListHost].
class SectionDeepDiveList extends StatelessWidget {
  final List<FluxSection> sections;
  final void Function(String sectionKey) onOpenSection;
  final VoidCallback onTapManage;

  const SectionDeepDiveList({
    super.key,
    required this.sections,
    required this.onOpenSection,
    required this.onTapManage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Ou accède directement à',
                style: FacteurTypography.labelSmall(colors.textTertiary)
                    .copyWith(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Container(
                  height: 1,
                  color: colors.textTertiary.withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              _InlineManageLink(onTap: onTapManage),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space3),
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
              child: _SectionRow(
                section: section,
                onTap: () => onOpenSection(sectionKey(section)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lien « Gérer » discret (plat, sans fond ni bordure) de la liste des sections
/// du rituel. Contraste voulu avec [ManageButton] (pilule accentuée du feed) :
/// ici il est inline et secondaire pour ne pas concurrencer le CTA « Ouvrir ta
/// tournée ». Garde ~36px de hauteur de tap (InkWell + ripple) malgré son style
/// plat.
class _InlineManageLink extends StatelessWidget {
  final VoidCallback onTap;

  const _InlineManageLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: 'Gérer mes intérêts',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gérer',
                  style: FacteurTypography.labelSmall(colors.textSecondary)
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Icon(Icons.chevron_right,
                    size: 14, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une ligne du deep-dive : carré emoji + nom (+ badge « Peu d'articles »
/// optionnel) + méta compteur (« N titres » / « N articles ») + flèche →. Le
/// fond porte une teinte discrète de l'accent de la section.
///
/// **Échafaudage (reveal rapide)** : quand la section est encore une coquille
/// (`FeedThemeSection.isPlaceholder`, ou compteur nul — sections éditoriales du
/// squelette), le label/emoji/accent restent lisibles mais la ligne méta + la
/// flèche sont remplacées par un **shimmer discret**. Le tap reste actif (le feed
/// hydrate la section à l'arrivée) et l'ordre est stable.
class _SectionRow extends StatelessWidget {
  final FluxSection section;
  final VoidCallback onTap;

  /// Seuil « peu fourni » : une section avec ≤1 carte affiche le badge.
  static const int _kThinThreshold = 1;

  const _SectionRow({required this.section, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final s = section;
    final placeholder =
        (s is FeedThemeSection && s.isPlaceholder) || s.totalCount == 0;
    final count = s.totalCount;
    final isEssentiel = s is EssentielSection;
    final meta = isEssentiel
        ? '$count titre${count > 1 ? 's' : ''}'
        : '$count article${count > 1 ? 's' : ''}';
    // En squelette : pas de badge « peu fourni » (le compteur n'est pas encore
    // réel), et la sémantique annonce « chargement » plutôt qu'un faux compteur.
    final thin = !placeholder && count <= _kThinThreshold;

    return Semantics(
      button: true,
      label: placeholder ? '${s.label}, chargement' : '${s.label}, $meta',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          decoration: BoxDecoration(
            color: s.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(FacteurRadius.large),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                  border: Border.all(
                    color: colors.textTertiary.withValues(alpha: 0.10),
                  ),
                ),
                child: Text(
                  sectionEmoji(s),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FacteurTypography.bodyMedium(
                                    colors.textPrimary)
                                .copyWith(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                        if (thin) ...[
                          const SizedBox(width: FacteurSpacing.space2),
                          _ThinBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    if (placeholder)
                      const _MetaShimmer()
                    else
                      Text(
                        meta.toUpperCase(),
                        style:
                            FacteurTypography.labelSmall(colors.textTertiary)
                                .copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          letterSpacing: 0.4,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              // Flèche masquée tant que la section charge (largeur réservée pour
              // ne pas décaler la ligne quand le contenu arrive).
              placeholder
                  ? const SizedBox(width: 17)
                  : Icon(Icons.arrow_forward_rounded,
                      size: 17, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barre shimmer discrète qui remplace la ligne méta « N articles » d'une
/// section encore en cours de chargement (échafaudage du reveal rapide). Le
/// package `shimmer` gère sa propre animation → widget `const` sans état.
class _MetaShimmer extends StatelessWidget {
  const _MetaShimmer();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final base = colors.textTertiary.withValues(alpha: 0.20);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: colors.textTertiary.withValues(alpha: 0.06),
      child: Container(
        width: 64,
        height: 9,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Badge « Peu d'articles » (pilule `primary` 12 %) d'une section peu fournie.
class _ThinBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_rounded, size: 11, color: colors.primary),
          const SizedBox(width: 3),
          Text(
            'Peu d\'articles',
            style: FacteurTypography.labelSmall(colors.primary)
                .copyWith(fontWeight: FontWeight.w600, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// « Mode Serein » du rituel sous forme de **pilule secondaire centrée**, collée
/// en bas de la page scrollable (dégradé + sticky). Pour les matins sans envie de news
/// difficiles : un accès direct à la lecture apaisée (toggle persistant partagé
/// avec le feed, cf. [sereinToggleProvider]). L'état rempli/contour communique
/// on/off (plus de cercle + sous-titre + `Switch.adaptive`). `ConsumerWidget`
/// privé pour garder [MorningRitualContent] provider-free.
class _SereinCta extends ConsumerWidget {
  const _SereinCta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final serein = ref.watch(sereinToggleProvider);
    final enabled = serein.enabled;
    // Désactivé tant que la préférence serveur n'est pas chargée (évite un
    // toggle qui serait écrasé par la première synchro `initFromApi`).
    final loading = serein.isLoading;

    void toggle() {
      if (loading) return;
      HapticFeedback.selectionClick();
      unawaited(ref.read(sereinToggleProvider.notifier).toggle());
    }

    final Widget pill = InkWell(
      onTap: loading ? null : toggle,
      borderRadius: BorderRadius.circular(FacteurRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: SereinColors.sereinColor
              .withValues(alpha: enabled ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(FacteurRadius.pill),
          border: Border.all(
            color: SereinColors.sereinColor
                .withValues(alpha: enabled ? 0.5 : 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              SereinColors.sereinIcon,
              size: 16,
              color: SereinColors.sereinColor,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Text(
              enabled ? 'Mode serein activé' : 'Passer en mode serein',
              style: FacteurTypography.labelLarge(
                enabled ? SereinColors.sereinColor : colors.textSecondary,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            if (enabled) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_rounded,
                size: 14,
                color: SereinColors.sereinColor,
              ),
            ],
          ],
        ),
      ),
    );

    // Intro discrète au-dessus de la pilule, uniquement en mode par défaut
    // (serein désactivé) : adoucit l'entrée en mode serein. Disparaît une fois
    // activé (le libellé de la pilule confirme alors l'état).
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!enabled) ...[
          Text(
            'Pas d\'humeur pour du négatif ?',
            textAlign: TextAlign.center,
            style: FacteurTypography.bodySmall(colors.textTertiary),
          ),
          const SizedBox(height: FacteurSpacing.space2),
        ],
        pill,
      ],
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
  <rect x="200" y="30" width="34" height="28" fill="$primary" stroke="#FCF8F0"
        stroke-width="2" stroke-dasharray="3 3"/>
  <circle cx="217" cy="44" r="5" fill="#FCF8F0" opacity="0.85"/>
  <circle cx="130" cy="106" r="28" fill="$primary"/>
  <circle cx="130" cy="106" r="28" fill="none" stroke="rgba(0,0,0,0.12)" stroke-width="2"/>
</svg>''';
