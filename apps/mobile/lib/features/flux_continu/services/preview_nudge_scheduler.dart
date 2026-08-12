import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tournee_progress_service.dart';

/// Préfixe de la clé « compteur du jour » (`..._<jour>`) du pulse auto-grow :
/// borne le nombre de pulses par jour calendaire. Le suffixe daté rend le reset
/// gratuit (une nouvelle clé = 0 le lendemain).
const String kAutoGrowCountPrefixPrefsKey = 'auto_grow_nudge_count_';

/// Timestamp (ms epoch) du dernier pulse auto-grow — impose l'espacement.
const String kAutoGrowLastTriggerPrefsKey = 'auto_grow_nudge_last_trigger_ms';

/// Flag « l'utilisateur a découvert l'aperçu » (vrai long-press) — arrête
/// définitivement le pulse auto-grow.
const String kAutoGrowDiscoveredPrefsKey = 'auto_grow_nudge_discovered';

/// Budget quotidien de pulses auto-grow.
const int kAutoGrowDailyBudget = 3;

/// Espacement minimum entre deux pulses auto-grow (répartit les ~3/jour sur la
/// journée plutôt que de les enchaîner dans la même session).
const Duration kAutoGrowMinSpacing = Duration(minutes: 90);

/// Clés du nudge « aperçu au long-press » de la pile de tri (Story 33.1).
const String kTriagePreviewCountPrefixPrefsKey = 'triage_preview_nudge_shown_';
const String kTriagePreviewLastTriggerPrefsKey =
    'triage_preview_nudge_last_trigger_ms';
const String kTriagePreviewDiscoveredPrefsKey =
    'triage_preview_nudge_discovered';

/// Index (0-based) de la carte de tri sur laquelle le nudge se déclenche : la
/// **deuxième**. À la première, l'utilisateur découvre le geste de swipe ; lui
/// annoncer un second geste dans la foulée noierait les deux.
const int kTriagePreviewNudgeCardIndex = 1;

/// Durée d'affichage du mini libellé du nudge de tri avant auto-masquage —
/// alignée sur le hint de réorganisation des onglets (`flux_continu_screen`).
const Duration kTriagePreviewHintDuration = Duration(milliseconds: 2400);

/// Clés du rappel « glisse pour l'article suivant » du deck (Story 34.2).
const String kArticleSwipeCountPrefixPrefsKey = 'article_swipe_nudge_shown_';
const String kArticleSwipeLastTriggerPrefsKey =
    'article_swipe_nudge_last_trigger_ms';
const String kArticleSwipeDiscoveredPrefsKey = 'article_swipe_nudge_discovered';

/// Espacement des rappels **après** que l'utilisateur a swipé au moins une fois.
const Duration kArticleSwipePostDiscoverySpacing = Duration(days: 7);

/// Nombre total de rappels joués après la découverte — « une fois par semaine
/// en début d'expérience », puis plus rien.
const int kArticleSwipePostDiscoveryBudget = 4;

/// Coordinateur des nudges d'apprentissage d'un **geste** (aperçu au
/// long-press, swipe d'article).
///
/// Volontairement **hors** de `NudgeRegistry`/`NudgeCoordinator` : aucune
/// fréquence existante ne correspond à « plusieurs fois par jour, espacées », et
/// ces nudges doivent échapper au cooldown global ~24 h du coordinator, calibré
/// pour des sollicitations d'écran et non pour un indice joué pendant un geste.
///
/// Une seule mécanique, trois réglages (cf. les providers plus bas) :
/// - **auto-grow** dans le flux : 3 pulses/jour calendaire, espacés de 90 min ;
/// - **pile de tri** : 1 fois par jour de Tournée (bascule 07h30 Paris, pour
///   suivre la même journée que le tri qu'il commente), sans espacement ;
/// - **swipe d'article** : 2 rappels/jour espacés de 2 h **puis**, une fois le
///   geste fait, un rappel hebdomadaire borné (étage post-découverte).
///
/// Persistance `SharedPreferences`, `clock`/`prefs` injectables pour les tests
/// (même pattern que `WellInformedPromptController`).
class PreviewNudgeScheduler {
  PreviewNudgeScheduler({
    required String countKeyPrefix,
    required String lastTriggerKey,
    required String discoveredKey,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
    String Function(DateTime)? dayKey,
    int dailyBudget = kAutoGrowDailyBudget,
    Duration minSpacing = kAutoGrowMinSpacing,
    Duration? postDiscoverySpacing,
    int postDiscoveryBudget = 0,
  })  : _countKeyPrefix = countKeyPrefix,
        _lastTriggerKey = lastTriggerKey,
        _discoveredKey = discoveredKey,
        _clock = clock ?? DateTime.now,
        _prefsFactory = prefs ?? SharedPreferences.getInstance,
        _dayKey = dayKey ?? _calendarDayKey,
        _dailyBudget = dailyBudget,
        _minSpacing = minSpacing,
        _postDiscoverySpacing = postDiscoverySpacing,
        _postDiscoveryBudget = postDiscoveryBudget;

  final String _countKeyPrefix;
  final String _lastTriggerKey;
  final String _discoveredKey;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;
  final String Function(DateTime) _dayKey;
  final int _dailyBudget;
  final Duration _minSpacing;

  /// Espacement des rappels joués **après** la découverte du geste. `null` (par
  /// défaut) = la découverte éteint le nudge définitivement.
  final Duration? _postDiscoverySpacing;

  /// Nombre total de rappels autorisés après la découverte.
  final int _postDiscoveryBudget;

  /// Latch mémoire de [markDiscovered] : le flag ne peut aller que de `false` à
  /// `true` une seule fois, mais le long-press qui le pose est câblé sur chaque
  /// carte. Sans ce verrou, chaque appui maintenu rejouerait un aller-retour de
  /// canal de plateforme + un commit disque, sur la frame même où l'aperçu
  /// s'ouvre et s'anime.
  bool _discovered = false;

  /// Vrai si un pulse peut être déclenché maintenant :
  ///   - l'utilisateur n'a PAS déjà découvert le geste, ET
  ///   - le budget du jour n'est pas épuisé, ET
  ///   - l'espacement minimum depuis le dernier pulse est écoulé.
  ///
  /// Une fois le geste découvert, le nudge s'éteint — sauf si un étage
  /// post-découverte est configuré ([_postDiscoverySpacing]), auquel cas les
  /// rappels continuent, espacés et en nombre borné.
  Future<bool> canTriggerNow() async {
    final prefs = await _prefsFactory();
    if (_discovered || (prefs.getBool(_discoveredKey) ?? false)) {
      return _canTriggerAfterDiscovery(prefs);
    }

    final now = _clock();
    if ((prefs.getInt(_countKey(now)) ?? 0) >= _dailyBudget) return false;

    if (_minSpacing > Duration.zero) {
      final lastMs = prefs.getInt(_lastTriggerKey);
      if (lastMs != null) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (now.difference(last) < _minSpacing) return false;
      }
    }
    return true;
  }

  /// Rappels d'après-découverte : espacés de [_postDiscoverySpacing] et bornés
  /// à [_postDiscoveryBudget] au total. Sans étage configuré, la découverte
  /// éteint le nudge pour de bon (comportement des nudges d'aperçu).
  Future<bool> _canTriggerAfterDiscovery(SharedPreferences prefs) async {
    final spacing = _postDiscoverySpacing;
    if (spacing == null) return false;
    if ((prefs.getInt(_postDiscoveryCountKey) ?? 0) >= _postDiscoveryBudget) {
      return false;
    }
    final lastMs = prefs.getInt(_lastTriggerKey);
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (_clock().difference(last) < spacing) return false;
    }
    return true;
  }

  /// Enregistre un pulse déclenché : incrémente le compteur du jour, pose le
  /// timestamp du dernier trigger, et jette les compteurs des jours précédents
  /// — sans quoi ils s'accumuleraient indéfiniment (même motif que
  /// `TourneeProgressService.purgeOldPrefsKeys`).
  ///
  /// Après découverte, c'est le compteur **total** de rappels qui avance : le
  /// budget d'après-découverte se compte sur toute la vie de l'utilisateur, pas
  /// par jour.
  Future<void> recordTriggered() async {
    final prefs = await _prefsFactory();
    final now = _clock();
    final key = _countKey(now);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
    await prefs.setInt(_lastTriggerKey, now.millisecondsSinceEpoch);
    if (_discovered || (prefs.getBool(_discoveredKey) ?? false)) {
      final count = prefs.getInt(_postDiscoveryCountKey) ?? 0;
      await prefs.setInt(_postDiscoveryCountKey, count + 1);
    }
    await TourneeProgressService.purgeDatedPrefsKeys(
      prefs,
      prefix: _countKeyPrefix,
      keep: key,
    );
  }

  /// Marque le geste comme découvert (vrai long-press, vrai swipe d'article) →
  /// arrête le nudge, définitivement ou jusqu'au prochain rappel espacé selon
  /// l'étage post-découverte.
  Future<void> markDiscovered() async {
    if (_discovered) return;
    _discovered = true;
    final prefs = await _prefsFactory();
    await prefs.setBool(_discoveredKey, true);
    // La découverte compte comme le dernier « signal reçu » : le premier rappel
    // d'après-découverte se compte à partir d'elle, pas du dernier rebond joué
    // (qui peut n'avoir jamais eu lieu si le geste a été trouvé tout seul).
    if (_postDiscoverySpacing != null) {
      await prefs.setInt(_lastTriggerKey, _clock().millisecondsSinceEpoch);
    }
  }

  String _countKey(DateTime now) => '$_countKeyPrefix${_dayKey(now)}';

  /// Dérivée du flag de découverte, **pas** du préfixe daté : les clés qui
  /// commencent par `_countKeyPrefix` sont purgées à chaque nouveau jour
  /// (cf. [recordTriggered]), ce qui remettrait le budget total à zéro.
  String get _postDiscoveryCountKey => '${_discoveredKey}_reminders';

  static String _calendarDayKey(DateTime now) {
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}

/// Pulse auto-grow du flux : 3 fois par jour calendaire, espacés de 90 min.
final autoGrowNudgeSchedulerProvider = Provider<PreviewNudgeScheduler>(
  (ref) => PreviewNudgeScheduler(
    countKeyPrefix: kAutoGrowCountPrefixPrefsKey,
    lastTriggerKey: kAutoGrowLastTriggerPrefsKey,
    discoveredKey: kAutoGrowDiscoveredPrefsKey,
  ),
);

/// Rappel « glisse pour l'article suivant » du deck (Story 34.2).
///
/// Tant que l'utilisateur n'a jamais swipé : 2 rebonds par jour calendaire,
/// espacés de 2 h — le tout premier article ouvert rebondit donc. Une fois le
/// geste fait : un rappel hebdomadaire, 4 fois en tout, puis plus jamais.
final articleSwipeNudgeSchedulerProvider = Provider<PreviewNudgeScheduler>(
  (ref) => PreviewNudgeScheduler(
    countKeyPrefix: kArticleSwipeCountPrefixPrefsKey,
    lastTriggerKey: kArticleSwipeLastTriggerPrefsKey,
    discoveredKey: kArticleSwipeDiscoveredPrefsKey,
    dailyBudget: 2,
    minSpacing: const Duration(hours: 2),
    postDiscoverySpacing: kArticleSwipePostDiscoverySpacing,
    postDiscoveryBudget: kArticleSwipePostDiscoveryBudget,
  ),
);

/// Nudge de la pile de tri : 1 fois par jour de Tournée, sans espacement.
final triagePreviewNudgeSchedulerProvider = Provider<PreviewNudgeScheduler>(
  (ref) => PreviewNudgeScheduler(
    countKeyPrefix: kTriagePreviewCountPrefixPrefsKey,
    lastTriggerKey: kTriagePreviewLastTriggerPrefsKey,
    discoveredKey: kTriagePreviewDiscoveredPrefsKey,
    dayKey: TourneeProgressService.dayKey,
    dailyBudget: 1,
    minSpacing: Duration.zero,
  ),
);
