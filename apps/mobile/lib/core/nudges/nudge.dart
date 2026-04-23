import 'package:flutter/foundation.dart';

enum NudgeSurface { digest, feed, article, settings, saved, global }

enum NudgePlacement {
  modal,
  bottomSheet,
  overlay,
  inlineBanner,
  tooltip,
  hintAnimation,
}

/// Higher priority wins queue contention.
enum NudgePriority { critical, high, normal, low }

/// How often a nudge may be shown.
enum NudgeFrequency {
  /// Once per user — never again once seen.
  once,

  /// Once per app session.
  session,

  /// With a cooldown between displays (see [Nudge.cooldown]).
  cooldown,
}

/// Declarative description of a single nudge.
///
/// All nudges are registered in [nudge_registry.dart]. Runtime behavior
/// (show / dismiss / seen flag) is handled by [NudgeService] and
/// [NudgeCoordinator].
@immutable
class Nudge {
  final String id;
  final NudgeSurface surface;
  final NudgePlacement placement;
  final NudgePriority priority;
  final NudgeFrequency frequency;

  /// Only relevant when [frequency] == [NudgeFrequency.cooldown].
  final Duration? cooldown;

  /// Ids of other nudges that must be seen before this one can show.
  final List<String> prerequisites;

  /// Legacy SharedPreferences key for the "seen" flag, if the nudge
  /// existed before the unified system. Read once, then migrated.
  final String? legacySeenKey;

  /// Legacy SharedPreferences key for "last shown date" (ISO8601), if any.
  final String? legacyLastShownKey;

  /// Whether this nudge counts against the per-session non-critical budget.
  /// `critical`/`high` bypass the budget; `normal`/`low` consume it.
  bool get consumesSessionBudget =>
      priority == NudgePriority.normal || priority == NudgePriority.low;

  const Nudge({
    required this.id,
    required this.surface,
    required this.placement,
    required this.priority,
    required this.frequency,
    this.cooldown,
    this.prerequisites = const [],
    this.legacySeenKey,
    this.legacyLastShownKey,
  }) : assert(
          frequency != NudgeFrequency.cooldown || cooldown != null,
          'cooldown frequency requires a cooldown duration',
        );
}
