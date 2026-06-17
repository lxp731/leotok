import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../models/download_task.dart';

/// Grid of completed downloads. Tap to play, long-press to delete.
class DownloadGalleryScreen extends StatefulWidget {
  const DownloadGalleryScreen({super.key});

  @override
  State<DownloadGalleryScreen> createState() => _DownloadGalleryScreenState();
}

class _DownloadGalleryScreenState extends State<DownloadGalleryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DownloadProvider>().refreshTasks();
    });
  }

  void _playVideo(DownloadTask task) {
    Navigator.pushNamed(context, '/player', arguments: task.taskId);
  }

  Future<void> _deleteTask(DownloadTask task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('删除 ${task.filename ?? '此视频'}？\n文件将被永久删除。',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await context.read<DownloadProvider>().deleteTask(task.taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? '已删除' : '删除失败'),
            backgroundColor: ok ? null : Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🖼️ 已下载'),
        backgroundColor: Colors.black,
        actions: [
          Consumer<DownloadProvider>(
            builder: (_, dp, __) => IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
              onPressed: () => dp.refreshTasks(),
            ),
          ),
        ],
      ),
      body: Consumer<DownloadProvider>(
        builder: (_, dp, __) {
          final items = dp.completedTasks;
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.video_library_outlined, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('还没有下载任何视频', style: TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => dp.refreshTasks(),
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _buildItem(items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildItem(DownloadTask task) {
    return GestureDetector(
      onTap: () => _playVideo(task),
      onLongPress: () => _deleteTask(task),
      child: Card(
        color: Colors.grey.shade900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail placeholder
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Center(
                  child: Icon(Icons.play_circle_outline,
                      size: 48, color: Colors.white38),
                ),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.filename ?? 'unknown.mp4',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (task.filesize != null) ...[
                        Text(task.filesize!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11)),
                        const SizedBox(width: 8),
                      ],
                      Text(_formatDate(task.createdAt),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
