import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../models/download_task.dart';

/// Shows download progress with percentage, speed, ETA, and cancel button.
class DownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onCancel;

  const DownloadCard({super.key, required this.task, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isActive = task.isActive;
    final isDone = task.isDone;
    final isFailed = task.isFailed;
    final isCancelled = task.isCancelled;

    return Card(
      color: isDone
          ? Colors.green.shade900
          : isFailed
          ? Colors.red.shade900
          : isCancelled
          ? Colors.amber.shade800
          : Colors.grey.shade900,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: (isDone && task.filepath != null)
            ? () => _openInFileManager(task.filepath!)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Icon(
                    isDone
                        ? Icons.check_circle
                        : isFailed
                        ? Icons.error
                        : isCancelled
                        ? Icons.cancel
                        : Icons.downloading,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isActive
                          ? '下载中...'
                          : isDone
                          ? '下载完成'
                          : isCancelled
                          ? '已取消'
                          : '下载失败',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isActive && onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress bar
              if (isActive) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: task.progress / 100.0,
                    backgroundColor: Colors.white24,
                    color: Colors.blue,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${task.progress.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],

              // Speed / ETA
              if (isActive && (task.speed != null || task.eta != null)) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (task.speed != null) ...[
                      const Icon(Icons.speed, size: 14, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        task.speed!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    if (task.eta != null) ...[
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '剩余 ${task.eta!}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ],

              // File info (when done)
              if (isDone) ...[
                Text(
                  task.filename ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                if (task.filesize != null)
                  Text(
                    task.filesize!,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              ],

              // Error message
              if (isFailed && task.error != null)
                Text(
                  task.error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Open the system file manager at the directory containing [filepath].
Future<void> _openInFileManager(String filepath) async {
  debugPrint('📂 Open in file manager: $filepath');

  final dir = filepath.substring(0, filepath.lastIndexOf('/'));
  final dirUri = _toContentUri(dir);
  if (dirUri == null) {
    debugPrint('❌ Cannot convert path to content URI');
    return;
  }

  // Strategy 1: open directory with DocumentsContract MIME type.
  // This targets the system DocumentsUI (file manager) directly.
  try {
    final intent = AndroidIntent(
      action: 'action_view',
      data: dirUri,
      type: 'vnd.android.document/directory',
    );
    await intent.launch();
    debugPrint('✅ Opened directory via directory MIME: $dirUri');
    return;
  } catch (e) {
    debugPrint('⚠️  directory MIME failed: $e');
  }

  // Strategy 2: open directory without MIME type — Android infers from URI.
  try {
    final intent = AndroidIntent(action: 'action_view', data: dirUri);
    await intent.launch();
    debugPrint('✅ Opened directory via no-MIME: $dirUri');
    return;
  } catch (e) {
    debugPrint('⚠️  no-MIME failed: $e');
  }

  // Strategy 3: open the file itself — app chooser should include file managers.
  try {
    final fileUri = _toContentUri(filepath)!;
    final intent = AndroidIntent(
      action: 'action_view',
      data: fileUri,
      type: 'video/mp4',
    );
    await intent.launch();
    debugPrint('✅ Opened file via video/mp4');
  } catch (e) {
    debugPrint('❌ All strategies failed: $e');
  }
}

/// Convert an absolute file path to a content:// URI via ExternalStorageProvider.
///
/// Returns `null` if the path is not under a recognised storage root.
String? _toContentUri(String absolutePath) {
  // Common Android storage roots
  const roots = <String>['/storage/emulated/0/', '/sdcard/'];
  for (final root in roots) {
    if (absolutePath.startsWith(root)) {
      final relative = absolutePath.substring(root.length);
      // Document ID: primary:<relative-path>
      final docId = 'primary:$relative';
      return 'content://com.android.externalstorage.documents/document/${Uri.encodeComponent(docId)}';
    }
  }
  return null;
}
