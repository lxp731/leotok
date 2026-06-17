import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A video progress bar with tap-to-seek, drag precision, and time preview.
///
/// - Tap anywhere to jump to that position.
/// - Drag horizontally to scrub; pull finger away vertically for fine scrubbing.
/// - A time preview floats above the thumb while dragging.
class VideoProgressBar extends StatefulWidget {
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
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  bool _isDragging = false;
  late Duration _dragPosition;

  @override
  void initState() {
    super.initState();
    _dragPosition = widget.controller.value.position;
  }

  void _seekTo(BuildContext ctx, double localX, Duration duration,
      {double? verticalOffset}) {
    if (duration.inMilliseconds == 0) return;
    final box = ctx.findRenderObject() as RenderBox;
    final barWidth = box.size.width;
    var ratio = (localX / barWidth).clamp(0.0, 1.0);

    // Drag precision: if finger is pulled away vertically, reduce sensitivity.
    // The further away, the finer the scrubbing (YouTube-style).
    if (verticalOffset != null && verticalOffset.abs() > 30) {
      // Scale ratio around the current position — acts like a "scrub gear".
      final currentRatio = widget.controller.value.position.inMilliseconds /
          duration.inMilliseconds;
      final distance = (verticalOffset.abs() - 30) / 100; // 0..n
      final factor = 1.0 / (1.0 + distance * 3); // e.g. 1×, 0.25×, 0.1×
      ratio = currentRatio + (ratio - currentRatio) * factor;
      ratio = ratio.clamp(0.0, 1.0);
    }

    final target = Duration(
      milliseconds: (duration.inMilliseconds * ratio).round(),
    );
    _dragPosition = target;
    widget.controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final position = value.position;
        final duration = value.duration;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        final displayPosition = _isDragging ? _dragPosition : position;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time preview overlay (shown while dragging)
              if (_isDragging)
                _TimePreview(
                  position: _dragPosition,
                  duration: duration,
                  barWidth: MediaQuery.of(context).size.width - 32,
                  progressRatio: duration.inMilliseconds > 0
                      ? _dragPosition.inMilliseconds / duration.inMilliseconds
                      : 0.0,
                ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  setState(() => _isDragging = true);
                  widget.onDragStart?.call();
                  _seekTo(context, details.localPosition.dx, duration);
                  setState(() => _isDragging = false);
                  widget.onDragEnd?.call();
                },
                onHorizontalDragStart: (details) {
                  setState(() {
                    _isDragging = true;
                    _dragPosition = position;
                  });
                  widget.onDragStart?.call();
                  _seekTo(context, details.localPosition.dx, duration);
                },
                onHorizontalDragUpdate: (details) {
                  _seekTo(context, details.localPosition.dx, duration,
                      verticalOffset: details.localPosition.dy);
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _isDragging = false);
                  widget.onDragEnd?.call();
                },
                child: SizedBox(
                  height: 40, // fat hit target
                  child: Center(
                    child: _ProgressBarThumb(progress: progress),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '-${_formatDuration(duration - displayPosition)}',
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
  }
}

/// A floating chip showing the scrub position time.
class _TimePreview extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final double barWidth;
  final double progressRatio;

  const _TimePreview({
    required this.position,
    required this.duration,
    required this.barWidth,
    required this.progressRatio,
  });

  @override
  Widget build(BuildContext context) {
    final totalWidth = barWidth;
    // Clamp so the preview doesn't go off-screen
    final leftOffset = (totalWidth * progressRatio).clamp(30.0, totalWidth - 30.0);

    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          Positioned(
            left: leftOffset - 35,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _fmt(position),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0
        ? '${h}:$m:$s'
        : '$m:$s';
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
