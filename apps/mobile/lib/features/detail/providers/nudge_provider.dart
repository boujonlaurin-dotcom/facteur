import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';

/// Manages the 🌻 "Recommander ?" nudge display logic.
///
/// Persistence (cooldown date) is delegated to the unified [NudgeService];
/// the in-session "article-count" gate stays here because it's runtime state
/// that shouldn't survive app restarts.
///
/// Rules:
/// - Show after >30s of reading an article
/// - Skip the first 2 articles read in the session
/// - Max 1 nudge per session
/// - Max 1 nudge every 3 days (cooldown enforced by NudgeRegistry)
/// - Don't show if article is already sunflowered
class NudgeTracker {
  static int _articlesOpenedInSession = 0;
  static bool _nudgeShownThisSession = false;

  /// Call when a user opens an article
  static void recordArticleOpen() {
    _articlesOpenedInSession++;
  }

  /// Check if the nudge should be shown for the current article.
  static Future<bool> shouldShowNudge({
    required bool isAlreadySunflowered,
  }) async {
    if (isAlreadySunflowered) return false;
    if (_nudgeShownThisSession) return false;
    if (_articlesOpenedInSession <= 2) return false;
    try {
      return NudgeService().canShow(NudgeIds.sunflowerRecommend);
    } catch (_) {
      return false;
    }
  }

  /// Mark nudge as shown (persists date for cooldown)
  static Future<void> markNudgeShown() async {
    _nudgeShownThisSession = true;
    try {
      await NudgeService().markShown(NudgeIds.sunflowerRecommend);
    } catch (_) {
      // Best-effort persistence
    }
  }
}
