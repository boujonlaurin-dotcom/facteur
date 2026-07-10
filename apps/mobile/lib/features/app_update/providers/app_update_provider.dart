import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/providers.dart';

/// Info about the latest available release.
class AppUpdateInfo {
  final String latestTag;
  final String name;
  final String notes;
  final String publishedAt;
  final int? apkSize;
  final bool updateAvailable;

  const AppUpdateInfo({
    required this.latestTag,
    required this.name,
    required this.notes,
    required this.publishedAt,
    this.apkSize,
    required this.updateAvailable,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final latestTag = json['tag'] as String;
    final hasApk = json['apk_asset_id'] != null;
    return AppUpdateInfo(
      latestTag: latestTag,
      name: json['name'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      apkSize: json['apk_size'] as int?,
      updateAvailable:
          hasApk && _isNewer(latestTag, AppUpdateConstants.releaseTag),
    );
  }

  /// Tags émis par la CI au format `<canal>-YYYYMMDD-HHMM`
  /// (ex. "beta-20260221-1430", "release-20260221-1430").
  ///
  /// On parse la structure plutôt que de comparer lexicographiquement : si
  /// l'un des deux tags n'est pas au format attendu, ou si les canaux diffèrent
  /// (formats incomparables), on renvoie `false` — jamais de point rouge
  /// fantôme sur une comparaison ambiguë.
  static final RegExp _tagPattern =
      RegExp(r'^(beta|release)-(\d{8})-(\d{4})$');

  /// Clé numérique triable `YYYYMMDD * 10000 + HHMM`, préfixée du canal.
  /// `null` si le tag n'est pas au format attendu.
  static ({String channel, int key})? _parseTag(String tag) {
    final m = _tagPattern.firstMatch(tag);
    if (m == null) return null;
    return (
      channel: m.group(1)!,
      key: int.parse(m.group(2)!) * 10000 + int.parse(m.group(3)!),
    );
  }

  /// Exposé pour les tests (le vrai `local` est un `String.fromEnvironment`
  /// figé à la compilation, impossible à piloter depuis un test).
  @visibleForTesting
  static bool isNewer(String remote, String local) => _isNewer(remote, local);

  static bool _isNewer(String remote, String local) {
    if (local.isEmpty) return false; // dev build: hide update
    final r = _parseTag(remote);
    final l = _parseTag(local);
    // Formats incomparables (parse échoué ou canaux différents) : pas de MAJ.
    if (r == null || l == null || r.channel != l.channel) return false;
    return r.key > l.key;
  }

  /// Format APK size for display (e.g. "62.3 MB")
  String get formattedSize {
    if (apkSize == null) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Checks for app updates. Returns null on non-Android platforms or dev builds.
final appUpdateProvider =
    FutureProvider.autoDispose<AppUpdateInfo?>((ref) async {
  if (kIsWeb || !Platform.isAndroid) return null;
  if (!AppUpdateConstants.isReleaseBuild) return null;
  if (AppUpdateConstants.isPlayStoreBuild) return null;

  try {
    final apiClient = ref.read(apiClientProvider);
    final data = await apiClient.get(
      'app/update',
      queryParameters: {'channel': AppUpdateConstants.updateChannel},
    );
    return AppUpdateInfo.fromJson(data as Map<String, dynamic>);
  } catch (e) {
    // Fail silently — update check should never block the app
    // ignore: avoid_print
    print('AppUpdate: check failed: $e');
    return null;
  }
});
