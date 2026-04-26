import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/providers.dart';

const String _kNudgesEnabledKey = 'nudges_enabled';

/// Kill switch: reads `app_config.nudges_enabled` (jsonb boolean) at boot.
///
/// Failure modes (network error, table missing, RLS blocks read, malformed
/// value) all resolve to `true` — the switch only *disables* nudges; it can
/// never cause them to fail closed. The welcome tour (priority=critical) is
/// unaffected regardless.
final nudgesEnabledProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final row = await client
        .from('app_config')
        .select('value')
        .eq('key', _kNudgesEnabledKey)
        .maybeSingle();
    if (row == null) return true;
    final value = row['value'];
    if (value is bool) return value;
    return true;
  } on PostgrestException catch (e) {
    debugPrint('nudgesEnabledProvider Postgrest: ${e.message}');
    return true;
  } catch (e) {
    debugPrint('nudgesEnabledProvider failure: $e');
    return true;
  }
});
