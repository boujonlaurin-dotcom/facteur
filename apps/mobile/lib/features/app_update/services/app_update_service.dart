import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_client.dart';

/// Snapshot of the current update download.
class UpdateProgress {
  final String taskId;
  final DownloadTaskStatus status;
  final int progress; // 0-100
  final String? errorMessage;
  final bool isIncompatible;

  const UpdateProgress({
    required this.taskId,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.isIncompatible = false,
  });
}

const _kPortName = 'facteur_app_update_port';
const _kHiveTaskId = 'update_task_id';
const _kHiveFilePath = 'update_file_path';
const _kApkFileName = 'facteur-update.apk';

/// Singleton managing the APK download lifecycle via Android DownloadManager.
///
/// Survives app backgrounding because flutter_downloader uses a system service.
/// The widget reconnects to an in-flight task at rebuild via [resumeIfActive].
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  final StreamController<UpdateProgress> _controller =
      StreamController<UpdateProgress>.broadcast();
  Stream<UpdateProgress> get progressStream => _controller.stream;

  ReceivePort? _port;
  String? _currentTaskId;
  String? _currentFilePath;
  bool _installTriggered = false;

  void _bind() {
    if (_port != null) return;
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(_port!.sendPort, _kPortName);
    _port!.listen((dynamic data) {
      final list = data as List<dynamic>;
      final id = list[0] as String;
      final status = DownloadTaskStatus.fromInt(list[1] as int);
      final progress = list[2] as int;
      _controller.add(UpdateProgress(
        taskId: id,
        status: status,
        progress: progress,
      ));
      if (id == _currentTaskId && status == DownloadTaskStatus.complete) {
        unawaited(_triggerInstall());
      }
    });
    FlutterDownloader.registerCallback(downloadCallback);
  }

  /// Starts a fresh APK download. Returns the new [UpdateProgress] (enqueued).
  Future<UpdateProgress> startUpdate(ApiClient apiClient) async {
    _bind();
    _installTriggered = false;

    final urlResponse = await apiClient.get('app/update/download-url');
    final downloadUrl = (urlResponse as Map<String, dynamic>)['url'] as String;

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$_kApkFileName';
    final stale = File(filePath);
    try {
      if (stale.existsSync()) stale.deleteSync();
    } catch (_) {/* best-effort */}

    final taskId = await FlutterDownloader.enqueue(
      url: downloadUrl,
      savedDir: dir.path,
      fileName: _kApkFileName,
      showNotification: true,
      openFileFromNotification: false,
      saveInPublicStorage: false,
    );
    if (taskId == null) {
      throw Exception('Impossible de démarrer le téléchargement');
    }

    _currentTaskId = taskId;
    _currentFilePath = filePath;
    final box = Hive.box<dynamic>('settings');
    await box.put(_kHiveTaskId, taskId);
    await box.put(_kHiveFilePath, filePath);

    return UpdateProgress(
      taskId: taskId,
      status: DownloadTaskStatus.enqueued,
      progress: 0,
    );
  }

  /// Reconnects to an existing in-flight task, if any. Returns null when
  /// nothing is active.
  Future<UpdateProgress?> resumeIfActive() async {
    final box = Hive.box<dynamic>('settings');
    final taskId = box.get(_kHiveTaskId) as String?;
    final filePath = box.get(_kHiveFilePath) as String?;
    if (taskId == null) return null;

    final tasks = await FlutterDownloader.loadTasksWithRawQuery(
      query: "SELECT * FROM task WHERE task_id='$taskId'",
    );
    if (tasks == null || tasks.isEmpty) {
      await _clearPersistedTask();
      return null;
    }
    final t = tasks.first;
    _currentTaskId = taskId;
    _currentFilePath = filePath;
    _bind();

    if (t.status == DownloadTaskStatus.complete) {
      // Download finished while app was killed — kick off install now.
      unawaited(_triggerInstall());
    } else if (t.status == DownloadTaskStatus.failed ||
        t.status == DownloadTaskStatus.canceled) {
      await _clearPersistedTask();
    }

    return UpdateProgress(
      taskId: taskId,
      status: t.status,
      progress: t.progress,
    );
  }

  Future<void> _triggerInstall() async {
    if (_installTriggered) return;
    _installTriggered = true;
    final filePath = _currentFilePath;
    if (filePath == null) return;
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      _controller.add(UpdateProgress(
        taskId: _currentTaskId ?? '',
        status: DownloadTaskStatus.failed,
        progress: 100,
        errorMessage: result.message,
        isIncompatible: true,
      ));
    }
    unawaited(_clearPersistedTask());
  }

  Future<void> _clearPersistedTask() async {
    try {
      final box = Hive.box<dynamic>('settings');
      await box.delete(_kHiveTaskId);
      await box.delete(_kHiveFilePath);
    } catch (_) {/* box might not be open in tests */}
  }
}

/// Top-level callback invoked by flutter_downloader on a background isolate.
@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final send = IsolateNameServer.lookupPortByName(_kPortName);
  send?.send(<dynamic>[id, status, progress]);
}
