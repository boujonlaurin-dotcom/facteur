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
    return AppUpdateInfo(
      latestTag: latestTag,
      name: json['name'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      apkSize: json['apk_size'] as int?,
      updateAvailable: _isNewer(latestTag, AppUpdateConstants.releaseTag),
    );
  }

  /// Lexicographic comparison works for date-based tags:
  /// "beta-20260221-1430" > "beta-20260220-0900"
  static bool _isNewer(String remote, String local) {
    if (local.isEmpty) return false; // dev build: hide update
    return remote.compareTo(local) > 0;
  }

  /// Format APK size for display (e.g. "62.3 MB")
  String get formattedSize {
    if (apkSize == null) return '';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Checks for app updates. Returns null if not a release build or check fails.
final appUpdateProvider =
    FutureProvider.autoDispose<AppUpdateInfo?>((ref) async {
  if (!AppUpdateConstants.isReleaseBuild) return null;

  try {
    final apiClient = ref.read(apiClientProvider);
    final data = await apiClient.get('/app/update');
    return AppUpdateInfo.fromJson(data as Map<String, dynamic>);
  } catch (_) {
    // Fail silently — update check should never block the app
    return null;
  }
});
