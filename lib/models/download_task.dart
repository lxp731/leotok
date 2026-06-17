/// Represents a download task tracked by the backend.
class DownloadTask {
  final String taskId;
  final String url;
  final String startTime;
  final int duration;
  final String quality;
  final String? proxy;

  String status; // pending | downloading | done | failed | cancelled
  double progress; // 0–100
  String? speed;
  String? eta;
  String? filename;
  String? filepath;
  String? filesize;
  String? error;
  final String createdAt;

  DownloadTask({
    required this.taskId,
    required this.url,
    required this.startTime,
    required this.duration,
    this.quality = '720p',
    this.proxy,
    this.status = 'pending',
    this.progress = 0.0,
    this.speed,
    this.eta,
    this.filename,
    this.filepath,
    this.filesize,
    this.error,
    required this.createdAt,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      taskId: json['task_id'] as String,
      url: json['url'] as String? ?? '',
      startTime: json['start_time'] as String? ?? '00:00',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      quality: json['quality'] as String? ?? '720p',
      proxy: json['proxy'] as String?,
      status: json['status'] as String? ?? 'pending',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      speed: json['speed'] as String?,
      eta: json['eta'] as String?,
      filename: json['filename'] as String?,
      filepath: json['filepath'] as String?,
      filesize: json['filesize'] as String?,
      error: json['error'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );
  }

  bool get isActive => status == 'pending' || status == 'downloading';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';
}
