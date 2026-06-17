import 'package:flutter/material.dart';
import 'wheel_time_picker.dart';

/// A compact widget for picking video start time and duration.
///
/// Start time: scroll wheel (MM:SS, 0-59:59) with keyboard toggle.
/// Duration:   scroll wheel (M:SS, 0-6:00) with keyboard toggle,
///             value passed as total seconds to the backend.
class TimeRangePicker extends StatefulWidget {
  final String initialStartTime;
  final int initialDuration;
  final ValueChanged<String>? onStartTimeChanged;
  final ValueChanged<int>? onDurationChanged;

  const TimeRangePicker({
    super.key,
    this.initialStartTime = '00:00',
    this.initialDuration = 10,
    this.onStartTimeChanged,
    this.onDurationChanged,
  });

  @override
  State<TimeRangePicker> createState() => _TimeRangePickerState();
}

class _TimeRangePickerState extends State<TimeRangePicker> {
  @override
  Widget build(BuildContext context) {
    // Parse initialStartTime "MM:SS" → minutes, seconds
    final startParts = widget.initialStartTime.split(':');
    final startMin = startParts.isNotEmpty ? int.tryParse(startParts[startParts.length - 2]) ?? 0 : 0;
    final startSec = startParts.length >= 2 ? int.tryParse(startParts.last) ?? 0 : 0;

    // Parse initialDuration (seconds) → minutes, seconds
    final durMin = widget.initialDuration ~/ 60;
    final durSec = widget.initialDuration % 60;

    return Row(
      children: [
        // Start time — 4 digit columns (分十位, 分个位, 秒十位, 秒个位)
        Expanded(
          flex: 2,
          child: WheelTimePicker(
            label: '开始时间',
            icon: Icons.timer_outlined,
            maxMinutes: 59,
            initialMinutes: startMin.clamp(0, 59),
            initialSeconds: startSec.clamp(0, 59),
            splitMinutes: true,
            splitSeconds: true,
            onChanged: (m, s) {
              widget.onStartTimeChanged
                  ?.call('${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}');
            },
          ),
        ),
        const SizedBox(width: 12),
        // Duration — 3 digit columns (分, 秒十位, 秒个位), max 6:00
        Expanded(
          flex: 1,
          child: WheelTimePicker(
            label: '耗时',
            icon: Icons.timelapse,
            maxMinutes: 6,
            initialMinutes: durMin.clamp(0, 6),
            initialSeconds: durSec.clamp(0, 59),
            splitMinutes: false,
            splitSeconds: true,
            maxTotalSeconds: 360,
            onChanged: (m, s) {
              final totalSeconds = m * 60 + s;
              if (totalSeconds > 0) {
                widget.onDurationChanged?.call(totalSeconds);
              }
            },
          ),
        ),
      ],
    );
  }
}
