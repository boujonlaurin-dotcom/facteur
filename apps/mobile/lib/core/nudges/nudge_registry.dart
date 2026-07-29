import 'nudge.dart';
import 'nudge_ids.dart';

/// Static declarations of every nudge in the app.
///
/// Lookup by id via [NudgeRegistry.get]. New nudges are added here and
/// reference their id via [NudgeIds].
class NudgeRegistry {
  NudgeRegistry._();

  static final Map<String, Nudge> _byId = {for (final n in _all) n.id: n};

  static Nudge get(String id) {
    final nudge = _byId[id];
    if (nudge == null) {
      throw ArgumentError('Unknown nudge id: $id');
    }
    return nudge;
  }

  static bool has(String id) => _byId.containsKey(id);

  static List<Nudge> get all => List.unmodifiable(_all);

  static final List<Nudge> _all = [
    // --- Existing nudges, migrated with legacy keys for backward compat. ---
    const Nudge(
      id: NudgeIds.widgetPinAndroid,
      surface: NudgeSurface.digest,
      placement: NudgePlacement.bottomSheet,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.once,
      legacySeenKey: 'has_seen_widget_pin_nudge',
    ),
    const Nudge(
      id: NudgeIds.sunflowerRecommend,
      surface: NudgeSurface.article,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 3),
      legacyLastShownKey: 'sunflower_last_nudge_date',
    ),
    const Nudge(
      id: NudgeIds.savedUnread,
      surface: NudgeSurface.saved,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(hours: 24),
      legacyLastShownKey: 'saved_nudge_dismissed_at',
    ),

    // --- Feed/article nudges.
    const Nudge(
      id: NudgeIds.feedSwipeHint,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 14),
      legacySeenKey: 'feed_swipe_hint_seen',
    ),
    const Nudge(
      id: NudgeIds.feedBadgeLongpress,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.once,
    ),
    const Nudge(
      id: NudgeIds.feedPreviewLongpress,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 14),
    ),
    const Nudge(
      id: NudgeIds.personalisationCta,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 30),
    ),
    // Bandeau « Ajoute le widget » de Flâner. Cooldown 7 j, aligné sur le
    // bandeau Lettres : on repropose, sans être insistant.
    const Nudge(
      id: NudgeIds.widgetCtaFeedBanner,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 7),
    ),
    const Nudge(
      id: NudgeIds.prioritySliderExplainer,
      surface: NudgeSurface.settings,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
    ),
    const Nudge(
      id: NudgeIds.articleSaveNotes,
      surface: NudgeSurface.article,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
      legacySeenKey: 'has_seen_note_welcome',
    ),
    const Nudge(
      id: NudgeIds.perspectivesCta,
      surface: NudgeSurface.article,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.once,
    ),
    const Nudge(
      id: NudgeIds.articleReadOnSite,
      surface: NudgeSurface.article,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.once,
    ),

    // Nudges de scroll flottants dans le reader (cf. content_detail_screen).
    // Pilotés directement via [NudgeService] (pas le coordinator) : seul le
    // cooldown par-nudge s'applique → « 1×/24 h par cible ». La priorité n'est
    // pas consultée sur ce chemin ; l'entrée sert au lookup canShow/cooldown.
    const Nudge(
      id: NudgeIds.scrollToDeepReco,
      surface: NudgeSurface.article,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 1),
    ),
    const Nudge(
      id: NudgeIds.scrollToPerspectives,
      surface: NudgeSurface.article,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 1),
    ),

    // Story 14.3 — well-informed NPS. Cooldown porté à 21j (skip) ; le
    // provider impose en plus un cooldown 60j après une vraie soumission, et un
    // tirage aléatoire quotidien (~1 jour sur 7) pour rarefier sans biais.
    const Nudge(
      id: NudgeIds.wellInformedPoll,
      surface: NudgeSurface.digest,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 21),
    ),

    // Story web.1 — iOS Safari "Ajouter à l'écran d'accueil". Cooldown 7j
    // pour les utilisateurs qui ferment via "Plus tard" ; `markSeen`
    // permanent quand l'utilisateur confirme "C'est fait".
    const Nudge(
      id: NudgeIds.iosAddToHome,
      surface: NudgeSurface.global,
      placement: NudgePlacement.modal,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 7),
    ),

    // Story 13.3 — la modale « un café en visio » se déploie seule une fois,
    // à la première exposition éligible. Le re-ciblage (snooze / cap
    // d'affichages) reste piloté par le backend, pas par ce nudge.
    const Nudge(
      id: NudgeIds.feedbackCallAutoModal,
      surface: NudgeSurface.digest,
      placement: NudgePlacement.bottomSheet,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
    ),
  ];
}
