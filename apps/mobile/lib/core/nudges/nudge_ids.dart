/// Central registry of every nudge identifier used in the app.
///
/// Adding a new nudge:
/// 1. Declare its id here.
/// 2. Add its [Nudge] definition in [nudge_registry.dart].
/// 3. Use [NudgeService] / [NudgeCoordinator] from the trigger site.
class NudgeIds {
  NudgeIds._();

  // Existing (migrated from scattered SharedPreferences keys).
  static const widgetPinAndroid = 'widget_pin_android';
  static const sunflowerRecommend = 'sunflower_recommend';
  static const savedUnread = 'saved_unread';

  // Feed and article nudges.
  static const feedSwipeHint = 'feed_swipe_hint';
  static const feedBadgeLongpress = 'feed_badge_longpress';
  static const feedPreviewLongpress = 'feed_preview_longpress';
  static const personalisationCta = 'personalisation_cta';
  // Bandeau « Ajoute le widget » en tête de Flâner. Distinct de
  // [widgetPinAndroid], qui décrit la feuille du bas côté Essentiel : surface,
  // placement et fréquence diffèrent, seule l'intention est voisine.
  static const widgetCtaFeedBanner = 'widget_cta_feed_banner';
  // ID kept after the slider→picker migration so users who already dismissed
  // the explainer don't see it pop again.
  static const prioritySliderExplainer = 'priority_slider_explainer';
  static const articleSaveNotes = 'article_save_notes';
  static const perspectivesCta = 'perspectives_cta';
  static const articleReadOnSite = 'article_read_on_site';
  // Nudge de scroll flottant dans le reader : invite vers le pas de recul
  // (prioritaire) ou vers la couverture médiatique. Deux ids indépendants →
  // cooldown 24 h par cible.
  static const scrollToDeepReco = 'scroll_to_deep_reco';
  static const scrollToPerspectives = 'scroll_to_perspectives';

  // Story 14.3 — self-reported "well-informed" score (NPS-style).
  static const wellInformedPoll = 'well_informed_poll';

  // Story web.1 — Modal "Ajouter à l'écran d'accueil" sur iOS Safari.
  static const iosAddToHome = 'ios_add_to_home';
}
