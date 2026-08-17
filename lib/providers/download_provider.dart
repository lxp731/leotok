import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/download_task.dart';
import '../services/api_service.dart';

/// Manages download tasks: starting, polling, cancelling, deleting.
class DownloadProvider extends ChangeNotifier {
  final ApiService _api;
  Timer? _pollTimer;

  DownloadProvider(this._api);

  final Map<String, DownloadTask> _tasks = {};
  List<String> _taskOrder = []; // kept in insertion order (reverse: newest first)

  /// Active polling task ID (only one download at a time).
  String? _activeTaskId;

  // ---- getters ----

  List<DownloadTask> get tasks => List.unmodifiable(_taskOrder.map((id) => _tasks[id]!));
  List<DownloadTask> get completedTasks =>
      tasks.where((t) => !t.isActive).toList();
  List<DownloadTask> get activeTasks =>
      tasks.where((t) => t.isActive).toList();
  bool get hasActive => activeTasks.isNotEmpty;
  DownloadTask? get activeTask =>
      _activeTaskId != null ? _tasks[_activeTaskId] : null;

  // ---- server status ----

  bool _serverOnline = false;
  bool _checkingServer = false;
  bool get serverOnline => _serverOnline;
  bool get checkingServer => _checkingServer;

  /// Check if the Termux backend is reachable.
  Future<bool> checkServer() async {
    _checkingServer = true;
    notifyListeners();
    try {
      await _api.healthCheck();
      _serverOnline = true;
    } catch (_) {
      _serverOnline = false;
    }
    _checkingServer = false;
    notifyListeners();
    return _serverOnline;
  }

  // ---- actions ----

  /// Start a new download. Returns the task ID.
  Future<String?> startDownload({
    required String url,
    required String startTime,
    required int duration,
    String quality = '720p',
    String? proxy,
    String? outputDir,
  }) async {
    try {
      final task = await _api.startDownload(
        url: url,
        startTime: startTime,
        duration: duration,
        quality: quality,
        proxy: proxy,
        outputDir: outputDir,
      );
      _tasks[task.taskId] = task;
      _taskOrder.insert(0, task.taskId);
      _activeTaskId = task.taskId;
      notifyListeners();

      // Start polling for progress
      _startPolling(task.taskId);
      return task.taskId;
    } catch (e) {
      debugPrint('Failed to start download: $e');
      return null;
    }
  }

  void _startPolling(String taskId) {
    _pollTimer?.cancel();
    _pollErrorCount = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      await _pollTask(taskId);
    });
  }

  /// Consecutive poll failures before the task is marked failed and polling
  /// stops (~10s at 500ms interval). Prevents an unreachable/restarted
  /// backend from leaving the UI stuck on "下载进行中" forever.
  static const int _maxPollErrors = 20;
  int _pollErrorCount = 0;

  Future<void> _pollTask(String taskId) async {
    try {
      final updated = await _api.getTask(taskId);
      _tasks[taskId] = updated;
      _pollErrorCount = 0;

      if (!updated.isActive) {
        // Download finished (or failed/cancelled)
        if (taskId == _activeTaskId) {
          _activeTaskId = null;
          _pollTimer?.cancel();
        }
      }
      notifyListeners();
    } on DioException catch (e) {
      // 404 = the backend no longer knows this task (e.g. server restarted).
      // Treat it as terminal immediately; other network errors get a grace
      // period before giving up.
      final taskGone = e.response?.statusCode == 404;
      _pollErrorCount++;
      if (taskGone || _pollErrorCount >= _maxPollErrors) {
        _failPolling(taskId, taskGone
            ? '后端已重启，任务状态丢失'
            : '连接后端失败（网络错误）');
      }
    } catch (_) {
      _pollErrorCount++;
      if (_pollErrorCount >= _maxPollErrors) {
        _failPolling(taskId, '连接后端失败（网络错误）');
      }
    }
  }

  /// Marks the task as failed and stops polling so the UI unblocks.
  void _failPolling(String taskId, String message) {
    final task = _tasks[taskId];
    if (task != null && task.isActive) {
      task.status = 'failed';
      task.error = message;
    }
    if (taskId == _activeTaskId) {
      _activeTaskId = null;
      _pollTimer?.cancel();
    }
    _pollErrorCount = 0;
    notifyListeners();
  }

  /// Cancel the active download.
  Future<void> cancelActive() async {
    if (_activeTaskId == null) return;
    try {
      await _api.cancelTask(_activeTaskId!);
    } catch (_) {}
    _tasks[_activeTaskId]?.status = 'cancelled';
    _activeTaskId = null;
    _pollTimer?.cancel();
    _pollErrorCount = 0;
    notifyListeners();
  }

  /// Point the HTTP client at a new backend URL (used when the user edits
  /// the server URL in settings — takes effect immediately, no restart).
  void updateServerUrl(String url) {
    _api.updateBaseUrl(url);
    _serverOnline = false;
    checkServer();
  }

  /// Delete a completed download (file + server record).
  Future<bool> deleteTask(String taskId) async {
    try {
      await _api.deleteVideo(taskId);
      _tasks.remove(taskId);
      _taskOrder.remove(taskId);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Remove only the local record — never touches the file on disk.
  void removeRecord(String taskId) {
    _tasks.remove(taskId);
    _taskOrder.remove(taskId);
    notifyListeners();
  }

  /// Delete all completed tasks (files + records).
  Future<void> clearAllTasks() async {
    final completed = completedTasks;
    for (final t in completed) {
      try {
        await _api.deleteVideo(t.taskId);
        _tasks.remove(t.taskId);
        _taskOrder.remove(t.taskId);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Remove all local records without touching files.
  void clearAllRecords() {
    _tasks.clear();
    _taskOrder.clear();
    notifyListeners();
  }

  /// Load all tasks from backend (for gallery refresh).
  Future<void> refreshTasks() async {
    try {
      final list = await _api.listTasks();
      _tasks.clear();
      _taskOrder.clear();
      for (final t in list) {
        _tasks[t.taskId] = t;
        _taskOrder.add(t.taskId);
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
