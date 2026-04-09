import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_client.dart';

/// Thrown when Android refuses to install the APK (e.g. signature mismatch).
class AppUpdateInstallException implements Exception {
  final String message;
  final bool isIncompatible;
  AppUpdateInstallException({required this.message, this.isIncompatible = false});

  @override
  String toString() => 'AppUpdateInstallException: $message';
}

/// Handles APK download and installation trigger.
class AppUpdateService {
  final ApiClient _apiClient;

  AppUpdateService(this._apiClient);

  /// Download the latest APK and return the local file path.
  ///
  /// [onProgress] receives (received, total) bytes for progress display.
  /// Throws on failure.
  Future<String> downloadApk({
    required void Function(int received, int total) onProgress,
  }) async {
    // 1. Get temporary download URL from backend
    final urlResponse = await _apiClient.get('app/update/download-url');
    final downloadUrl = (urlResponse as Map<String, dynamic>)['url'] as String;

    // 2. Get temp directory for download
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/facteur-update.apk';

    // 3. Download APK with progress using a clean Dio (no auth interceptors)
    final downloadDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ));

    await downloadDio.download(
      downloadUrl,
      filePath,
      onReceiveProgress: onProgress,
    );

    return filePath;
  }

  /// Trigger Android install intent for an already-downloaded APK.
  ///
  /// Throws [AppUpdateInstallException] if the system refuses to install.
  Future<void> installApk(String filePath) async {
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw AppUpdateInstallException(
        message: result.message,
        isIncompatible: true,
      );
    }
  }
}
