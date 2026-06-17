import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A time picker that uses scroll wheels (like alarm clock) with an
/// optional keyboard toggle for manual input.
///
/// When [splitMinutes] / [splitSeconds] are true, each digit gets its
/// own scroll column (e.g. 4 columns for MM:SS: tens + ones for each).
class WheelTimePicker extends StatefulWidget {
  final int maxMinutes;
  final int initialMinutes;
  final int initialSeconds;
  final String label;
  final IconData icon;
  final bool splitMinutes;
  final bool splitSeconds;
  final void Function(int minutes, int seconds) onChanged;

  /// Optional clamp for total seconds (e.g. 360 for 6-minute max).
  /// When non-null, the confirmed value will not exceed this.
  final int? maxTotalSeconds;

  const WheelTimePicker({
    super.key,
    required this.maxMinutes,
    this.initialMinutes = 0,
    this.initialSeconds = 0,
    required this.label,
    required this.icon,
    this.splitMinutes = false,
    this.splitSeconds = false,
    this.maxTotalSeconds,
    required this.onChanged,
  });

  @override
  State<WheelTimePicker> createState() => _WheelTimePickerState();
}

class _WheelTimePickerState extends State<WheelTimePicker> {
  late int _minutes;
  late int _seconds;

  // Non-split controllers
  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _secCtrl;

  // Split-digit controllers
  late FixedExtentScrollController _minTCtrl;
  late FixedExtentScrollController _minOCtrl;
  late FixedExtentScrollController _secTCtrl;
  late FixedExtentScrollController _secOCtrl;

  int get _minTens => _minutes ~/ 10;
  int get _minOnes => _minutes % 10;
  int get _secTens => _seconds ~/ 10;
  int get _secOnes => _seconds % 10;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes;
    _seconds = widget.initialSeconds;
    _minCtrl = FixedExtentScrollController(initialItem: _minutes);
    _secCtrl = FixedExtentScrollController(initialItem: _seconds);
    _minTCtrl = FixedExtentScrollController(initialItem: _minTens);
    _minOCtrl = FixedExtentScrollController(initialItem: _minOnes);
    _secTCtrl = FixedExtentScrollController(initialItem: _secTens);
    _secOCtrl = FixedExtentScrollController(initialItem: _secOnes);
  }

  String get _displayText =>
      '${_minutes.toString().padLeft(2, '0')}:${_seconds.toString().padLeft(2, '0')}';

  /// Clamp pending values to max constraints, then return (clampedMinutes, clampedSeconds).
  (int, int) _clamp(int m, int s) {
    final total = m * 60 + s;
    if (widget.maxTotalSeconds != null && total > widget.maxTotalSeconds!) {
      final clamped = widget.maxTotalSeconds!;
      return (clamped ~/ 60, clamped % 60);
    }
    if (m > widget.maxMinutes) {
      return (widget.maxMinutes, 0);
    }
    if (s >= 60) return (m, 59);
    return (m, s);
  }

  void _syncSplitControllers() {
    _minTCtrl.jumpToItem(_minTens);
    _minOCtrl.jumpToItem(_minOnes);
    _secTCtrl.jumpToItem(_secTens);
    _secOCtrl.jumpToItem(_secOnes);
  }

  void _openPicker() {
    int pendingMinutes = _minutes;
    int pendingSeconds = _seconds;
    bool showManual = false;
    final manualCtrl = TextEditingController(text: _displayText);

    // Position controllers
    if (widget.splitMinutes || widget.splitSeconds) {
      _syncSplitControllers();
    } else {
      _minCtrl.jumpToItem(_minutes);
      _secCtrl.jumpToItem(_seconds);
    }

    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final preview =
              '${pendingMinutes.toString().padLeft(2, '0')}:${pendingSeconds.toString().padLeft(2, '0')}';

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- Header ----
                _HeaderRow(
                  label: widget.label,
                  preview: preview,
                  showManual: showManual,
                  onToggle: () {
                    setSheetState(() {
                      showManual = !showManual;
                      if (showManual) {
                        manualCtrl.text = preview;
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  showManual ? '键盘输入 (点击上方切换滚轮)' : '滚动选择 (点击上方切换键盘)',
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
                const SizedBox(height: 8),

                // ---- Wheels or manual input ----
                if (showManual)
                  _ManualInput(
                    controller: manualCtrl,
                    onParsed: (m, s) {
                      final (cm, cs) = _clamp(m, s);
                      pendingMinutes = cm;
                      pendingSeconds = cs;
                    },
                  )
                else if (widget.splitMinutes || widget.splitSeconds)
                  SizedBox(
                    height: 180,
                    child: _DigitWheelRow(
                      minutes: pendingMinutes,
                      seconds: pendingSeconds,
                      maxMinutes: widget.maxMinutes,
                      splitMinutes: widget.splitMinutes,
                      splitSeconds: widget.splitSeconds,
                      maxTotalSeconds: widget.maxTotalSeconds,
                      minTCtrl: _minTCtrl,
                      minOCtrl: _minOCtrl,
                      secTCtrl: _secTCtrl,
                      secOCtrl: _secOCtrl,
                      onChanged: (m, s) {
                        setSheetState(() {
                          pendingMinutes = m;
                          pendingSeconds = s;
                        });
                      },
                    ),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: _WheelRow(
                      minutes: pendingMinutes,
                      seconds: pendingSeconds,
                      maxMinutes: widget.maxMinutes,
                      minCtrl: _minCtrl,
                      secCtrl: _secCtrl,
                      onMinutesChanged: (v) {
                        pendingMinutes = v;
                        setSheetState(() {});
                      },
                      onSecondsChanged: (v) {
                        pendingSeconds = v;
                        setSheetState(() {});
                      },
                    ),
                  ),

                const SizedBox(height: 12),
                _ButtonRow(
                  onCancel: () => Navigator.pop(ctx),
                  onConfirm: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );
        },
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          _minutes = pendingMinutes;
          _seconds = pendingSeconds;
          _minCtrl.jumpToItem(_minutes);
          _secCtrl.jumpToItem(_seconds);
          _minTCtrl.jumpToItem(_minTens);
          _minOCtrl.jumpToItem(_minOnes);
          _secTCtrl.jumpToItem(_secTens);
          _secOCtrl.jumpToItem(_secOnes);
        });
        widget.onChanged(_minutes, _seconds);
      }
      manualCtrl.dispose();
    });
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    _minTCtrl.dispose();
    _minOCtrl.dispose();
    _secTCtrl.dispose();
    _secOCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade700),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blue),
          ),
        ),
        child: Text(
          _displayText,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}

// ---- Header row (label, preview, toggle) ----

class _HeaderRow extends StatelessWidget {
  final String label;
  final String preview;
  final bool showManual;
  final VoidCallback onToggle;

  const _HeaderRow({
    required this.label,
    required this.preview,
    required this.showManual,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 14)),
        const Spacer(),
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preview,
                  style: const TextStyle(
                      color: Colors.blue,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Icon(
                  showManual ? Icons.touch_app : Icons.keyboard,
                  color: Colors.white54,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Button row ----

class _ButtonRow extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const _ButtonRow({required this.onCancel, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: onCancel,
          child:
              const Text('取消', style: TextStyle(color: Colors.white54)),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: onConfirm, child: const Text('确定')),
      ],
    );
  }
}

// ---- Two-column wheel row (original, non-split) ----

class _WheelRow extends StatelessWidget {
  final int minutes, seconds, maxMinutes;
  final FixedExtentScrollController minCtrl, secCtrl;
  final void Function(int) onMinutesChanged, onSecondsChanged;

  const _WheelRow({
    required this.minutes,
    required this.seconds,
    required this.maxMinutes,
    required this.minCtrl,
    required this.secCtrl,
    required this.onMinutesChanged,
    required this.onSecondsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildCol(ctrl: minCtrl, count: maxMinutes + 1,
              idx: minutes, label: '分', onChanged: onMinutesChanged),
        ),
        _colon,
        Expanded(
          child: _buildCol(ctrl: secCtrl, count: 60, idx: seconds,
              label: '秒', onChanged: onSecondsChanged),
        ),
      ],
    );
  }

  static Widget _buildCol({
    required FixedExtentScrollController ctrl,
    required int count,
    required int idx,
    required String label,
    required void Function(int) onChanged,
  }) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Expanded(
          child: ListWheelScrollView.useDelegate(
            controller: ctrl,
            itemExtent: 44,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (_, i) => _digitItem(i, i == idx),
              childCount: count,
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Digit-split wheel row (3-4 columns, tight per-unit spacing) ----

class _DigitWheelRow extends StatelessWidget {
  final int minutes, seconds, maxMinutes;
  final bool splitMinutes, splitSeconds;
  final int? maxTotalSeconds;
  final FixedExtentScrollController minTCtrl, minOCtrl, secTCtrl, secOCtrl;
  final void Function(int minutes, int seconds) onChanged;

  const _DigitWheelRow({
    required this.minutes,
    required this.seconds,
    required this.maxMinutes,
    required this.splitMinutes,
    required this.splitSeconds,
    this.maxTotalSeconds,
    required this.minTCtrl,
    required this.minOCtrl,
    required this.secTCtrl,
    required this.secOCtrl,
    required this.onChanged,
  });

  int get _minTens => minutes ~/ 10;
  int get _minOnes => minutes % 10;

  int get _secTens => seconds ~/ 10;
  int get _secOnes => seconds % 10;

  int _maxSecTensFor(int m) {
    if (maxTotalSeconds != null) {
      final remaining = maxTotalSeconds! - m * 60;
      if (remaining <= 0) return 0;
      return (remaining.clamp(0, 59)) ~/ 10;
    }
    return 5;
  }

  int _maxSecOnesFor(int m, int st) {
    if (maxTotalSeconds != null) {
      final remaining = maxTotalSeconds! - m * 60 - st * 10;
      if (remaining <= 0) return 0;
      return remaining.clamp(0, 9);
    }
    return 9;
  }

  void _rebuild(int m, int s) {
    final total = m * 60 + s;
    if (maxTotalSeconds != null && total > maxTotalSeconds!) {
      final t = maxTotalSeconds!;
      onChanged(t ~/ 60, t % 60);
    } else if (s >= 60) {
      onChanged(m + 1, s - 60);
    } else {
      onChanged(m, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSt = _maxSecTensFor(minutes);
    final maxSo = _maxSecOnesFor(minutes, _secTens > maxSt ? maxSt : _secTens);

    return Row(
      children: [
        // ---- Minutes ----
        if (splitMinutes)
          Expanded(
            child: _tightPair(
              left: _buildDigitCol(
                ctrl: minTCtrl,
                count: (maxMinutes ~/ 10) + 1,
                idx: _minTens,
                label: '十分',
                onChanged: (v) => _rebuild(v * 10 + _minOnes, seconds),
              ),
              right: _buildDigitCol(
                ctrl: minOCtrl,
                count: _minTens == maxMinutes ~/ 10 ? (maxMinutes % 10) + 1 : 10,
                idx: _minOnes,
                label: '分',
                onChanged: (v) => _rebuild(_minTens * 10 + v, seconds),
              ),
            ),
          )
        else
          Expanded(
            flex: 2,
            child: _WheelRow._buildCol(
              ctrl: minTCtrl,
              count: maxMinutes + 1,
              idx: minutes,
              label: '分',
              onChanged: (v) => _rebuild(v, seconds),
            ),
          ),

        _colon,

        // ---- Seconds ----
        if (splitSeconds)
          Expanded(
            child: _tightPair(
              left: _buildDigitCol(
                ctrl: secTCtrl,
                count: maxSt + 1,
                idx: _secTens > maxSt ? maxSt : _secTens,
                label: '十秒',
                onChanged: (v) {
                  _rebuild(minutes, v * 10 + (_secOnes > maxSo ? maxSo : _secOnes));
                },
              ),
              right: _buildDigitCol(
                ctrl: secOCtrl,
                count: maxSo + 1,
                idx: _secOnes > maxSo ? maxSo : _secOnes,
                label: '秒',
                onChanged: (v) => _rebuild(minutes, _secTens * 10 + v),
              ),
            ),
          )
        else
          Expanded(
            flex: 2,
            child: _WheelRow._buildCol(
              ctrl: secTCtrl,
              count: 60,
              idx: seconds,
              label: '秒',
              onChanged: (v) => _rebuild(minutes, v),
            ),
          ),
      ],
    );
  }

  /// Two digit columns tightly packed (no gap between tens and ones).
  static Widget _tightPair({
    required Widget left,
    required Widget right,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: left),
        Flexible(child: right),
      ],
    );
  }

  Widget _buildDigitCol({
    required FixedExtentScrollController ctrl,
    required int count,
    required int idx,
    required String label,
    required void Function(int) onChanged,
  }) {
    final safeIdx = idx.clamp(0, count - 1);
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Expanded(
          child: ListWheelScrollView.useDelegate(
            controller: ctrl,
            itemExtent: 44,
            diameterRatio: 1.5,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (_, i) => _digitItem(i, i == safeIdx),
              childCount: count,
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Shared helpers ----

final _colon = Padding(
  padding: const EdgeInsets.symmetric(horizontal: 4),
  child: Text(
    ':',
    style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 32),
  ),
);

Widget _digitItem(int index, bool isSelected) {
  return Center(
    child: Text(
      index.toString(),
      style: TextStyle(
        color: isSelected ? Colors.blue : Colors.white38,
        fontSize: isSelected ? 24 : 18,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    ),
  );
}

// ---- Manual keyboard input ----

class _ManualInput extends StatelessWidget {
  final TextEditingController controller;
  final void Function(int minutes, int seconds) onParsed;

  const _ManualInput({required this.controller, required this.onParsed});

  void _parse(String value) {
    final parts = value.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null && s >= 0 && s < 60) {
        onParsed(m, s);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 24),
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        ],
        decoration: InputDecoration(
          hintText: 'MM:SS',
          hintStyle: const TextStyle(color: Colors.white30),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700)),
          focusedBorder:
              const OutlineInputBorder(borderSide: BorderSide(color: Colors.blue)),
        ),
        onChanged: _parse,
      ),
    );
  }
}
