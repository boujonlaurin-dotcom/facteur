/// Central registry of every nudge identifier used in the app.
///
/// Adding a new nudge:
/// 1. Declare its id here.
/// 2. Add its [Nudge] definition in [nudge_registry.dart].
/// 3. Use [NudgeService] / [NudgeCoordinator] from the trigger site.
class NudgeIds {
  NudgeIds._();

  // Existing (migrated from scattered SharedPreferences keys).
  static const digestWelcome = 'digest_welcome';
  static const widgetPinAndroid = 'widget_pin_android';
  static const sunflowerRecommend = 'sunflower_recommend';
  static const savedUnread = 'saved_unread';

  // New (planned for PR2/PR3).
  static const welcomeTour = 'welcome_tour';
  static const feedSwipeHint = 'feed_swipe_hint';
  static const feedBadgeLongpress = 'feed_badge_longpress';
  static const feedPreviewLongpress = 'feed_preview_longpress';
  static const prioritySliderExplainer = 'priority_slider_explainer';
  static const articleSaveNotes = 'article_save_notes';
  static const perspectivesCta = 'perspectives_cta';
  static const articleReadOnSite = 'article_read_on_site';

  // Story 14.3 — self-reported "well-informed" score (NPS-style).
  static const wellInformedPoll = 'well_informed_poll';
}
