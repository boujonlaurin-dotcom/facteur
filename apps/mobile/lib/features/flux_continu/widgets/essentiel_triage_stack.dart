import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/theme.dart';
import '../../../core/nudges/widgets/nudge_inline_banner.dart';
import '../../../shared/widgets/read_state_mark.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../detail/content_preview_mapper.dart';
import '../../digest/widgets/divergence_inline_badge.dart';
import '../../feed/models/content_model.dart'
    show ReadState, effectiveReadState, opacityForReadState;
import '../../feed/services/read_sync_service.dart';
import '../../feed/widgets/animated_feed_card.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../models/flux_continu_models.dart';
import '../providers/essentiel_triage_provider.dart';
import '../services/preview_nudge_scheduler.dart';
import '../utils/section_fit.dart';
import '../utils/theme_color_mapping.dart';
import 'auto_grow_pulse.dart';
import 'coverage_chip.dart';
import 'triage_stack_skeleton.dart';
import 'triage_swipe_card.dart';

/// La pile à trier de la carte « Ton Essentiel » (Story 33.1).
///
/// Un article à la fois : swipe droite « Je garde », swipe gauche « Pas pour
/// moi », bouton signet « Plus tard ». La liste des gardés se construit sous la
/// pile, dans le feed, sans écran supplémentaire.
///
/// **La carte épouse son contenu** (itération PO 33.1) : au lieu de réserver la
/// hauteur de pic (grand vide sous la pile), la colonne est dimensionnée par son
/// contenu et enveloppée d'un [AnimatedSize] aligné en haut → la kept-list
/// grandit **vers le bas, sous la barre d'actions**.
///
/// La carte du dessus est elle aussi **dimensionnée par son contenu** (reprise
/// PO 08/08, qui renverse les deux hauteurs discrètes de la passe design) :
/// bandeau image s'il y en a un, titre sur ses lignes réelles, méta juste
/// dessous. Un titre court ne laisse plus de blanc interne. La bascule d'une
/// hauteur à l'autre reste **glissée** par l'[AnimatedSize] : la barre d'actions
/// se déplace de façon lisible sous le pouce, elle ne saute pas. La hauteur
/// reste bornée par construction (bandeau [kTriageCardImageHeight] fixe + titre
/// borné par `maxLines`) — aucun plafond explicite n'est donc nécessaire.
///
/// Ordre de la colonne (reprises PO 08/08, 10/08, puis 33.4) : **carte →
/// actions → nudge d'arrêt → barre de progression → objectif → gardés**. Tout
/// ce qui informe est *sous* les boutons, à portée du pouce ; la silhouette
/// ([TriageStackSkeleton]) porte le même ordre et les mêmes hauteurs, sans quoi
/// la mise en page sauterait à l'hydratation (le nudge, lui, n'a pas de
/// silhouette : il n'existe qu'après cinq refus, jamais au premier rendu).
///
/// Ce que la story 33.4 change dans cette colonne : la barre de progression
/// compte les **gardés** et non plus les triés, et le stepper règle le nombre
/// d'articles à garder — la pile, elle, s'alimente jusqu'à cette cible.
class EssentielTriageStack extends ConsumerStatefulWidget {
  /// Pool des articles adressables par la pile : le slate figé du jour, suivi
  /// des articles injectables par « Voir d'autres articles ». C'est une liste ;
  /// l'index par `contentId` est construit au build, à un seul endroit.
  final List<EssentielArticle> articles;
  final EssentielTriageState triage;

  /// Ouvre un article — une ligne gardée, ou la **carte du dessus** elle-même
  /// (Story 33.2 : un tap ouvre, sans décider). Quand l'article ouvert depuis
  /// la pile est effectivement lu, le retour le compte comme gardé
  /// (`decide(keep, via: read)`).
  final void Function(EssentielArticle article) onTapArticle;

  const EssentielTriageStack({
    super.key,
    required this.articles,
    required this.triage,
    required this.onTapArticle,
  });

  @override
  ConsumerState<EssentielTriageStack> createState() =>
      _EssentielTriageStackState();
}

class _EssentielTriageStackState extends ConsumerState<EssentielTriageStack> {
  final GlobalKey<TriageSwipeCardState> _cardKey = GlobalKey();

  /// Jeton de rejeu du pulse `AutoGrowPulse` — change pour rejouer.
  Object? _pulseToken;

  /// Le mini libellé « Appuie longuement pour un aperçu. » est-il visible ?
  bool _showPreviewHint = false;

  /// Une seule tentative de nudge par montage : sans ce verrou, un rebuild
  /// pendant que le `canTriggerNow()` asynchrone est en vol relancerait la
  /// séquence et le pulse se rejouerait en boucle sur la même carte.
  bool _nudgeAttempted = false;

  /// L'event `shown` du nudge d'arrêt est-il déjà parti pour l'apparition en
  /// cours ? Retombe à faux dès que le nudge disparaît, pour que la prochaine
  /// série de refus soit de nouveau comptée.
  bool _stopNudgeTracked = false;

  /// Les `contentId` ouverts **depuis la pile** (tap sur la carte du dessus).
  /// C'est le filtre de l'auto-keep au retour : sans lui, l'hydratation
  /// serveur de `consumedContentIdsProvider` au cold-boot garderait d'office
  /// tout article du slate déjà lu par ailleurs.
  final Set<String> _openedForRead = {};

  Timer? _hintTimer;

  /// Avancée du geste en cours (0..1), remontée par [TriageSwipeCard]. Pilote la
  /// **promotion continue** de la carte du dessous : son opacité (seul attribut
  /// de profondeur, cf. [kTriageBackCardOpacity]) atteint 1.0 *pendant* la
  /// sortie de la carte du dessus, au lieu de claquer de 0.5 à 1.0 quand elle
  /// devient carte du dessus.
  ///
  /// Un `ValueNotifier` plutôt qu'un `setState` : seule la carte du dessous doit
  /// se rebuilder à chaque frame de geste, pas la pile entière.
  final ValueNotifier<double> _promotion = ValueNotifier(0);

  /// Les `contentId` des lignes gardées déjà rendues au moins une fois. Une
  /// ligne absente de ce set est une **nouvelle** gardée : elle joue son entrée
  /// (fade + léger scale) une seule fois. Initialisé avec les gardés du montage
  /// pour qu'un cold-boot en plein tri ne rejoue pas l'entrée de toute la liste
  /// — l'entrée est un événement, pas un état.
  late final Set<String> _renderedKeptIds;

  @override
  void initState() {
    super.initState();
    _renderedKeptIds = {...widget.triage.keptContentIds};
    // Point de départ de la mesure de latence du premier article.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(essentielTriageProvider.notifier).markShown();
    });
    // Cold-boot en plein tri : la pile peut se monter directement sur la carte
    // du nudge.
    unawaited(_maybeTriggerPreviewNudge());
  }

  @override
  void didUpdateWidget(EssentielTriageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.triage.index != widget.triage.index) {
      // La carte promue devient carte du dessus : la promotion repart de zéro
      // pour la nouvelle carte du dessous, qui elle n'a pas encore été touchée.
      _promotion.value = 0;
      unawaited(_maybeTriggerPreviewNudge());
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _promotion.dispose();
    super.dispose();
  }

  void _decide(TriageDecision decision, TriageVia via) {
    ref.read(essentielTriageProvider.notifier).decide(decision, via: via);
  }

  /// Depuis la barre d'actions : rejoue la sortie physique du swipe pour que
  /// les deux modalités rendent le même mouvement.
  void _decideFromButton(TriageDecision decision) {
    final state = _cardKey.currentState;
    if (state == null) {
      _decide(decision, TriageVia.button);
      return;
    }
    // « Plus tard » sort du même côté que « Je garde » (c'est un choix
    // positif), mais la décision enregistrée reste `later`, et la modalité
    // `button`.
    state.animateOut(
      toRight: decision != TriageDecision.pass,
      onDone: () => _decide(decision, TriageVia.button),
    );
  }

  /// Joue une fois le nudge « aperçu au long-press » sur la 2ᵉ carte de la pile
  /// (la 1ʳᵉ appartient à la découverte du swipe). Silencieux si le scheduler
  /// refuse : déjà montré aujourd'hui, ou aperçu déjà découvert.
  Future<void> _maybeTriggerPreviewNudge() async {
    if (_nudgeAttempted) return;
    if (widget.triage.index != kTriagePreviewNudgeCardIndex) return;
    _nudgeAttempted = true;

    final scheduler = ref.read(triagePreviewNudgeSchedulerProvider);
    if (!await scheduler.canTriggerNow()) return;
    if (!mounted) return;
    await scheduler.recordTriggered();
    if (!mounted) return;

    setState(() {
      _pulseToken = Object();
      _showPreviewHint = true;
    });
    _hintTimer?.cancel();
    _hintTimer = Timer(kTriagePreviewHintDuration, () {
      if (mounted) setState(() => _showPreviewHint = false);
    });
  }

  /// Un vrai long-press : l'aperçu est découvert. Le nudge s'éteint à vie et le
  /// libellé en cours disparaît immédiatement — il a fait son travail.
  void _markPreviewDiscovered() {
    unawaited(ref.read(triagePreviewNudgeSchedulerProvider).markDiscovered());
    _hintTimer?.cancel();
    if (_showPreviewHint) setState(() => _showPreviewHint = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final triage = widget.triage;
    final currentId = triage.currentContentId;
    // Inatteignable depuis la carte (`showTriage` ⇒ `triage.isActive` ⇒
    // `!done` ⇒ `currentContentId != null`), mais fermé comme son cas frère
    // ci-dessous : un `SizedBox.shrink()` ici rendrait la carte à son en-tête
    // nu si un appelant futur montait la pile hors de ce gate.
    if (currentId == null) return const TriageStackSkeleton(standalone: true);

    final byId = {for (final a in widget.articles) a.contentId: a};
    final current = byId[currentId];
    // Haut de pile irrésolvable : le slate est figé pour la journée, mais le
    // pool, lui, peut ne pas (encore) le porter — carrousel absent de
    // l'hydratation cache après un « Plus d'articles », blend live qui rebat le
    // jeu du jour, articles masqués au swipe. On rend alors la **silhouette**,
    // jamais un corps vide : un `SizedBox.shrink()` ici laissait la carte
    // réduite à son en-tête au-dessus d'un aplat de fond, indéfiniment (défaut
    // « aucun squelette pendant le chargement » remonté en E2E). La carte
    // déclenche en parallèle `pruneUnavailable`, donc cette attente est bornée :
    // soit le pool se complète, soit le slate se répare.
    if (current == null) return const TriageStackSkeleton(standalone: true);

    // Article suivant, rendu en dessous pour donner l'épaisseur de pile.
    final nextIndex = triage.index + 1;
    final next =
        nextIndex < triage.slate.length ? byId[triage.slate[nextIndex]] : null;

    // État de lecture de session : la carte du dessus et les lignes gardées
    // portent le marquage habituel (grisé + coche), et c'est aussi le signal
    // de l'auto-keep ci-dessous.
    final consumedIds = ref.watch(consumedContentIdsProvider);
    final completedIds = ref.watch(completedContentIdsProvider);
    ReadState readStateFor(EssentielArticle a) => effectiveReadState(
          a.readState,
          consumedThisSession: consumedIds.contains(a.contentId),
          completedThisSession: completedIds.contains(a.contentId),
        );

    // **Auto-keep au retour de lecture** (Story 33.2) : l'article du dessus a
    // été ouvert depuis la pile (tap) et la session le dit lu → il compte
    // comme gardé, via la modalité `read`. Posté après la frame (muter un
    // provider pendant le build est interdit) ; retiré du set **avant** le
    // post pour qu'un rebuild dans la même frame ne double pas la décision.
    if (_openedForRead.contains(currentId) &&
        (consumedIds.contains(currentId) || completedIds.contains(currentId))) {
      _openedForRead.remove(currentId);
      final decidedId = currentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final notifier = ref.read(essentielTriageProvider.notifier);
        // La carte du dessus doit être restée la même : `decide` agit sur le
        // haut de pile courant, pas sur un id.
        if (ref.read(essentielTriageProvider).currentContentId != decidedId) {
          return;
        }
        notifier.decide(TriageDecision.keep, via: TriageVia.read);
      });
    }

    // Un seul point de lecture de l'état des sources : les cartes et les lignes
    // gardées restent des `StatelessWidget` et reçoivent un `InterestState`.
    //
    // Indexé une fois par build : `UserSourcesState.stateOf` est un scan
    // linéaire, et la pile l'interrogerait sinon une fois par article rendu
    // (carte du dessus + carte du dessous + chaque ligne gardée) à chaque
    // décision de tri.
    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    final stateBySourceId = <String, InterestState>{};
    if (sourcesState != null) {
      // `putIfAbsent` et non `[]=` : `stateOf` retient la **première**
      // occurrence, on garde exactement la même règle en cas de doublon.
      for (final s in sourcesState.sources) {
        stateBySourceId.putIfAbsent(s.sourceId, () => s.state);
      }
    }
    InterestState? sourceStateOf(EssentielArticle a) {
      final id = a.sourceId;
      if (sourcesState == null || id == null) {
        // Repli sur le drapeau déjà porté par le modèle : au cold-boot, une
        // source suivie doit montrer sa coche sans attendre le réseau.
        return a.isFollowedSource ? InterestState.followed : null;
      }
      // Même défaut que `UserSourcesState.stateOf` : une source inconnue du
      // catalogue est « non suivie », pas « état indéterminé ».
      return stateBySourceId[id] ?? InterestState.unfollowed;
    }

    // Nudge d'arrêt : purement dérivé de l'état, aucun scheduler. L'event
    // `shown` est posté après la frame et **une seule fois par apparition** —
    // le verrou retombe dès que le nudge disparaît (un keep suffit).
    final showStopNudge =
        triage.consecutivePassCount >= kTriageStopNudgeThreshold &&
            !triage.stopNudgeDismissed;
    if (!showStopNudge) {
      _stopNudgeTracked = false;
    } else if (!_stopNudgeTracked) {
      _stopNudgeTracked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(essentielTriageProvider.notifier).trackStopNudgeShown();
      });
    }

    // **Deux `AnimatedSize` frères, jamais imbriqués** (passe PO 09/08, défaut
    // A3). Chacun anime une hauteur **disjointe** : le slot de carte pour l'un,
    // la liste des gardés pour l'autre. La colonne, elle, n'est plus enveloppée.
    //
    // Pourquoi c'est structurel et pas cosmétique : `RenderAnimatedSize` bascule
    // en état `unstable` dès que la taille de son enfant change plusieurs frames
    // d'affilée — il **cesse alors d'animer** et se cale sur l'enfant, après une
    // frame de stalle et un saut de re-ciblage. Un `AnimatedSize` enveloppant la
    // colonne a pour enfant une colonne dont la hauteur bouge à chaque frame
    // (puisque le slot de carte anime la sienne) : il était donc *toujours*
    // instable au changement de carte. Mesuré sur le build cassé, la barre
    // d'actions descendait par à-coups (495.9 → 460.8 → 431.5 → 407.4 → 373.9 →
    // 362.6 : pas irréguliers avec rebond) au lieu d'une easeOutCubic monotone.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Le slot n'impose plus de hauteur : il prend celle de la carte du
        // dessus, qui prend celle de son contenu réel (image ou non, longueur
        // vraie du titre, badges présents ou non). L'`AnimatedSize` fait
        // glisser la barre d'actions d'une carte à l'autre au lieu de la
        // faire sauter — c'est ce qui rend le fit-to-content tenable sous le
        // pouce.
        AnimatedSize(
          duration: FacteurDurations.medium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          // Le `ClipRect` est **la** correction du drift : la carte du dessus
          // est l'enfant non positionné du `Stack`, et son
          // `Transform.translate` peint hors des bornes de layout — un `Stack`
          // ne rogne que ses enfants positionnés, jamais celui-là. Pendant tout
          // le drag et la sortie, la carte débordait donc du cadre de la pile
          // (tranche de carte visible à droite de « Ton Essentiel », lue comme
          // un décalage des articles suivants). Rognée ici, la carte glisse
          // *hors du cadre* et y disparaît proprement, comme tirée d'un paquet.
          child: ClipRect(
            child: Stack(
              // Clés fixes sur les trois slots : l'appariement d'un build à
              // l'autre se fait alors **par clé**, jamais par position. Sans
              // elles, le nombre d'enfants changeait (3 → 2 sur la dernière
              // carte) et un élément glissait d'un slot à l'autre le temps
              // d'une frame — d'où le tampon apparemment déjà posé sur la
              // carte fraîche. Le slot arrière est toujours rendu, vide s'il
              // n'y a plus d'article dessous.
              //
              // **La carte du dessus est le seul enfant non positionné** :
              // c'est elle qui dimensionne le `Stack`, donc la pile entière.
              // Le slot arrière est en `Positioned.fill` — donc exactement au
              // gabarit de la carte du dessus — mais son contenu garde sa
              // hauteur réelle grâce à l'`OverflowBox` (une contrainte serrée
              // ferait déborder une carte image sous une carte texte courte).
              // Ce qui dépasse est rogné par le `ClipRRect`, **au même rayon
              // que la carte du dessus** : c'est la correction du défaut « des
              // arrondis colorés apparaissent autour de la première carte » —
              // le `Stack` rognait au rectangle droit, si bien que l'image de
              // la carte du dessous se voyait dans les deux encoches laissées
              // par les coins arrondis de la carte du dessus.
              children: [
                Positioned.fill(
                  key: const ValueKey('triage-back'),
                  child: next == null
                      ? const SizedBox.shrink()
                      // **Carte du dessous à fleur du cadre, jamais mise à
                      // l'échelle** (reprise PO 10/08, défaut « la carte
                      // suivante est décalée du côté du swipe »). Une carte
                      // réduite est plus étroite que le cadre : dès que la carte
                      // du dessus glisse et pivote, on découvrait sur son bord
                      // de fuite un liseré de fond + le coin arrondi de la carte
                      // du dessous *à l'intérieur* du cadre — lu comme un
                      // décalage latéral. En pleine largeur, la carte révélée
                      // épouse exactement le cadre : plus aucun jour d'un côté,
                      // et la promotion carte-du-dessous → carte-du-dessus
                      // devient continue (aucun « pop » d'échelle). La
                      // profondeur reste portée par l'**opacité seule**, qui
                      // monte de [kTriageBackCardOpacity] vers 1.0 au fil du
                      // geste. L'ancrage haut de l'`OverflowBox` suffit à
                      // aligner deux cartes de hauteurs différentes.
                      : ValueListenableBuilder<double>(
                          valueListenable: _promotion,
                          // `RepaintBoundary` **sous** l'`Opacity` : avec un
                          // enfant déjà composité, `RenderOpacity` pousse un
                          // calque au compositeur au lieu de passer par
                          // `saveLayer` (un tampon hors écran réalloué à chaque
                          // peinture, donc à chaque frame de swipe).
                          builder: (context, p, child) => Opacity(
                            opacity:
                                lerpDouble(kTriageBackCardOpacity, 1.0, p)!,
                            child: child,
                          ),
                          child: IgnorePointer(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(FacteurRadius.large),
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                minHeight: 0,
                                maxHeight: double.infinity,
                                child: RepaintBoundary(
                                  child: _TriageArticleCard(
                                    article: next,
                                    sourceState: sourceStateOf(next),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                AutoGrowPulse(
                  key: const ValueKey('triage-top'),
                  playToken: _pulseToken,
                  child: TriageSwipeCard(
                    key: _cardKey,
                    // Jeton de « carte fraîche » : quand l'article du dessus
                    // change, le State réutilisé (GlobalKey) repart d'un
                    // geste propre au lieu de fuir le drag/anim du précédent.
                    articleId: currentId,
                    onGestureProgress: (p) => _promotion.value = p,
                    // Un tap ouvre l'article, sans décider. La décision
                    // (`keep` via `read`) tombe au retour, si l'article a
                    // vraiment été lu — cf. l'auto-keep en tête de build.
                    onTap: () {
                      _openedForRead.add(currentId);
                      widget.onTapArticle(current);
                    },
                    onKeep: () => _decide(TriageDecision.keep, TriageVia.swipe),
                    onPass: () => _decide(TriageDecision.pass, TriageVia.swipe),
                    // L'aperçu est monté **dans** la carte qui swipe, pas
                    // autour : l'arène de gestes départage alors un drag
                    // horizontal (qui gagne dès le slop franchi) d'un appui
                    // maintenu, au lieu de voir le parent capter les deux.
                    child: ArticlePreviewGesture(
                      contentBuilder: () => current.toPreviewContent(),
                      onLongPressStart: _markPreviewDiscovered,
                      child: _TriageArticleCard(
                        article: current,
                        sourceState: sourceStateOf(current),
                        readState: readStateFor(current),
                      ),
                    ),
                  ),
                ),
                // Le libellé du nudge flotte au bas de la carte : le rendre
                // dans la colonne coûterait une ligne de hauteur permanente
                // pour un message qui vit 2,4 s.
                Positioned(
                  key: const ValueKey('triage-hint'),
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _showPreviewHint ? 1 : 0,
                      duration: FacteurDurations.medium,
                      child: const Center(child: _PreviewHint()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        _ActionBar(
          onPass: () => _decideFromButton(TriageDecision.pass),
          onLater: () => _decideFromButton(TriageDecision.later),
          onKeep: () => _decideFromButton(TriageDecision.keep),
        ),
        // Nudge d'arrêt, **sous** la barre d'actions et au-dessus de la
        // progression : il ne doit ni recouvrir la carte, ni s'intercaler entre
        // le pouce et les boutons. Son propre `AnimatedSize` (frère des deux
        // autres) le fait pousser puis se retirer sans que rien ne saute.
        AnimatedSize(
          duration: FacteurDurations.medium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: showStopNudge
              ? _TriageStopNudge(
                  onStop: () =>
                      ref.read(essentielTriageProvider.notifier).stopTriage(),
                  onDismiss: () => ref
                      .read(essentielTriageProvider.notifier)
                      .dismissStopNudge(),
                )
              : const SizedBox(width: double.infinity),
        ),
        // Repérage visuel de l'avancée **vers la cible de gardés**, sans
        // chiffre : le nombre se lit dans le contrôle juste dessous.
        TriageProgressBar(triage: triage),
        // L'objectif réglable — le nombre d'articles à garder aujourd'hui.
        TriageGoalControl(triage: triage),
        // La liste des gardés se construit sous la pile. Volontairement en
        // lignes compactes et non en `_LeadTile`/`_MediumTile` (les tuiles
        // pleines reviennent une fois le tri terminé, quand la carte reprend
        // sa liste habituelle).
        //
        // Dimensionnée par son contenu (`shrinkWrap`), mais **bornée** : si la
        // kept-list dépasse la moitié du viewport (slate étendu tout gardé sur
        // petit écran), elle défile en interne au lieu de pousser la carte
        // hors de l'écran. En deçà, rien à faire défiler → le geste passe au
        // feed.
        //
        // Son `AnimatedSize` est **frère** de celui du slot de carte, pas son
        // parent : c'est lui qui fait grandir la liste « vers le bas » quand
        // un gardé s'ajoute, sans jamais animer aussi la hauteur du slot (cf.
        // l'explication de l'état `unstable` en tête de build).
        AnimatedSize(
          duration: FacteurDurations.medium,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.5,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              children: [
                // En-tête « TU GARDES » (design 2A) : rendu **dans**
                // l'AnimatedSize de la kept-list pour apparaître avec elle.
                if (triage.keptContentIds.isNotEmpty)
                  _KeptListHeader(
                    count: triage.keptCount,
                    accent: colors.sectionEssentiel,
                  ),
                for (final id in triage.keptContentIds)
                  if (byId[id] != null)
                    _KeptRow(
                      key: ValueKey('triage-kept-row-$id'),
                      article: byId[id]!,
                      sourceState: sourceStateOf(byId[id]!),
                      readState: readStateFor(byId[id]!),
                      // Jouée à la **première** apparition seulement : la clé
                      // stable fait persister l'élément, donc l'entrée ne se
                      // rejoue pas aux rebuilds suivants même si ce booléen
                      // retombe à faux.
                      animateEntry: _renderedKeptIds.add(id),
                      onTap: () => widget.onTapArticle(byId[id]!),
                      onPreviewStart: _markPreviewDiscovered,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Mini libellé du nudge : dit le geste, rien d'autre. Fond opaque pour rester
/// lisible par-dessus le pied de carte qu'il recouvre le temps de son passage.
class _PreviewHint extends StatelessWidget {
  const _PreviewHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        'Appuie longuement pour un aperçu.',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// Un article gardé, en ligne compacte. Tappable : la lecture commence ici,
/// après le tri. Le long-press ouvre le même aperçu que les autres cartes.
///
/// Porte le marquage de lecture habituel (grisé [opacityForReadState] + coche
/// [ReadStateMark], l'idiome de `_LeadTile`/`_MediumTile`) : c'est ici que le
/// signal « lu depuis la pile » vit vraiment, la carte lue quittant la pile
/// aussitôt gardée.
class _KeptRow extends StatefulWidget {
  final EssentielArticle article;

  /// État d'intérêt de la source, pour la coche/étoile posée à droite du nom.
  /// `null` ⇒ aucun signal (source neutre, masquée, ou état pas encore chargé).
  final InterestState? sourceState;

  /// État de lecture effectif (fusion session incluse), descendu par la pile —
  /// un seul point de lecture des providers.
  final ReadState readState;

  /// `true` pour une ligne qui vient d'être gardée : elle joue une entrée
  /// sobre (fade + scale 0.98 → 1.0), une seule fois. Les lignes déjà
  /// présentes au montage de la pile restent statiques — l'entrée est un
  /// événement, pas un état.
  final bool animateEntry;

  final VoidCallback onTap;
  final VoidCallback onPreviewStart;

  const _KeptRow({
    super.key,
    required this.article,
    required this.sourceState,
    required this.readState,
    required this.animateEntry,
    required this.onTap,
    required this.onPreviewStart,
  });

  @override
  State<_KeptRow> createState() => _KeptRowState();
}

class _KeptRowState extends State<_KeptRow> {
  /// Capturé au montage : un rebuild pendant les 250ms d'entrée (provider de
  /// lecture, décision suivante) redescend `animateEntry` à faux — sans cette
  /// capture, l'enveloppe d'animation disparaîtrait de l'arbre en plein vol et
  /// la ligne claquerait à son état final.
  late final bool _playEntry = widget.animateEntry;

  @override
  Widget build(BuildContext context) {
    final article = widget.article;
    final colors = context.facteurColors;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate = _playEntry && !reduceMotion;
    final row = _buildRow(context, colors, article, popCheck: animate);
    if (!animate) return row;
    // Glissée depuis la gauche + fondu : la ligne « se range » visiblement dans
    // la liste. Un simple fade + scale 0.98 (première itération) était
    // imperceptible — l'AnimatedSize pousse la liste au même moment et un scale
    // de 2 % sur 64px fait bouger ~1px.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: FacteurDurations.slow,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(-16 * (1 - t), 0),
          child: child,
        ),
      ),
      child: row,
    );
  }

  Widget _buildRow(
    BuildContext context,
    FacteurColors colors,
    EssentielArticle article, {
    required bool popCheck,
  }) {
    final sourceState = widget.sourceState;
    final readState = widget.readState;
    final onTap = widget.onTap;
    final onPreviewStart = widget.onPreviewStart;
    return ArticlePreviewGesture(
      contentBuilder: () => article.toPreviewContent(),
      onLongPressStart: onPreviewStart,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: opacityForReadState(readState),
          child: AnimatedFeedCard(
            isCompleted: readState == ReadState.completed,
            animate: false,
            child: SizedBox(
              height: kTriageKeptSlotHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // La coche « pope » (0 → léger dépassement → 1,
                  // easeOutBack) à l'entrée d'une nouvelle gardée : c'est le
                  // point de satisfaction du « Je garde », sans haptique
                  // supplémentaire. Statique sur les lignes déjà en place.
                  if (popCheck)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: FacteurDurations.slow,
                      curve: Curves.easeOutBack,
                      builder: (context, t, child) =>
                          Transform.scale(scale: t, child: child),
                      child: Icon(
                        PhosphorIcons.check(),
                        size: 14,
                        color: colors.sectionEssentiel,
                      ),
                    )
                  else
                    Icon(
                      PhosphorIcons.check(),
                      size: 14,
                      color: colors.sectionEssentiel,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _SourceLine(
                          name: article.sourceName,
                          state: sourceState,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (readState != ReadState.unread) ...[
                    const SizedBox(width: 8),
                    ReadStateMark(
                      color: colors.success,
                      state: readState,
                      size: 18,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de progression segmentée, rendue **entre** la barre d'actions et le
/// contrôle d'objectif (reprise PO 10/08 — la progression visuelle revient, le
/// contrôle garde sa place).
///
/// **Elle compte les gardés, plus les triés** (33.4) : un segment par article
/// de la cible, rempli à mesure que l'utilisateur en garde. C'est la seule
/// lecture qui suive l'objectif du jour — le nombre d'articles restant à trier
/// n'est plus déterminé (le pool s'allonge), l'afficher mentirait.
///
/// Il n'y a donc plus de segment « courant » : la progression n'est plus
/// positionnelle, elle est cumulative. La barre ne porte **aucun compteur**
/// visible ; le chiffre vit dans le contrôle juste dessous, et dans la
/// sémantique de ce nœud.
class TriageProgressBar extends StatelessWidget {
  final EssentielTriageState triage;

  const TriageProgressBar({super.key, required this.triage});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (!triage.hasStarted) {
      return const SizedBox(height: kTriageProgressBarHeight);
    }
    final goal = triage.effectiveGoal;
    final kept = triage.keptCount;
    final segments = math.min(goal, kTriageProgressMaxSegments);
    // Cas rare : « Plus d'articles ? » a poussé la cible au-delà du plafond de
    // segments. On proratise plutôt que d'ajouter des traits illisibles.
    final filled = goal <= segments ? kept : (kept * segments / goal).round();
    // La barre reste un repère périphérique, jamais une jauge — mais l'écart
    // entre acquis et restant doit se lire d'un coup d'œil (reprise PO 11/08) :
    // le segment rempli remonte de 0.35 à 0.45, le segment vide descend à 0.45
    // du filet, plus proche du fond de carte.
    final fill = colors.sectionEssentiel.withValues(alpha: 0.45);
    final empty = colors.border.withValues(alpha: 0.45);
    return SizedBox(
      height: kTriageProgressBarHeight,
      child: Semantics(
        // Un seul nœud, jamais N segments bavards. C'est lui qui porte le
        // chiffre : l'affichage visuel continue de n'en porter aucun.
        label: 'Articles gardés : $kept sur $goal',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < segments; i++) ...[
              if (i > 0) const SizedBox(width: kTriageProgressSegmentGap),
              Expanded(
                child: AnimatedContainer(
                  key: ValueKey('triage-progress-segment-$i'),
                  duration: FacteurDurations.medium,
                  curve: Curves.easeOutCubic,
                  height: kTriageProgressSegmentHeight,
                  decoration: BoxDecoration(
                    color: i < filled ? fill : empty,
                    borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Contrôle compact sous les boutons : « Garder [−] N [+] articles ».
///
/// **N est le nombre d'articles à garder** (33.4), plus la taille du slate : le
/// stepper ne touche donc plus au pool, et le fragment « · Y à trier » a
/// disparu — le reste à trier n'est plus déterminé.
///
/// Hiérarchie voulue (reprises PO 10/08 puis 11/08) : c'est un **réglage
/// discret**, pas un titre — et il doit s'effacer davantage encore. La phrase
/// s'est raccourcie (« Je veux lire … articles aujourd'hui » → « Garder …
/// articles ») : moins de mots, donc moins de masse au centre de la carte, et
/// une formulation qui nomme l'action du tri plutôt que d'énoncer une intention.
/// Les ronds encadrent immédiatement le chiffre — ils sont ce qui le règle, les
/// pousser aux deux extrémités de la largeur cassait ce lien — et le chiffre
/// lui-même est passé en `textSecondary` 13/w600 : il reste le repère à lire de
/// la ligne, sans rivaliser avec le titre de la carte.
class TriageGoalControl extends ConsumerWidget {
  final EssentielTriageState triage;

  const TriageGoalControl({super.key, required this.triage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final current = triage.effectiveGoal;

    void nudge(int delta) =>
        ref.read(essentielTriageProvider.notifier).setGoal(current + delta);

    // `textTertiary` en 11.5 (était 12) : la phrase est un habillage du
    // réglage, seul le chiffre N — en `textSecondary` 13/w600 — est le repère
    // à lire.
    final labelStyle = TextStyle(fontSize: 11.5, color: colors.textTertiary);
    return SizedBox(
      height: kTriageTargetControlHeight,
      child: Row(
        children: [
          Text('Garder', style: labelStyle),
          _TargetRound(
            icon: PhosphorIcons.minus(),
            semanticLabel: 'Moins d\'articles',
            enabled: current > kTriageGoalMin,
            onTap: () => nudge(-1),
          ),
          Text(
            '$current',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
          _TargetRound(
            icon: PhosphorIcons.plus(),
            semanticLabel: 'Plus d\'articles',
            enabled: current < kTriageGoalMax,
            onTap: () => nudge(1),
          ),
          // `Flexible` et non `Expanded` : la phrase s'élide sur une carte
          // étroite au lieu de pousser les ronds hors du cadre.
          Flexible(
            child: Text(
              'articles',
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau « tu peux t'arrêter là », proposé après
/// [kTriageStopNudgeThreshold] refus enchaînés.
///
/// Réutilise [NudgeInlineBanner] pour le rendu, **sans passer par
/// `NudgeCoordinator`** : son cooldown global de 24 h et son budget de session
/// sont faits pour des sollicitations transverses, pas pour un signal
/// contextuel intra-session qui doit apparaître au moment exact où
/// l'utilisateur s'entête. C'est la justification déjà écrite pour
/// `preview_nudge_scheduler.dart`.
///
/// Il **disparaît de lui-même** dès qu'un article est gardé, sans code de
/// nettoyage : `consecutivePassCount` repart de 0.
class _TriageStopNudge extends StatelessWidget {
  final VoidCallback onStop;
  final VoidCallback onDismiss;

  const _TriageStopNudge({required this.onStop, required this.onDismiss});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
        child: NudgeInlineBanner(
          // Sobre et non personnifié (contrainte de copy PO) : l'icône dit la
          // pause proposée, elle ne fait pas parler l'app.
          icon: PhosphorIcons.pause(),
          body: 'Rien ne t\'accroche ? Tu peux t\'arrêter là.',
          actionLabel: 'Arrêter le tri',
          onAction: onStop,
          onDismiss: onDismiss,
        ),
      );
}

/// Rond `−` / `+` du contrôle d'objectif : cercle **visible** de
/// [kTriageTargetRoundSize], cible tactile de [kTriageTargetControlHeight].
///
/// Les 9px transparents de chaque côté du cercle sont l'écart au chiffre : le
/// bouton reste collé à ce qu'il règle sans sacrifier l'accessibilité. Aux
/// bornes `[kTriageGoalMin, kTriageGoalMax]`, le bouton est visiblement éteint
/// **et** non actionnable (`onTap: null` ⇒ l'`InkWell` ne prend même pas le tap).
class _TargetRound extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onTap;

  const _TargetRound({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      // L'`InkWell` porte la **boîte de 44**, pas le cercle : c'est ce qui fait
      // la cible tactile. Le cercle de 26 n'est plus qu'un décor centré dedans
      // — l'inverse (InkWell sur le cercle, boîte de 44 autour) rendait les 9px
      // de marge inertes et la cible restait à 26.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: kTriageTargetControlHeight,
            height: kTriageTargetControlHeight,
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : 0.35,
                child: Container(
                  width: kTriageTargetRoundSize,
                  height: kTriageTargetRoundSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(icon, size: 14, color: colors.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// En-tête de la liste des gardés (design 2A) : « TES ARTICLES », un filet qui
/// prend le reste de la largeur, puis le compte en accent. Rendu uniquement
/// quand la liste est non vide, **dans** son `AnimatedSize` pour apparaître
/// avec elle.
class _KeptListHeader extends StatelessWidget {
  final int count;
  final Color accent;

  const _KeptListHeader({required this.count, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final labelStyle = GoogleFonts.courierPrime(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: colors.textTertiary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          Text('TES ARTICLES', style: labelStyle),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: colors.border)),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: labelStyle.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

/// Coche « suivie » / étoile « favorite » posée à droite du nom de source.
///
/// Réutilise l'idiome visuel canonique des intérêts ([InterestStateVisuals]) au
/// lieu d'en réinventer un : même icône et même accent que les pastilles de
/// « Mes intérêts ». Ne rend **que** `followed` et `favorite` — un état neutre
/// ou masqué n'a rien à signaler sur une carte à trier.
class _SourceStateMark extends StatelessWidget {
  final InterestState? state;

  const _SourceStateMark({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s != InterestState.followed && s != InterestState.favorite) {
      return const SizedBox.shrink();
    }
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        label: s!.label,
        child: Icon(s.iconData, size: 12, color: s.accent(colors)),
      ),
    );
  }
}

/// Nom de source suivi de son éventuelle marque d'intérêt — sur la carte à
/// trier comme sur les lignes gardées. Le nom s'élide avant la marque : le
/// signal « je suis cette source » ne doit jamais être ce qui saute.
class _SourceLine extends StatelessWidget {
  final String name;
  final TextStyle style;
  final InterestState? state;

  const _SourceLine({
    required this.name,
    required this.style,
    required this.state,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          _SourceStateMark(state: state),
        ],
      );
}

/// Barre d'actions compacte : ✕ · signet · bouton plein « Je garde ».
///
/// Doublon volontaire du geste : le tri doit rester possible **sans swipe**
/// (accessibilité, et utilisateurs qui ne découvrent pas le geste).
class _ActionBar extends StatelessWidget {
  final VoidCallback onPass;
  final VoidCallback onLater;
  final VoidCallback onKeep;

  const _ActionBar({
    required this.onPass,
    required this.onLater,
    required this.onKeep,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return SizedBox(
      height: kTriageActionBarHeight,
      child: Row(
        children: [
          _RoundButton(
            icon: PhosphorIcons.x(),
            semanticLabel: 'Pas pour moi',
            color: colors.textSecondary,
            onTap: onPass,
          ),
          const SizedBox(width: kTriageActionGap),
          _RoundButton(
            icon: PhosphorIcons.bookmarkSimple(),
            semanticLabel: 'Plus tard',
            color: colors.textSecondary,
            onTap: onLater,
          ),
          const SizedBox(width: kTriageActionGap),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Je garde',
              child: Material(
                color: colors.primary,
                borderRadius: BorderRadius.circular(FacteurRadius.pill),
                child: InkWell(
                  borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  onTap: onKeep,
                  child: SizedBox(
                    height: kTriageActionButtonSize,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.checkCircle(
                              PhosphorIconsStyle.fill,
                            ),
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Je garde',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  const _RoundButton({
    required this.icon,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: colors.backgroundSecondary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: kTriageActionButtonSize,
            height: kTriageActionButtonSize,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

/// Balises du pied de carte (design 2A), par ordre de priorité :
/// la **primaire** dit d'où vient l'article ([cover] : polarisation +
/// couverture), les secondaires le situent ([theme], [fresh]).
enum _TriageTag { cover, theme, fresh }

/// Balises à rendre au pied de la carte de tri, règle du design 2A : une carte
/// **avec image** ne porte qu'**une** balise (la primaire si elle existe, sinon
/// la première secondaire) ; une carte sans image en porte jusqu'à **deux**
/// (primaire puis secondaires). Fonction pure — la disponibilité de chaque
/// balise dérive des seuls signaux du modèle.
///
/// Les balises `newsource` / `social` / `format (durée)` du design n'ont aucun
/// signal côté données ([EssentielArticle] ne porte ni temps de lecture, ni
/// ancienneté de source, ni compteur social) : hors périmètre.
List<_TriageTag> _triageCardTags(
  EssentielArticle article, {
  required bool hasImage,
}) {
  final tags = <_TriageTag>[
    if (article.coverageCount >= kCoverageChipMinSources ||
        article.divergenceLevel != null)
      _TriageTag.cover,
    if (themeMap.containsKey(article.theme)) _TriageTag.theme,
    // La fraîcheur est toujours disponible (`publishedAt` est requis).
    _TriageTag.fresh,
  ];
  return tags.take(hasImage ? 1 : 2).toList(growable: false);
}

/// Le contenu de la carte du dessus : bandeau image (quand il y en a une),
/// source, titre, puis les balises du design 2A ([_triageCardTags]). Pas de
/// chapô : à ce stade on choisit, on ne lit pas encore.
class _TriageArticleCard extends StatelessWidget {
  final EssentielArticle article;

  /// État d'intérêt de la source (coche/étoile à droite du nom). `null` ⇒ rien
  /// à signaler.
  final InterestState? sourceState;

  /// État de lecture effectif — grise la carte et pose la coche quand
  /// l'article a été ouvert/lu (idiome `_LeadTile`). La carte du **dessous**
  /// reste au défaut : le signal appartient au haut de pile.
  final ReadState readState;

  const _TriageArticleCard({
    required this.article,
    required this.sourceState,
    this.readState = ReadState.unread,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Décidé à la composition, jamais pendant le geste : la carte ne se replie
    // pas sous le doigt si l'image échoue en cours de route (l'échec est mis en
    // cache et prendra effet au rendu suivant).
    final hasImage = triageCardHasImage(article.thumbnailUrl);
    final tags = _triageCardTags(article, hasImage: hasImage);
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      // `min` de bout en bout : la carte prend la hauteur de ce qu'elle affiche
      // vraiment. Le titre n'est plus un `Expanded` — il occupait tout l'espace
      // restant d'un slot figé, donc un titre court étirait du vide et
      // repoussait la méta en bas de carte (défaut « la carte ne s'adapte pas au
      // contenu », E2E PO). Il reste borné par `maxLines`.
      child: Opacity(
        opacity: opacityForReadState(readState),
        child: AnimatedFeedCard(
          isCompleted: readState == ReadState.completed,
          animate: false,
          child: Stack(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pas de bandeau du tout sans image (décision PO) : plus
                  // d'aplat gris imposé. Une carte sans image est simplement
                  // plus courte, son titre respire sur 6 lignes — et plus
                  // grand (alignement typographique 2A).
                  if (hasImage)
                    _TriageCardBanner(imageUrl: article.thumbnailUrl),
                  Padding(
                    padding: hasImage
                        ? const EdgeInsets.symmetric(
                            horizontal: kTriageCardPaddingH,
                            vertical: kTriageCardPaddingV,
                          )
                        : const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceLine(
                          name: article.sourceName,
                          state: sourceState,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          article.title,
                          maxLines: hasImage ? 4 : 6,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            fontSize: hasImage ? 19 : 22,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // `Flexible` sur chaque balise : un libellé long
                              // (thème + fraîcheur sur carte étroite) s'élide
                              // au lieu de déborder du cadre.
                              for (var i = 0; i < tags.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Flexible(
                                  child: _TriageTagView(
                                    tag: tags[i],
                                    article: article,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (readState != ReadState.unread)
                Positioned(
                  top: 8,
                  right: 8,
                  child: ReadStateMark(
                    color: colors.success,
                    state: readState,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rendu d'une balise du pied de carte ([_triageCardTags]) :
///
/// - [_TriageTag.cover] — pilule bordée qui **réutilise** le vocabulaire
///   visuel existant ([DivergenceInlineBadge] icône seule + [CoverageChip]),
///   aucune nouvelle pastille ;
/// - [_TriageTag.theme] — pilule bordée, libellé discret du thème ;
/// - [_TriageTag.fresh] — nue : horloge + fraîcheur `timeago` (« il y a 2 h »).
class _TriageTagView extends StatelessWidget {
  final _TriageTag tag;
  final EssentielArticle article;

  const _TriageTagView({required this.tag, required this.article});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    switch (tag) {
      case _TriageTag.cover:
        final showCoverage = article.coverageCount >= kCoverageChipMinSources;
        return _TagPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (article.divergenceLevel != null)
                DivergenceInlineBadge(
                  divergenceLevel: article.divergenceLevel,
                  iconOnly: true,
                ),
              if (article.divergenceLevel != null && showCoverage)
                const SizedBox(width: 6),
              if (showCoverage)
                CoverageChip(
                  key: const Key('triage-coverage-chip'),
                  sourceCount: article.coverageCount,
                  sources: article.perspectiveSources,
                  colors: colors,
                ),
            ],
          ),
        );
      case _TriageTag.theme:
        return _TagPill(
          child: Text(
            themeMap[article.theme]!.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: colors.textSecondary),
          ),
        );
      case _TriageTag.fresh:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.clock(),
              size: 12,
              color: colors.textTertiary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                timeago.format(article.publishedAt, locale: 'fr'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
          ],
        );
    }
  }
}

/// Pilule des balises du pied de carte (padding 3/9, rayon pill). Aligne son
/// vocabulaire visuel sur celui du design system ([EditorialBadge]) : un aplat
/// gris subtil et sans bordure — sobre et élégant — plutôt qu'un contour.
class _TagPill extends StatelessWidget {
  final Widget child;

  const _TagPill({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: colors.textSecondary.withValues(alpha: isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: child,
    );
  }
}

/// L'article porte-t-il une image exploitable ? `false` ⇒ carte texte,
/// naturellement plus courte, **sans bandeau du tout**.
///
/// `FacteurThumbnail.failedUrls` est le cache d'URLs mortes de la session : une
/// URL déjà perdue vaut absence d'image, sans nouvelle tentative.
///
/// Vit ici et non dans `section_fit.dart`, qui est délibérément de
/// l'arithmétique pure sans binding Flutter — seule la constante y est exposée.
bool triageCardHasImage(String? url) =>
    url != null && url.isNotEmpty && !FacteurThumbnail.failedUrls.contains(url);

/// Bandeau image en tête de carte, rendu **uniquement quand il y a une image**
/// ([triageCardHasImage]) : plus d'aplat de secours imposé (décision PO), une
/// carte sans image est une carte texte plus courte.
///
/// Le slot garde une hauteur fixe [kTriageCardImageHeight] : une image qui
/// échoue *en cours de chargement* laisse un vide transparent et se replie au
/// **rendu suivant** (via `FacteurThumbnail.markFailed`), jamais au milieu du
/// geste.
class _TriageCardBanner extends StatelessWidget {
  final String? imageUrl;

  const _TriageCardBanner({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) return const SizedBox.shrink();

    return SizedBox(
      key: const Key('triage-card-banner'),
      height: kTriageCardImageHeight,
      width: double.infinity,
      child: FacteurImage(
        imageUrl: url,
        fit: BoxFit.cover,
        height: kTriageCardImageHeight,
        memCacheWidth: (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round(),
        placeholder: (_) => const SizedBox.shrink(),
        errorWidget: (_) {
          FacteurThumbnail.markFailed(url);
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
