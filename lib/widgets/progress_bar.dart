import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A sleek, draggable video progress bar.
///
/// Displays elapsed time on left, remaining on right,
/// with a thin bar that expands slightly while dragging.
class VideoProgressBar extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const VideoProgressBar({
    super.key,
    required this.controller,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final position = value.position;
        final duration = value.duration;
        final progress =
            duration.inMilliseconds > 0
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  onDragStart?.call();
                  _seekTo(context, details.localPosition.dx, duration);
                },
                onHorizontalDragUpdate: (details) {
                  _seekTo(context, details.localPosition.dx, duration);
                },
                onHorizontalDragEnd: (_) => onDragEnd?.call(),
                child: SizedBox(
                  height: 36, // fat hit target
                  child: Center(
                    child: _ProgressBarThumb(progress: progress),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '-${_formatDuration(duration - position)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _seekTo(BuildContext ctx, double localX, Duration duration) {
    if (duration.inMilliseconds == 0) return;
    final box = ctx.findRenderObject() as RenderBox;
    // Measure relative to the progress bar's horizontal bounds
    final barWidth = box.size.width;
    final ratio = (localX / barWidth).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (duration.inMilliseconds * ratio).round(),
    );
    controller.seekTo(target);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

class _ProgressBarThumb extends StatelessWidget {
  final double progress;
  const _ProgressBarThumb({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Track
            Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Progress
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Knob
            Positioned(
              left: (constraints.maxWidth * progress) - 6,
              top: -4,
              child: Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
