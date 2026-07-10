import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/providers.dart';
import '../../../core/version/semver.dart';

/// Niveau d'incitation à la mise à jour iOS, résolu à partir de la version
/// installée et des deux seuils distants ([app_config]).
enum IosUpdateLevel {
  /// À jour (ou indéterminé / fail-open) : rien à afficher.
  none,

  /// `installée < ios_latest_version` : bannière incitative non bloquante.
  banner,

  /// `installée < ios_min_supported_version` : gate bloquant.
  gate,
}

/// Résultat du contrôle de version iOS : niveau + fiche App Store à ouvrir.
@immutable
class IosUpdateStatus {
  const IosUpdateStatus({required this.level, this.appStoreUrl});

  final IosUpdateLevel level;
  final String? appStoreUrl;

  static const none = IosUpdateStatus(level: IosUpdateLevel.none);
}

const String _kLatestKey = 'ios_latest_version';
const String _kMinSupportedKey = 'ios_min_supported_version';
const String _kAppStoreUrlKey = 'ios_app_store_url';

/// Logique pure de résolution du niveau (testable sans `Platform` ni réseau).
///
/// Priorité au gate. Toute valeur manquante ou non parsable rend le seuil
/// concerné inopérant (fail-open) :
/// - `installed < min`            → [IosUpdateLevel.gate]
/// - sinon `installed < latest`   → [IosUpdateLevel.banner]
/// - sinon                        → [IosUpdateLevel.none]
IosUpdateLevel resolveIosUpdateLevel({
  required String installed,
  String? latest,
  String? minSupported,
}) {
  if (minSupported != null) {
    final cmp = compareSemver(installed, minSupported);
    if (cmp != null && cmp < 0) return IosUpdateLevel.gate;
  }
  if (latest != null) {
    final cmp = compareSemver(installed, latest);
    if (cmp != null && cmp < 0) return IosUpdateLevel.banner;
  }
  return IosUpdateLevel.none;
}

/// Lit une clé `app_config` (jsonb string) ; `null` si absente/non-string.
Future<String?> _readConfigString(SupabaseClient client, String key) async {
  final row = await client
      .from('app_config')
      .select('value')
      .eq('key', key)
      .maybeSingle();
  final value = row?['value'];
  return value is String ? value : null;
}

/// Contrôle de version iOS : compare la version installée aux deux seuils
/// distants servis par `app_config` (même pattern que [nudgesEnabledProvider]).
///
/// **iOS uniquement** : web et Android renvoient toujours [IosUpdateStatus.none]
/// (Android a son propre flow de self-update via `appUpdateProvider`).
///
/// **Fail-open** : toute erreur (réseau, table/clé absente, RLS, valeur
/// malformée) résout en [IosUpdateLevel.none] — jamais de gate accidentel.
final iosUpdateStatusProvider = FutureProvider<IosUpdateStatus>((ref) async {
  if (kIsWeb || !Platform.isIOS) return IosUpdateStatus.none;

  try {
    final info = await PackageInfo.fromPlatform();
    final installed = info.version;
    if (installed.isEmpty) return IosUpdateStatus.none;

    final client = ref.watch(supabaseClientProvider);
    final latest = await _readConfigString(client, _kLatestKey);
    final minSupported = await _readConfigString(client, _kMinSupportedKey);
    final appStoreUrl = await _readConfigString(client, _kAppStoreUrlKey);

    final level = resolveIosUpdateLevel(
      installed: installed,
      latest: latest,
      minSupported: minSupported,
    );

    // Sans fiche App Store on ne peut rien proposer : reste neutre.
    if (level == IosUpdateLevel.none || appStoreUrl == null) {
      return IosUpdateStatus.none;
    }
    return IosUpdateStatus(level: level, appStoreUrl: appStoreUrl);
  } on PostgrestException catch (e) {
    debugPrint('iosUpdateStatusProvider Postgrest: ${e.message}');
    return IosUpdateStatus.none;
  } catch (e) {
    debugPrint('iosUpdateStatusProvider failure: $e');
    return IosUpdateStatus.none;
  }
});

/// Masquage de la bannière pour la session courante (le `×`). Non persistant :
/// la bannière revient au prochain lancement tant que la version reste en deçà
/// de `ios_latest_version`. Sans effet sur le gate (non masquable).
final iosBannerDismissedProvider = StateProvider<bool>((ref) => false);
