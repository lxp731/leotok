import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';

/// Full-screen video player for downloaded videos.
///
/// Receives a taskId as route argument. Plays the file directly from shared
/// storage (both Termux and Flutter can access /sdcard/Download/).
class PlayerScreen extends StatefulWidget {
  final String taskId;

  const PlayerScreen({super.key, required this.taskId});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final dp = context.read<DownloadProvider>();
      await dp.refreshTasks();
      final tasks = dp.tasks;
      final task = tasks.where((t) => t.taskId == widget.taskId).firstOrNull;

      if (task == null || task.filename == null) {
        setState(() => _error = '找不到视频文件');
        return;
      }

      final filePath = '/sdcard/Download/${task.filename}';
      final file = File(filePath);
      if (!await file.exists()) {
        setState(() => _error = '文件不存在: $filePath');
        return;
      }

      final controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      _controller = controller;
      await controller.initialize();
      await controller.play();
      await controller.setLooping(true);

      controller.addListener(() {
        if (mounted) setState(() {});
      });

      setState(() => _initialized = true);
    } catch (e) {
      setState(() => _error = '播放失败: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🎬 播放'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.white)),
                ],
              )
            : !_initialized
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                    onTap: () {
                      if (_controller!.value.isPlaying) {
                        _controller!.pause();
                      } else {
                        _controller!.play();
                      }
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                        if (!_controller!.value.isPlaying)
                          const Icon(Icons.play_circle_fill,
                              size: 64, color: Colors.white54),
                      ],
                    ),
                  ),
      ),
    );
  }
}
