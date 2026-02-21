import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_client.dart';

/// Handles APK download and installation trigger.
class AppUpdateService {
  final ApiClient _apiClient;

  AppUpdateService(this._apiClient);

  /// Download the latest APK and trigger Android install.
  ///
  /// [onProgress] receives (received, total) bytes for progress display.
  /// Throws on failure.
  Future<void> downloadAndInstall({
    required void Function(int received, int total) onProgress,
  }) async {
    // 1. Get temporary download URL from backend
    final urlResponse = await _apiClient.get('/app/update/download-url');
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

    // 4. Trigger Android install intent
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      throw Exception('Failed to open APK: ${result.message}');
    }
  }
}
