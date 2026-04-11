import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the 🌻 "Recommander ?" nudge display logic.
///
/// Rules:
/// - Show after >30s of reading an article
/// - Skip the first 2 articles read in the session
/// - Max 1 nudge per session
/// - Max 1 nudge every 3 days (persisted via SharedPreferences)
/// - Don't show if article is already sunflowered
class NudgeState {
  final int articlesOpenedInSession;
  final bool nudgeShownThisSession;

  const NudgeState({
    this.articlesOpenedInSession = 0,
    this.nudgeShownThisSession = false,
  });

  NudgeState copyWith({
    int? articlesOpenedInSession,
    bool? nudgeShownThisSession,
  }) {
    return NudgeState(
      articlesOpenedInSession:
          articlesOpenedInSession ?? this.articlesOpenedInSession,
      nudgeShownThisSession:
          nudgeShownThisSession ?? this.nudgeShownThisSession,
    );
  }
}

class NudgeNotifier extends Notifier<NudgeState> {
  static const _lastNudgeDateKey = 'sunflower_last_nudge_date';
  static const _nudgeCooldownDays = 3;

  @override
  NudgeState build() {
    return const NudgeState();
  }

  /// Call when a user opens an article
  void recordArticleOpen() {
    state = state.copyWith(
      articlesOpenedInSession: state.articlesOpenedInSession + 1,
    );
  }

  /// Check if the nudge should be shown for the current article.
  /// Returns true if all conditions are met.
  Future<bool> shouldShowNudge({required bool isAlreadySunflowered}) async {
    // Already sunflowered — no nudge
    if (isAlreadySunflowered) return false;

    // Already shown this session
    if (state.nudgeShownThisSession) return false;

    // Skip first 2 articles of the session
    if (state.articlesOpenedInSession <= 2) return false;

    // Check 3-day cooldown
    final prefs = await SharedPreferences.getInstance();
    final lastNudgeDateStr = prefs.getString(_lastNudgeDateKey);
    if (lastNudgeDateStr != null) {
      final lastDate = DateTime.tryParse(lastNudgeDateStr);
      if (lastDate != null) {
        final daysSince = DateTime.now().difference(lastDate).inDays;
        if (daysSince < _nudgeCooldownDays) return false;
      }
    }

    return true;
  }

  /// Mark nudge as shown (persists date for cooldown)
  Future<void> markNudgeShown() async {
    state = state.copyWith(nudgeShownThisSession: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastNudgeDateKey,
      DateTime.now().toIso8601String(),
    );
  }
}

final nudgeProvider =
    NotifierProvider<NudgeNotifier, NudgeState>(NudgeNotifier.new);
