import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/analytics_provider.dart';
import '../services/posthog_service.dart';
import 'nudge.dart';
import 'nudge_registry.dart';

/// PostHog event names.
const String _kEventShown = 'nudge_shown';
const String _kEventDismissed = 'nudge_dismissed';

/// Stateless emitter for nudge telemetry. Lookups the Nudge metadata from
/// [NudgeRegistry] so call-sites only pass the id.
class NudgeEvents {
  NudgeEvents(this._posthog);

  final PostHogService _posthog;

  Future<void> shown(String id) async {
    final nudge = NudgeRegistry.get(id);
    await _posthog.capture(
      event: _kEventShown,
      properties: _propsFor(nudge),
    );
  }

  /// outcome is 'dismissed' or 'converted'.
  Future<void> dismissed(String id, {required String outcome}) async {
    final nudge = NudgeRegistry.get(id);
    await _posthog.capture(
      event: _kEventDismissed,
      properties: {
        ..._propsFor(nudge),
        'outcome': outcome,
      },
    );
  }

  Map<String, Object> _propsFor(Nudge nudge) => {
        'nudge_id': nudge.id,
        'surface': nudge.surface.name,
        'placement': nudge.placement.name,
        'priority': nudge.priority.name,
      };
}

final nudgeEventsProvider = Provider<NudgeEvents>((ref) {
  return NudgeEvents(ref.watch(posthogServiceProvider));
});
