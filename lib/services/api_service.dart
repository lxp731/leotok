import 'package:dio/dio.dart';
import '../models/download_task.dart';

/// HTTP client for communicating with the Termux-hosted Python backend.
///
/// All endpoints are on localhost because the server runs inside Termux
/// on the same device.
class ApiService {
  late final Dio _dio;

  ApiService({String baseUrl = 'http://127.0.0.1:8000'}) {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  void updateBaseUrl(String url) {
    _dio.options.baseUrl = url;
  }

  /// Check if the Termux backend is reachable.
  Future<Map<String, dynamic>> healthCheck() async {
    final resp = await _dio.get('/api/health');
    return resp.data as Map<String, dynamic>;
  }

  /// Start a new download task.
  Future<DownloadTask> startDownload({
    required String url,
    required String startTime,
    required int duration,
    String quality = '720p',
    String? proxy,
    String? outputDir,
  }) async {
    final resp = await _dio.post('/api/download', data: {
      'url': url,
      'start_time': startTime,
      'duration': duration,
      'quality': quality,
      'proxy': proxy,
      // ignore: use_null_aware_elements
      if (outputDir != null) 'output_dir': outputDir,
    });
    return DownloadTask.fromJson(resp.data as Map<String, dynamic>);
  }

  /// Get a single task's status (polled during active download).
  Future<DownloadTask> getTask(String taskId) async {
    final resp = await _dio.get('/api/tasks/$taskId');
    return DownloadTask.fromJson(resp.data as Map<String, dynamic>);
  }

  /// List all tasks (for gallery / history).
  Future<List<DownloadTask>> listTasks() async {
    final resp = await _dio.get('/api/tasks');
    final list = resp.data as List<dynamic>;
    return list
        .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cancel a running download.
  Future<void> cancelTask(String taskId) async {
    await _dio.delete('/api/tasks/$taskId');
  }

  /// Delete a completed download (file + record).
  Future<void> deleteVideo(String taskId) async {
    await _dio.delete('/api/videos/$taskId');
  }

  /// Test proxy connectivity.
  Future<bool> testProxy(String proxyUrl) async {
    try {
      final resp = await _dio.post('/api/proxy/test', data: {
        'proxy': proxyUrl,
      });
      return (resp.data as Map<String, dynamic>)['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
