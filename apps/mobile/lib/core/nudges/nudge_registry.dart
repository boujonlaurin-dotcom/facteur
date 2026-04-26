import 'nudge.dart';
import 'nudge_ids.dart';

/// Static declarations of every nudge in the app.
///
/// Lookup by id via [NudgeRegistry.get]. New nudges are added here and
/// reference their id via [NudgeIds].
class NudgeRegistry {
  NudgeRegistry._();

  static final Map<String, Nudge> _byId = {
    for (final n in _all) n.id: n,
  };

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
      id: NudgeIds.digestWelcome,
      surface: NudgeSurface.digest,
      placement: NudgePlacement.modal,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.once,
      legacySeenKey: 'has_seen_digest_welcome',
    ),
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

    // --- Reserved for PR2/PR3 (declared now to lock ids + priorities). ---
    const Nudge(
      id: NudgeIds.welcomeTour,
      surface: NudgeSurface.global,
      placement: NudgePlacement.overlay,
      priority: NudgePriority.critical,
      frequency: NudgeFrequency.once,
    ),
    const Nudge(
      id: NudgeIds.feedSwipeHint,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.once,
      legacySeenKey: 'feed_swipe_hint_seen',
    ),
    const Nudge(
      id: NudgeIds.feedBadgeLongpress,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.high,
      frequency: NudgeFrequency.once,
      prerequisites: [NudgeIds.welcomeTour],
    ),
    const Nudge(
      id: NudgeIds.feedPreviewLongpress,
      surface: NudgeSurface.feed,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
      prerequisites: [NudgeIds.feedBadgeLongpress],
    ),
    const Nudge(
      id: NudgeIds.prioritySliderExplainer,
      surface: NudgeSurface.settings,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
      prerequisites: [NudgeIds.welcomeTour],
    ),
    const Nudge(
      id: NudgeIds.articleSaveNotes,
      surface: NudgeSurface.article,
      placement: NudgePlacement.tooltip,
      priority: NudgePriority.normal,
      frequency: NudgeFrequency.once,
      legacySeenKey: 'has_seen_note_welcome',
      prerequisites: [NudgeIds.welcomeTour],
    ),
    const Nudge(
      id: NudgeIds.perspectivesCta,
      surface: NudgeSurface.article,
      placement: NudgePlacement.hintAnimation,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.once,
      prerequisites: [NudgeIds.welcomeTour],
    ),
    const Nudge(
      id: NudgeIds.articleReadOnSite,
      surface: NudgeSurface.article,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.once,
      prerequisites: [NudgeIds.welcomeTour],
    ),

    // Story 14.3 — well-informed NPS. Cooldown porté à 5j (skip) ; le
    // provider impose en plus un cooldown 14j après une vraie soumission.
    const Nudge(
      id: NudgeIds.wellInformedPoll,
      surface: NudgeSurface.digest,
      placement: NudgePlacement.inlineBanner,
      priority: NudgePriority.low,
      frequency: NudgeFrequency.cooldown,
      cooldown: Duration(days: 5),
    ),
  ];
}
