import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../grille/widgets/dashed_border.dart';
import '../../../shared/widgets/read_state_mark.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../feed/models/content_model.dart';
import '../../feed/services/read_sync_service.dart';
import '../../feed/widgets/animated_feed_card.dart';
import '../../detail/content_preview_mapper.dart';
import '../../tour/tour_anchors.dart';
import '../../settings/models/display_mode_spec.dart';
import '../../settings/providers/display_mode_provider.dart';
import '../models/flux_continu_models.dart';
import '../models/weather_snapshot.dart';
import '../providers/edition_read_status_provider.dart';
import '../providers/essentiel_extra_articles_provider.dart';
import '../providers/essentiel_triage_provider.dart';
import '../providers/selected_edition_date_provider.dart';
import '../providers/weather_provider.dart';
import '../services/tournee_progress_service.dart';
import '../utils/section_fit.dart';
import '../utils/theme_color_mapping.dart';
import 'article_impression_tracker.dart';
import 'auto_grow_candidate.dart';
import 'coverage_chip.dart';
import 'edition_timeline_sheet.dart';
import 'essentiel_triage_stack.dart';
import 'triage_stack_skeleton.dart';
import 'ephemeral_rattraper_label.dart';
import 'weather_condition_icon.dart';
import 'weather_detail_sheet.dart';

/// Carte hi-fi unique "L'Essentiel du jour".
///
/// Présente jusqu'à 5 articles transversaux du jour :
///   - `articles[0]` → lead (fond teinté, bord gauche accent)
///   - `articles[1..2]` → médiums (filets fins)
///   - `articles[3..4]` → lights (filet pointillé, une ligne tronquée)
class EssentielHiFiCard extends ConsumerStatefulWidget {
  final List<EssentielArticle> articles;
  final void Function(EssentielArticle article) onTapArticle;

  /// Carrousel du jour, source des articles réinjectés par « Voir d'autres
  /// articles » au tri terminé (itération PO 33.1). `null` ⇒ pas d'articles en
  /// plus à proposer.
  final FeedCarouselData? carousel;

  /// Jour Tournée courant. Non-null ⇒ chaque tuile compte une impression
  /// (`surface: essentiel`). `null` sur les éditions passées en lecture seule.
  final String? impressionDayKey;

  /// Rang du héros dans la page et nombre de cartes rendues avant lui —
  /// toujours 0/0 aujourd'hui (le héros ouvre la Tournée), mais portés en
  /// paramètre pour que la mesure ne dépende pas de cette hypothèse.
  final int sectionIndex;
  final int globalPositionOffset;
  final bool isSerene;

  const EssentielHiFiCard({
    super.key,
    required this.articles,
    required this.onTapArticle,
    this.carousel,
    this.impressionDayKey,
    this.sectionIndex = 0,
    this.globalPositionOffset = 0,
    this.isSerene = false,
  });

  /// Enveloppe une tuile dans son compteur d'impression ; passe-plat quand la
  /// mesure n'est pas câblée (lecture seule).
  Widget _tracked({
    required EssentielArticle article,
    required int position,
    required Widget child,
  }) {
    final dayKey = impressionDayKey;
    if (dayKey == null) return child;
    return ArticleImpressionTracker(
      dayKey: dayKey,
      info: ArticleImpressionInfo(
        contentId: article.contentId,
        sectionKey: 'essentiel_v3',
        sectionFamily: 'editorial',
        surface: 'essentiel',
        sectionIndex: sectionIndex,
        positionInSection: position,
        globalPosition: globalPositionOffset + position,
        // Le héros ne passe pas par le moteur de scoring personnalisé
        // (`recommendation_reason` est nul sur le chemin editorial_v3) : pas de
        // score à porter, et c'est une propriété du produit, pas un trou.
        theme: article.theme,
        sourceId: article.sourceId,
        isSerene: isSerene,
      ),
      child: child,
    );
  }

  @override
  ConsumerState<EssentielHiFiCard> createState() => _EssentielHiFiCardState();
}

class _EssentielHiFiCardState extends ConsumerState<EssentielHiFiCard> {
  bool _startScheduled = false;
  bool _prefetchScheduled = false;
  bool _pruneScheduled = false;

  /// La pile de tri a-t-elle été rendue pendant ce montage ? C'est le
  /// déclencheur de la révélation de fin de tri ([_TriageDoneReveal]) : elle ne
  /// se joue que sur la transition vécue pile → tri terminé. Un cold-boot dont
  /// le tri est déjà terminé rend la liste des gardés d'emblée, sans animation
  /// — la fin de tri est un événement, pas un état.
  bool _sawTriageActive = false;

  // Mémo du pool adressable (slate du jour + articles du carrousel adaptés).
  // Les deux entrées sont des champs du widget, qui ne dépendent d'aucun
  // provider watché ici — alors que la carte, elle, se reconstruit à **chaque**
  // décision de tri et à chaque émission des providers de session. Sans ce
  // mémo, chaque rebuild réallouait un Set, jusqu'à 5 `EssentielArticle` et
  // deux listes, presque toujours pour rien (le pool n'est lu que sur les
  // chemins de tri).
  List<EssentielArticle>? _memoArticles;
  FeedCarouselData? _memoCarousel;
  List<EssentielArticle> _memoFetched = const [];
  List<EssentielArticle> _memoPool = const [];
  Set<String> _memoPoolIds = const {};

  /// [fetched] = articles rapatriés par « Plus d'articles ? » quand la réserve
  /// locale était épuisée ([essentielExtraArticlesProvider]). Ils entrent dans
  /// le pool **en queue**, après le carrousel : le préfixe (slate backend puis
  /// carrousel) ne bouge jamais, donc rien de ce qui est déjà affiché n'est
  /// rebattu, ni au tri ni au cold-boot.
  void _refreshPoolMemo(List<EssentielArticle> fetched) {
    final articles = widget.articles;
    final carousel = widget.carousel;
    if (identical(_memoArticles, articles) &&
        identical(_memoCarousel, carousel) &&
        identical(_memoFetched, fetched)) {
      return;
    }
    _memoArticles = articles;
    _memoCarousel = carousel;
    _memoFetched = fetched;

    // Articles réinjectables : les items du carrousel du jour non déjà dans le
    // slate, adaptés en articles triables. Rangs au-delà du slate d'origine (le
    // backend accepte leur tri avec le `slate_size` **courant** que `decide()`
    // envoie — le slate s'allonge, la borne de schéma a été relevée en 33.4).
    final seen = {for (final a in articles) a.contentId};
    final extra = <EssentielArticle>[];
    final items = carousel?.items ?? const [];
    for (var i = 0; i < items.length; i++) {
      if (!seen.add(items[i].id)) continue; // déjà dans le slate
      extra.add(
        EssentielArticle.fromContent(items[i], rank: articles.length + i + 1),
      );
    }
    // Articles rapatriés au réseau, dédupés contre tout ce qui précède.
    final fetchedFresh = [
      for (final a in fetched)
        if (seen.add(a.contentId)) a,
    ];
    // Pool adressable par la pile : slate du jour + articles injectables. Le
    // slate (`syncSlate`) reçoit ce pool **ordonné** et le porte en entier — il
    // n'est plus coupé à la cible (33.4), c'est le nombre de gardés qui borne
    // le tri.
    _memoPool = List.unmodifiable([...articles, ...extra, ...fetchedFresh]);
    _memoPoolIds = {for (final a in _memoPool) a.contentId};
  }

  /// Répare un slate figé qui référence un article que le pool ne porte plus.
  ///
  /// Sans ça la pile n'a pas de haut à rendre et la carte se réduit à son
  /// en-tête au-dessus d'un aplat de fond, indéfiniment (défaut E2E « aucun
  /// squelette pendant le chargement » : l'aplat n'était pas une attente, mais
  /// un état cassé). Le cas le plus fréquent : « Plus d'articles » a persisté
  /// dans le slate des `contentId` du **carrousel**, absent de l'hydratation
  /// depuis le cache au cold-boot suivant.
  ///
  /// Posté après la frame (muter un provider pendant le build est interdit) et
  /// déclenché **uniquement** quand le haut de pile est irrésolvable, donc
  /// jamais sur le chemin nominal. `pruneUnavailable` est strictement
  /// décroissant ⇒ aucune boucle possible.
  void _schedulePruneUnavailable() {
    if (_pruneScheduled) return;
    _pruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pruneScheduled = false;
      if (!mounted) return;
      ref.read(essentielTriageProvider.notifier).pruneUnavailable(_memoPoolIds);
      // Un slate **entièrement** introuvable se vide : le gel doit alors
      // pouvoir rejouer sur les articles du jour. Sans ce déverrouillage, le
      // verrou une-fois-par-montage de [_scheduleStart] laissait la carte sur
      // sa silhouette indéfiniment — le bug qu'on vient de corriger, déplacé
      // d'un cran.
      _startScheduled = false;
    });
  }

  /// Aligne le slate du jour sur le pool. Appelé depuis `build` **uniquement**
  /// quand toutes les conditions sont déjà réunies, et exécuté après la frame :
  /// muter un provider pendant le build est interdit par Riverpod.
  ///
  /// Le gel de l'ordre se fait à la première frame de la pile, pas au premier
  /// geste : un refetch glissé entre l'affichage et le premier swipe changerait
  /// sinon la carte du dessus sous le doigt. Les appels suivants ne font
  /// qu'**allonger la queue** ([EssentielTriageNotifier.syncSlate]) — c'est ce
  /// qui remplace la réconciliation de cible de la 33.3 (carrousel arrivant
  /// après le héros) et ce qui fait entrer les articles prefetchés dans la pile.
  ///
  /// Le verrou n'est pas « une fois par montage » mais « un post par frame » :
  /// le pool grandit en cours de tri, chaque agrandissement doit passer.
  void _scheduleSyncSlate() {
    if (_startScheduled) return;
    _startScheduled = true;
    final snapshot = _memoPool.map((a) => a.contentId).toList(growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScheduled = false;
      if (!mounted) return;
      ref.read(essentielTriageProvider.notifier).syncSlate(snapshot);
    });
  }

  /// Va chercher la suite **avant** que la pile ne sèche (Story 33.4).
  ///
  /// C'est ce qui rend l'objectif « N articles à garder » tenable : sans lui,
  /// `/more` n'était appelé que par le tap sur « Plus d'articles ? » et la pile
  /// s'arrêtait sur le pool du matin, quel que soit le nombre de refus.
  ///
  /// Aucune UI d'attente : c'est un prefetch, il ne doit rien bloquer ni faire
  /// clignoter. Les articles rapatriés entrent dans `_memoPool` par le chemin
  /// déjà en place, et `syncSlate` les append au build suivant.
  ///
  /// Les gardes anti-boucle vivent dans le notifier ([_inFlight], cooldown
  /// d'épuisement, plafond de prefetchs) — la carte n'a que le verrou de frame.
  void _schedulePrefetchMore(List<String> poolIds) {
    if (_prefetchScheduled) return;
    if (!ref.read(essentielExtraArticlesProvider.notifier).canAutoFetch()) {
      return;
    }
    _prefetchScheduled = true;
    // Exclusions **ordonnées** (slate d'abord, puis pool) et non depuis un
    // `Set` non ordonné : le backend borne la liste, et ce qui saute à la
    // troncature doit être ce qui compte le moins.
    final triage = ref.read(essentielTriageProvider);
    final seen = <String>{};
    final exclude = [
      for (final id in [...triage.slate, ...triage.decisions.keys, ...poolIds])
        if (seen.add(id)) id,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _prefetchScheduled = false;
        return;
      }
      try {
        await ref.read(essentielExtraArticlesProvider.notifier).fetchMore(
              excludeIds: exclude,
              limit: kTriagePrefetchBatch,
            );
      } catch (e) {
        debugPrint('EssentielHiFiCard: prefetch failed: $e');
      } finally {
        if (mounted) _prefetchScheduled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final articles = widget.articles;
    final onTapArticle = widget.onTapArticle;
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final accent = colors.sectionEssentiel;
    final spec = ref.watch(displayModeSpecProvider);

    // Articles rapatriés au réseau (Story 33.3, puis prefetch automatique en
    // 33.4) : ils font partie du pool au même titre que le carrousel, et leur
    // hydratation asynchrone gate l'élagage du slate (cf.
    // `_schedulePruneUnavailable`).
    final extraState = ref.watch(essentielExtraArticlesProvider);
    _refreshPoolMemo(extraState.articles);
    final pool = _memoPool;
    // Pool **ordonné** (slate, carrousel, puis rapatriés) : le slate et les
    // exclusions envoyées au backend raisonnent sur cette même liste.
    final poolIds = [for (final a in pool) a.contentId];

    // Un seul point de lecture des providers de session : l'état dérivé descend
    // ensuite dans les tuiles, qui restent des `StatelessWidget`.
    final completedIds = ref.watch(completedContentIdsProvider);
    final consumedIds = ref.watch(consumedContentIdsProvider);
    ReadState readStateFor(EssentielArticle a) => effectiveReadState(
          a.readState,
          consumedThisSession: consumedIds.contains(a.contentId),
          completedThisSession: completedIds.contains(a.contentId),
        );

    // EPIC « Lettre du jour » — déclencheur « rewind » dans l'en-tête. Toujours
    // affiché (today ET passé) ; ouvre la timeline en overlay. La carte étant
    // l'unique héros Essentiel rendu dans les deux vues (live + passée), le
    // brancher ici le fait apparaître partout.
    //
    // « Rattraper » n'est plus un libellé fixe mais un **signal contextuel**
    // (décision PO « header épuré à jour ») :
    // - à jour → icône ⏪ seule (toujours tappable, ouvre la timeline) ;
    // - édition d'hier non ouverte → **point rouge** persistant sur ⏪ + le nudge
    //   éphémère « Rattraper ? » (fondu-in ~1 s / tient 2 s / fondu-out, ≤1×/j) ;
    // - lettre passée → « Revenir » fixe (état de navigation, inchangé).
    // Le titre de la section porte, lui, la date sélectionnée (« Hier » vs
    // « Ton Essentiel »).
    final selection = ref.watch(selectedEditionDateProvider);
    final isToday = selection is EditionToday;
    // « En retard » = today ET édition d'hier (J-1) non ouverte. Dégradation
    // gracieuse : `missedYesterday()` renvoie `false` si les streaks sont
    // indisponibles → aucun faux positif au cold-boot.
    final missedYesterday =
        isToday && ref.watch(editionReadStatusProvider).missedYesterday();
    final headerTitle = isToday ? 'Ton Essentiel' : editionPillLabel(selection);
    // La ligne sous le titre suit la même sélection que lui : « choisis » ne
    // vaut que pour la pile du jour, une lettre passée ou la rétro hebdo se
    // présentent (cf. `editionSubtitleLabel`).
    final headerSubtitle = editionSubtitleLabel(selection);

    // Story 33.1 — la carte est une pile à trier tant que le tri du jour n'est
    // pas fini. Jamais sur une édition passée : une lettre passée est figée,
    // la trier n'aurait aucun sens et polluerait la jauge avec des décisions
    // hors slate du jour.
    final triage = ref.watch(essentielTriageProvider);
    final canTriage = isToday && articles.isNotEmpty && triage.hydrated;
    var pendingPoolIds = 0;
    if (canTriage) {
      // Le slate porte tout le pool proposé (33.4) : tout id du pool qui n'y
      // est pas encore doit l'y rejoindre, en queue. C'est aussi ce qui fait
      // entrer les articles prefetchés dans la pile.
      final inSlate = triage.slate.toSet();
      // Articles du pool pas encore entrés dans le slate. Ils sont par
      // construction non décidés, donc ils comptent dans ce qui reste à
      // proposer — et c'est ce qui évite un second prefetch pendant la frame
      // où `syncSlate` n'a pas encore couru.
      pendingPoolIds = poolIds.where((id) => !inSlate.contains(id)).length;
      if (!triage.hasStarted || pendingPoolIds > 0) _scheduleSyncSlate();
    }
    final showTriage = canTriage && triage.isActive;
    if (showTriage) _sawTriageActive = true;
    // **Alimentation continue de la pile** (33.4) : dès qu'il reste moins de
    // deux articles à proposer et que la cible de gardés n'est pas atteinte, on
    // va chercher la suite. Sans ça, l'objectif « N articles à garder » ne
    // serait qu'une promesse : la pile s'arrêterait sur le pool du matin.
    final remainingToTriage =
        (triage.slate.length - triage.index) + pendingPoolIds;
    if (showTriage &&
        !triage.goalReached &&
        remainingToTriage <= kTriagePrefetchLowWaterMark) {
      _schedulePrefetchMore(poolIds);
    }
    // Haut de pile introuvable dans le pool ⇒ le slate a survécu à l'article
    // qu'il désigne. La pile rend la silhouette (jamais un corps vide) et on
    // programme la réparation du slate.
    // `extraState.hydrated` est une **condition de sûreté**, pas un détail : un
    // article rapatrié au réseau vit dans SharedPreferences, relu en asynchrone.
    // Élaguer avant sa relecture retirerait du slate l'article que
    // l'utilisateur a demandé la veille — le redémarrage annulerait sa décision
    // d'élargir sa pile.
    if (showTriage &&
        extraState.hydrated &&
        !_memoPoolIds.contains(triage.currentContentId)) {
      _schedulePruneUnavailable();
    }
    final triageDone = canTriage && triage.done;
    // Rien de **définitif** à rendre. Deux causes, une seule sortie : la
    // silhouette. Aucun chemin ne doit laisser la carte se réduire à son
    // en-tête au-dessus du vide (défaut A1, passe PO 09/08).
    //
    // 1. **Héros pas encore résolu** (`articles` vide). Convention du provider,
    //    désormais explicite des deux côtés : `_buildEssentielSection` renvoie
    //    `null` quand l'endpoint a répondu sans rien (dégradation gracieuse :
    //    pas de carte du tout), tandis qu'une `EssentielSection` **vide**
    //    signifie « pas encore résolu ». C'est la coquille posée par
    //    `_buildSkeletonState` : elle échappe au squelette d'écran dès qu'un
    //    `_compose()` non-squelette est publié pendant le bootstrap
    //    (`_reconcilePlacementThenSync`, délibérément non gardé par
    //    `_bootstrapping`), et la carte restait alors un en-tête nu pendant
    //    tout le fan-out.
    // 2. **Tri indéterminé** : SharedPrefs pas encore lu (`hydrated`) ou slate
    //    pas encore figé (`startIfNeeded` est posté après la frame). Rendre la
    //    liste passive ici ferait clignoter l'ancienne mise en page avant la
    //    pile — et sur un boot tiède (snapshot Hive frais, donc jamais de
    //    squelette d'écran) c'était le seul rendu que l'utilisateur voyait de
    //    l'attente.
    //
    // Effet de bord assumé : qui a **déjà terminé** son tri voit la silhouette
    // 1 à 3 frames avant sa liste de gardés. Strictement mieux que la mise en
    // page fausse, et l'hydratation SharedPreferences est en cache mémoire dès
    // le premier appel du process.
    final contentPending = articles.isEmpty ||
        (isToday && (!triage.hydrated || !triage.hasStarted));

    // Liste rendue en mode passif (hors pile de tri). Après un tri terminé, la
    // carte ne montre **que les articles gardés** (« Je garde » + « Plus tard »),
    // dans l'ordre du slate : les rejetés ne réapparaissent pas (décision PO,
    // renverse la tension documentée en 33.1). En dehors du tri terminé, c'est
    // le slate du jour tel quel.
    final List<EssentielArticle> passiveArticles;
    if (triageDone) {
      // `pool` (et non `articles`) : un article gardé injecté via « Voir
      // d'autres articles » doit apparaître dans la liste finale.
      final byId = {for (final a in pool) a.contentId: a};
      passiveArticles = [
        for (final id in triage.keptContentIds)
          if (byId[id] != null) byId[id]!,
      ];
    } else {
      passiveArticles = articles;
    }
    // B2 (passe PO 09/08) — **la liste des gardés est homogène** : tous les
    // articles y sont des tuiles sobres ([_MediumTile]), le premier compris. Un
    // gardé n'est pas plus important qu'un autre : c'est l'utilisateur qui les a
    // choisis un par un, hiérarchiser le premier était un reste du temps où la
    // carte affichait un classement éditorial.
    //
    // Une **lettre passée** (`isToday == false`), elle, garde son rendu
    // éditorial : lead teinté à filet + pastille « Actu du jour », puis mediums.
    // [_LeadTile], [_ActuBadge] et [_accentFor] restent donc vivants — ce n'est
    // pas du code mort, c'est l'autre moitié de cette bascule.
    // La limite éditoriale à 5 ne vaut que pour la liste passive historique.
    // Après le tri, chaque choix positif doit rester accessible, y compris le
    // 6e (l'objectif de gardés est réglable, et « Plus d'articles ? » peut le
    // pousser au-delà du plafond du stepper).
    final visible = (triageDone ? passiveArticles : passiveArticles.take(5))
        .toList(growable: false);
    final lead = triageDone || visible.isEmpty ? null : visible.first;
    final mediums = lead == null ? visible : visible.sublist(1);

    // Corps passif de la carte (hors pile de tri) : lead éventuel, mediums,
    // puis le pied de tri terminé. Rassemblé dans une fonction pour pouvoir
    // être rendu soit tel quel (lettre passée), soit enveloppé d'une seule
    // révélation de fin de tri ([_TriageDoneReveal]) — la bascule pile → liste
    // des gardés était sèche (un if/else de Column, aucune transition). Appelée
    // seulement dans les deux branches qui la rendent : pendant le tri et à
    // l'hydratation, ces tuiles seraient construites pour être jetées.
    List<Widget> buildPassiveChildren() => <Widget>[
          // Fin de tri : la liste des gardés s'ouvre sur un vrai sous-titre de
          // carte, sans quoi elle commençait par une tuile nue — rien ne marquait
          // que le tri était terminé ni ce qu'on regardait désormais.
          if (triageDone && visible.isNotEmpty) ...[
            const _KeptSectionTitle(),
            const SizedBox(height: 8),
          ],
          if (lead != null)
            widget._tracked(
              article: lead,
              position: 0,
              child: _LeadTile(
                article: lead,
                accent: accent,
                spec: spec,
                readState: readStateFor(lead),
                onTap: () => onTapArticle(lead),
              ),
            ),
          for (var i = 0; i < mediums.length; i++) ...[
            // Séparateur de tuiles medium 8→6 de part et d'autre du hairline
            // (poste le plus rentable : ×4, hairline 0.6px conserve le « moat »).
            // Pas de filet **avant la première** tuile quand il n'y a pas de
            // lead au-dessus (liste des gardés) : il pendrait sous l'en-tête.
            if (i > 0 || lead != null) ...[
              const SizedBox(height: 6),
              const _Hairline(),
            ],
            const SizedBox(height: 6),
            widget._tracked(
              article: mediums[i],
              // Décalé de 1 quand un lead occupe le rang 0.
              position: lead == null ? i : i + 1,
              child: _MediumTile(
                article: mediums[i],
                spec: spec,
                readState: readStateFor(mediums[i]),
                onTap: () => onTapArticle(mediums[i]),
              ),
            ),
          ],
          // Tri terminé : le pied de carte — « Plus d'articles ? » puis
          // « Refaire ? » (upsert backend idempotent sur
          // `(user, article, jour)`, donc re-trier écrase sans dupliquer).
          // L'objectif n'y est **plus affiché** (33.4) : un tri qui
          // s'arrête en deçà de la cible ne doit jamais se lire comme un
          // échec.
          if (triageDone) ...[
            if (visible.isEmpty) const _NothingKeptNotice(),
            _TriageDoneActions(poolIds: poolIds),
          ],
        ];
    final passiveChildren = buildPassiveChildren();

    return KeyedSubtree(
      // Ancre du tour guidé (étape 1 — hero « L'Essentiel du jour »).
      key: tourEssentielHeroKey,
      child: Container(
        // Marge/padding/chrome partagés avec `_HeroSkeleton` (theme.dart) : c'est
        // ce qui garantit qu'aucun pixel ne bouge à l'hydratation.
        margin: kEssentielCardMargin,
        decoration: facteurSurfaceCardDecoration(colors),
        child: Padding(
          padding: kEssentielCardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête « Ton Essentiel » (ou date sélectionnée) + pastille
              // date/météo + rewind.
              _Header(
                accent: accent,
                title: headerTitle,
                subtitle: headerSubtitle,
                rewind: EditionRewindTrigger(
                  onTap: () => EditionTimelineSheet.show(context),
                  // today à jour → icône seule ; lettre passée → « Revenir » fixe.
                  label: isToday ? null : 'Revenir',
                  // En retard → nudge éphémère « Rattraper ? » ; le point rouge
                  // persistant est dérivé de sa présence côté trigger.
                  ephemeralLabel: missedYesterday
                      ? EphemeralRattraperLabel(
                          dayKey: TourneeProgressService.dayKey(DateTime.now()),
                        )
                      : null,
                ),
              ),
              // Compaction « cartes ≤ écran » (passe 2, validée UX) : gap
              // header→lead 8→6 (le fond teinté du lead rétablit la séparation).
              const SizedBox(height: 6),
              if (showTriage)
                // Pas de compteur d'impression sur la pile de tri : une décision
                // de tri est déjà une impression, mesurée par sa propre jauge
                // (`essentiel_triage_decisions`). Les tuiles ne comptent que
                // lorsqu'elles sont réellement rendues, c'est-à-dire ici.
                EssentielTriageStack(
                  // Le pool (slate + articles injectables) permet à la pile de
                  // résoudre les ids réinjectés par « Voir d'autres articles ».
                  articles: pool,
                  triage: triage,
                  onTapArticle: onTapArticle,
                )
              else if (contentPending)
                const TriageStackSkeleton(standalone: true)
              else if (triageDone)
                // Fin de tri : la liste des gardés + le pied se révèlent d'un
                // seul mouvement (fade + léger scale-in), au lieu de claquer.
                _TriageDoneReveal(
                  animate: _sawTriageActive,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: passiveChildren,
                  ),
                )
              else
                ...passiveChildren,
            ],
          ),
        ),
      ),
    );
  }
}

/// Révélation **one-shot** de la fin de tri : fondu + remontée de 16px
/// (easeOutCubic, [FacteurDurations.slow], l'idiome de sobriété
/// d'`AnimatedFeedCard` — un événement, une transition lisible, ni confetti ni
/// haptique). Un fade + scale 0.98 (première itération) était invisible : la
/// bascule pile → liste réagence toute la carte au même moment, seul un
/// déplacement franc se lit.
///
/// [animate] est `false` quand le tri était déjà terminé au montage de la
/// carte (cold-boot) : l'état se rend alors d'emblée. Le reduce-motion
/// (`MediaQuery.maybeDisableAnimationsOf`) court-circuite de la même façon.
class _TriageDoneReveal extends StatelessWidget {
  final bool animate;
  final Widget child;

  const _TriageDoneReveal({required this.animate, required this.child});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!animate || reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: FacteurDurations.slow,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        // La liste remonte à sa place depuis 16px plus bas : elle « se pose »
        // là où vivait la pile.
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Pied de carte du tri terminé (design 2A) : « Plus d'articles ? » **toujours**,
/// et « Refaire ? » toujours.
///
/// - « Plus d'articles ? » est une **zone à bord pointillé** de 64px
///   ([DashedRRectPainter], le peintre existant du masthead/sceau — aucun
///   nouveau peintre) : icône `+` accent, titre, sous-titre « Deux de plus,
///   tirés du même Essentiel ».
/// - « Refaire ? » est une **ligne** de 28px centrée, icône + libellé discret —
///   une sortie de secours, pas un appel.
///
/// **La zone ne disparaît jamais** (reprise PO 10/08) et son action s'est
/// simplifiée en 33.4 : il n'y a plus de branche « réserve locale vs réseau » à
/// arbitrer, puisque le slate porte déjà tout le pool local. Un tap pousse
/// simplement l'objectif de gardés ([EssentielTriageNotifier.extendGoal]) :
///
/// 1. le slate a de quoi tenir la nouvelle cible → la pile rouvre dans la frame ;
/// 2. le slate est épuisé → on force un `fetchMore` (geste utilisateur : il
///    ignore le cooldown d'épuisement du prefetch automatique) ;
/// 3. rien d'inédit → la zone **reste** et son sous-titre le dit sobrement.
class _TriageDoneActions extends ConsumerStatefulWidget {
  /// Pool ordonné du jour (slate, carrousel, puis rapatriés) — base des
  /// exclusions envoyées au backend.
  final List<String> poolIds;

  const _TriageDoneActions({required this.poolIds});

  @override
  ConsumerState<_TriageDoneActions> createState() => _TriageDoneActionsState();
}

class _TriageDoneActionsState extends ConsumerState<_TriageDoneActions> {
  /// Un appel réseau en vol : bascule l'icône `+` en indicateur et **absorbe**
  /// les taps suivants. Le notifier porte la même garde (deux instances de la
  /// carte ne doivent pas non plus doubler l'appel) ; celle-ci ne sert qu'à
  /// rendre l'attente lisible.
  bool _loading = false;

  /// Le dernier appel n'a rien rapporté d'inédit. Effacé dès qu'on retente :
  /// un nouvel article a pu tomber entre-temps.
  bool _noneAvailable = false;

  Future<void> _onTap() async {
    if (_loading) return;

    // 1. Pousser la cible suffit : `extendGoal` est synchrone et lève l'arrêt
    //    volontaire. Si le slate porte encore des articles non triés, la pile
    //    rouvre dans la frame et ce pied de carte disparaît.
    ref
        .read(essentielTriageProvider.notifier)
        .extendGoal(kTriageGoalExtendStep);
    if (ref.read(essentielTriageProvider).isActive) return;

    // 2. Slate épuisé : il faut de la matière. Geste utilisateur ⇒ `force`,
    //    qui ignore le cooldown d'épuisement du prefetch automatique — il a le
    //    droit d'insister.
    setState(() {
      _loading = true;
      _noneAvailable = false;
    });
    try {
      final triage = ref.read(essentielTriageProvider);
      // Tout ce que le client porte déjà, **dans l'ordre** : le slate (affiché
      // ou à trier), les articles décidés (un rejeté ne doit jamais revenir),
      // puis le pool local. Le backend borne la liste ; ce qui saute à la
      // troncature doit être ce qui compte le moins.
      final seen = <String>{};
      final exclude = [
        for (final id in [
          ...triage.slate,
          ...triage.decisions.keys,
          ...widget.poolIds,
        ])
          if (seen.add(id)) id,
      ];
      final fresh =
          await ref.read(essentielExtraArticlesProvider.notifier).fetchMore(
                excludeIds: exclude,
                limit: kTriagePrefetchBatch,
                force: true,
              );
      if (!mounted) return;
      setState(() {
        _loading = false;
        // Rien d'inédit : la zone **reste** et le dit sobrement. L'objectif
        // relevé est conservé — si un article tombe plus tard, la pile rouvrira
        // d'elle-même au prochain `syncSlate`.
        _noneAvailable = fresh.isEmpty;
      });
    } catch (e) {
      debugPrint('EssentielHiFiCard: fetchMore failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _noneAvailable = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Padding(
      // La respiration au-dessus est le point : le pied ne doit plus toucher la
      // dernière ligne gardée.
      padding: const EdgeInsets.only(top: FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            enabled: !_loading,
            label: 'Plus d\'articles ?',
            child: InkWell(
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              onTap: _loading ? null : _onTap,
              child: CustomPaint(
                painter: DashedRRectPainter(
                  color: colors.border,
                  strokeWidth: 1.2,
                  radius: FacteurRadius.large,
                  dashLength: 5,
                  gapLength: 4,
                ),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // L'indicateur occupe **exactement** la place de l'icône :
                      // la zone ne change pas de taille pendant l'attente.
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: _loading
                            ? CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.sectionEssentiel,
                              )
                            : Icon(
                                PhosphorIcons.plus(),
                                size: 18,
                                color: colors.sectionEssentiel,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plus d\'articles ?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _loading
                                  ? 'Recherche en cours...'
                                  : _noneAvailable
                                      ? 'Pas de nouvel article pour l\'instant.'
                                      : 'Deux de plus, tirés du même Essentiel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: kTriageActionGap),
          Semantics(
            button: true,
            // « Refaire ? » seul est trop pauvre pour un lecteur d'écran : le
            // libellé visible est raccourci, pas la sémantique.
            label: 'Refaire le tri',
            child: InkWell(
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
              onTap: () => ref.read(essentielTriageProvider.notifier).restart(),
              child: SizedBox(
                height: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.arrowCounterClockwise(),
                      size: 12,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Refaire ?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tri terminé alors que rien n'a été gardé (tout passé). Message sobre à la
/// place d'une carte vide ; le pied [_TriageDoneActions] (rendu juste en
/// dessous) permet de revenir sur ses choix ou d'en voir d'autres.
class _NothingKeptNotice extends StatelessWidget {
  const _NothingKeptNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Rien gardé aujourd\'hui.',
        style: FacteurTypography.bodySmall(colors.textSecondary),
      ),
    );
  }
}

/// Sous-titre de la liste des gardés, rendu **une fois le tri terminé** :
/// « Tes articles » suivi d'un filet qui court jusqu'au bord de la carte. C'est
/// le repère de fin de tri — la pile a disparu, cette ligne dit ce qui la
/// remplace.
///
/// Volontairement distinct de l'en-tête inline affiché *pendant* le tri
/// ([_KeptListHeader] dans `essentiel_triage_stack.dart` : « TES ARTICLES » en
/// Courier capitales, un simple repère de progression sous la pile). Ici c'est
/// un titre de section de la carte, il porte donc la police de titre — le
/// Fraunces d'[_headerTitleStyle], d'un cran plus bas que l'en-tête « Ton
/// Essentiel » pour rester un **sous**-titre.
class _KeptSectionTitle extends StatelessWidget {
  const _KeptSectionTitle();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Row(
      children: [
        Text(
          'Tes articles',
          style: GoogleFonts.fraunces(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        // Le filet prolonge le titre au lieu de le souligner : le titre est
        // incrusté *dans* le séparateur, comme un cartouche de section.
        Expanded(
          child: Container(
            height: 1,
            color: colors.border.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// Titre Fraunces de l'en-tête standard ([_Header]).
TextStyle _headerTitleStyle(FacteurColors colors) => GoogleFonts.fraunces(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: colors.textPrimary,
    );

class _Header extends StatelessWidget {
  final Color accent;

  /// Titre de la section : « Ton Essentiel » en today, sinon le libellé de la
  /// lettre sélectionnée (« Hier », « Cette semaine », « mar. 24 »).
  final String title;

  /// Ligne sous le titre, accordée à la sélection (cf. `editionSubtitleLabel`).
  final String subtitle;

  /// Déclencheur « rewind » (timeline overlay), posé à droite du titre. Toujours
  /// fourni par la carte (today ET lettre passée).
  final Widget? rewind;

  const _Header({
    required this.accent,
    required this.title,
    required this.subtitle,
    this.rewind,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeaderBadge(accent: accent),
        const SizedBox(width: FacteurSpacing.space2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderAccentDash(accent: accent),
              const SizedBox(height: 5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: _headerTitleStyle(colors),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Ordre : titre … rewind. Le bouton « personnaliser » a été
                  // retiré (décision PO) : point d'entrée unique des préférences
                  // = l'inline « GÉRER » de MyInterestsIntro.
                  if (rewind != null) ...[
                    const SizedBox(width: FacteurSpacing.space2),
                    rewind!,
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // Décrit la carte **telle qu'elle est** (passe PO 09/08) : une
              // pile à trier, dont on choisit ce qu'on lira. L'ancien « 5
              // articles du jour, basé sur tes intérêts » devenait faux dès
              // qu'on touchait « Plus d'articles », et annonçait un sommaire
              // là où il y a un geste. « Ton Essentiel » n'est pas répété : le
              // titre juste au-dessus le porte déjà. Sur une lettre passée, le
              // geste n'existe plus : le texte suit la sélection.
              Text(
                subtitle,
                style: FacteurTypography.bodySmall(
                  colors.textSecondary,
                ).copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderAccentDash extends StatelessWidget {
  final Color accent;

  const _HeaderAccentDash({required this.accent});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 24,
        height: 2,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

String _monthAbbrev(int m) {
  const months = [
    'JAN',
    'FÉV',
    'MAR',
    'AVR',
    'MAI',
    'JUIN',
    'JUIL',
    'AOÛT',
    'SEPT',
    'OCT',
    'NOV',
    'DÉC',
  ];
  return months[m - 1];
}

class _HeaderBadge extends ConsumerStatefulWidget {
  final Color accent;

  const _HeaderBadge({required this.accent});

  @override
  ConsumerState<_HeaderBadge> createState() => _HeaderBadgeState();
}

class _HeaderBadgeState extends ConsumerState<_HeaderBadge> {
  bool _showWeather = false;
  Timer? _flipTimer;

  @override
  void initState() {
    super.initState();
    _flipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showWeather = true);
    });
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Always watch so the fetch starts on mount and any update triggers a rebuild.
    final forecast = ref.watch(weatherProvider).valueOrNull;

    final Widget child;
    if (_showWeather && forecast != null) {
      child = GestureDetector(
        key: const ValueKey('weather'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showWeatherDetailSheet(context),
        child: _WeatherBadge(forecast: forecast, accent: widget.accent),
      );
    } else {
      child = GestureDetector(
        key: const ValueKey('date'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showWeather = true),
        child: _DateStamp(
          day: now.day,
          month: _monthAbbrev(now.month),
          accent: widget.accent,
        ),
      );
    }

    // Fixed slot: the header never reflows when flipping between date/weather.
    // Slot resserré (110 → 96) : l'icône météo (88) et la pastille date (cercle
    // 68) restent centrées, mais sans le vide latéral d'avant (décision PO).
    return SizedBox(
      width: 96,
      height: 140,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (Widget child, Animation<double> animation) {
          final rotate = Tween<double>(
            begin: math.pi,
            end: 0.0,
          ).animate(animation);
          return AnimatedBuilder(
            animation: rotate,
            builder: (context, c) {
              final isFront = animation.value > 0.5;
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(rotate.value),
                alignment: Alignment.center,
                child: Opacity(opacity: isFront ? 1 : 0, child: c),
              );
            },
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}

/// Bloc météo compact du header : icône condition, min/max, et un indice
/// discret signalant qu'un tap ouvre la modal détaillée 5 jours.
class _WeatherBadge extends StatefulWidget {
  final WeatherForecast forecast;
  final Color accent;

  const _WeatherBadge({required this.forecast, required this.accent});

  @override
  State<_WeatherBadge> createState() => _WeatherBadgeState();
}

class _WeatherBadgeState extends State<_WeatherBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _temperatureController;
  late final Animation<double> _temperatureScale;

  @override
  void initState() {
    super.initState();
    _temperatureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _temperatureScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.94,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
    ]).animate(_temperatureController);
    _temperatureController.forward();
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Halo doux teinté accent derrière l'illustration météo : au repos, il
        // fait « léviter » l'icône et signale que le badge est tappable (ouvre
        // la modal 5 jours). Le BoxShadow se dessine à partir de la forme du
        // conteneur même avec un remplissage transparent → glow diffus, sans
        // contour dur.
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.accent.withValues(alpha: 0.14),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: WeatherConditionIcon(
            condition: widget.forecast.condition,
            size: 88,
            badgeSize: 30,
            emojiSize: 18,
            badgeInset: 4,
          ),
        ),
        const SizedBox(height: 2),
        ScaleTransition(
          key: const ValueKey('weather_temperatures'),
          scale: _temperatureScale,
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.courierPrime(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
              children: [
                TextSpan(
                  text: '${widget.forecast.minC}°',
                  style: TextStyle(color: colors.info),
                ),
                TextSpan(
                  text: '/',
                  style: TextStyle(color: colors.textSecondary),
                ),
                TextSpan(
                  text: '${widget.forecast.maxC}°',
                  style: TextStyle(color: colors.error),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        // Libellé discret souligné « Météo » (remplace l'ancien chevron) :
        // signale qu'un tap ouvre la modal détaillée 5 jours.
        Text(
          'Météo',
          style: GoogleFonts.courierPrime(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: 0.6,
            color: colors.textTertiary,
            decoration: TextDecoration.underline,
            decorationColor: colors.textTertiary.withValues(alpha: 0.6),
          ),
          semanticsLabel: 'Voir la météo détaillée',
        ),
      ],
    );
  }
}

class _DateStamp extends StatelessWidget {
  final int day;
  final String month;
  final Color accent;

  const _DateStamp({
    required this.day,
    required this.month,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 0.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.toString().padLeft(2, '0'),
                style: GoogleFonts.courierPrime(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: accent,
                ),
              ),
              Text(
                month,
                style: GoogleFonts.courierPrime(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  letterSpacing: 0.8,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Météo',
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: 0.8,
                color: colors.textTertiary.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_return_rounded,
              size: 11,
              color: colors.textTertiary.withValues(alpha: 0.72),
              semanticLabel: 'Retourner vers la météo',
            ),
          ],
        ),
      ],
    );
  }
}

class _LeadTile extends StatelessWidget {
  final EssentielArticle article;
  final Color accent;
  final DisplayModeSpec spec;

  /// État de lecture effectif (fusion session incluse). Descendu par la carte
  /// plutôt que relu ici — un seul point de lecture des providers.
  final ReadState readState;

  final VoidCallback onTap;

  const _LeadTile({
    required this.article,
    required this.accent,
    required this.spec,
    required this.onTap,
    required this.readState,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final chipAccent = _accentFor(article, accent);
    return Material(
      color: Colors.transparent,
      child: AutoGrowCandidate(
        contentId: article.contentId,
        isRead: article.isRead,
        keyPrefix: 'ess',
        child: ArticlePreviewGesture(
          contentBuilder: () => article.toPreviewContent(),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            // Lu : grise la tuile (0.8 « Ouvert » / 0.6 lu, cf. opacityForReadState)
            // + coche verte, comme les autres sections
            // (cf. flux_continu_article_card.dart). Le badge est inclus dans
            // l'Opacity pour s'estomper de concert avec le contenu.
            child: Opacity(
              opacity: opacityForReadState(readState),
              child: AnimatedFeedCard(
                isCompleted: readState == ReadState.completed,
                animate: false,
                child: Stack(
                  children: [
                    Container(
                      // Compaction passe 2 (validée UX) : padding héro 12→10. Plancher
                      // dur à 10 — sous ce seuil le texte « fuit » du fond teinté.
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                        border:
                            Border(left: BorderSide(color: accent, width: 3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bonus 10.1 — plus de chip section (allège la tuile) ;
                          // seul le badge « Actu du jour » reste, quand pertinent.
                          if (article.isActuDuJour) ...[
                            _ActuBadge(
                              accent: chipAccent,
                              overrideBackground: colors.sectionEssentiel,
                            ),
                            const SizedBox(height: FacteurSpacing.space2),
                          ],
                          Text(
                            article.title,
                            // Compaction « cartes ≤ écran » : plafond 5→4 lignes pour
                            // borner la hauteur du lead (cohérent avec section_fit).
                            maxLines: 4 + spec.titleMaxLinesDelta,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 16 * spec.fontScale,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                              color: colors.textPrimary,
                            ),
                          ),
                          // Titre→source 8→6 (le badge actu→titre reste à 8, délibéré).
                          const SizedBox(height: 6),
                          _SourceRow(article: article, accent: chipAccent),
                        ],
                      ),
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
          ),
        ),
      ),
    );
  }
}

class _MediumTile extends StatelessWidget {
  final EssentielArticle article;
  final DisplayModeSpec spec;
  final ReadState readState;
  final VoidCallback onTap;

  const _MediumTile({
    required this.article,
    required this.spec,
    required this.onTap,
    required this.readState,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Material(
      color: Colors.transparent,
      child: AutoGrowCandidate(
        contentId: article.contentId,
        isRead: article.isRead,
        keyPrefix: 'ess',
        child: ArticlePreviewGesture(
          contentBuilder: () => article.toPreviewContent(),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(FacteurRadius.small),
            // Lu : grise la tuile (0.8/0.6) + petite coche verte (cf. _LeadTile).
            child: Opacity(
              opacity: opacityForReadState(readState),
              child: AnimatedFeedCard(
                isCompleted: readState == ReadState.completed,
                animate: false,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  article.sourceName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FacteurTypography.labelSmall(
                                    colors.textTertiary,
                                  ),
                                ),
                              ),
                              if (article.coverageCount >=
                                  kCoverageChipMinSources) ...[
                                const SizedBox(width: 8),
                                CoverageChip(
                                  sourceCount: article.coverageCount,
                                  sources: article.perspectiveSources,
                                  colors: colors,
                                ),
                              ],
                              // Réserve l'espace de la coche pour qu'elle ne
                              // chevauche pas la source ellipsée.
                              if (readState != ReadState.unread)
                                const SizedBox(width: 22),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            article.title,
                            // Compaction « cartes ≤ écran » : plafond 4→3 lignes.
                            maxLines: 3 + spec.titleMaxLinesDelta,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 15 * spec.fontScale,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (readState != ReadState.unread)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: ReadStateMark(
                          color: colors.success,
                          state: readState,
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille "Actu du jour" affichée en tête du lead.
/// [overrideBackground] permet de forcer la couleur orange Essentiel quel
/// que soit le thème de l'article (sinon `accent` est utilisé).
class _ActuBadge extends StatelessWidget {
  final Color accent;
  final Color? overrideBackground;

  const _ActuBadge({required this.accent, this.overrideBackground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overrideBackground ?? accent,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Actu du jour',
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final EssentielArticle article;
  final Color accent;

  const _SourceRow({required this.article, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final isFollowed = article.isFollowedSource;
    final avatarBg = isFollowed
        ? accent.withValues(alpha: 0.18)
        : colors.backgroundSecondary;
    final avatarBorder = isFollowed ? accent : colors.border;
    final avatarTextColor = isFollowed ? accent : colors.textSecondary;
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatarBg,
            shape: BoxShape.circle,
            border: Border.all(color: avatarBorder, width: 0.8),
          ),
          child: Text(
            article.sourceLetter,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: avatarTextColor,
            ),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space2),
        Flexible(
          child: Text(
            article.sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FacteurTypography.labelSmall(colors.textTertiary),
          ),
        ),
        if (article.coverageCount >= kCoverageChipMinSources) ...[
          const Spacer(),
          CoverageChip(
            key: const Key('essentiel-coverage-chip'),
            sourceCount: article.coverageCount,
            sources: article.perspectiveSources,
            colors: colors,
          ),
        ],
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Container(height: 0.6, color: colors.border.withValues(alpha: 0.20));
  }
}

/// Looks up an entry in [themeMap] by article theme slug and extracts [selector].
/// Returns null when the slug is absent or not in the map.
T? _themeMapLookup<T>(String? slug, T Function(ThemeVisual) selector) {
  if (slug != null && themeMap.containsKey(slug)) {
    return selector(themeMap[slug]!);
  }
  return null;
}

/// Picks an accent color: theme slug first, then card-level kind fallback.
Color _accentFor(EssentielArticle article, Color fallback) =>
    _themeMapLookup(article.theme, (e) => e.accent) ?? fallback;
