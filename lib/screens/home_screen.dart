import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/video_item.dart';
import '../models/scan_state.dart';
import '../providers/settings_provider.dart';
import '../providers/video_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/long_press_menu.dart';
import '../widgets/empty_guide.dart';

/// The main playback screen with TikTok-style vertical swipe gestures.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Swipe detection
  double _dragStartY = 0;
  double _dragStartX = 0;
  bool _isDragging = false;
  bool _controlsVisible = true;
  bool _controlsPermanent = false;
  Timer? _controlsTimer;

  // Long-press detection
  Timer? _longPressTimer;
  bool _longPressPrimed = false;

  PlayerProvider? _playerProvider;
  SettingsProvider? _settingsProvider;
  bool _isAutoPlaying = false;

  // Screen-off listening countdown
  Timer? _screenOffTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPlayback();
      _setupListeners();
    });
  }

  void _setupListeners() {
    _playerProvider = context.read<PlayerProvider>();
    _playerProvider!.addListener(_autoPlayHandler);

    _settingsProvider = context.read<SettingsProvider>();
    _settingsProvider!.addListener(_settingsHandler);
  }

  void _settingsHandler() {
    if (!mounted) return;
    final settings = _settingsProvider!;

    // Sync looping state: if either auto-play or screen-off listening is on, 
    // we DON'T loop so the video can finish and trigger the next one.
    if (_playerProvider?.current != null) {
      final shouldLoop = !settings.autoPlayEnabled && !settings.screenOffListeningEnabled;
      _playerProvider!.current!.setLooping(shouldLoop);
    }

    // Manage wake lock
    _updateWakeLock();

    // Manage screen-off countdown
    if (settings.screenOffListeningEnabled) {
      _startScreenOffTimer();
    } else {
      _cancelScreenOffTimer();
    }
  }

  void _updateWakeLock() {
    final settings = _settingsProvider;
    if (settings == null) return;

    if (settings.autoPlayEnabled) {
      // Keep screen on for auto-play
      WakelockPlus.enable();
    } else {
      // For screen-off listening or normal mode, we don't force screen on.
      // Screen-off listening specifically wants the screen to be able to go off.
      WakelockPlus.disable();
    }
  }

  void _startScreenOffTimer() {
    final settings = _settingsProvider;
    if (settings == null) return;

    _cancelScreenOffTimer();
    _remainingSeconds = settings.screenOffTimerMinutes * 60;

    _screenOffTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _remainingSeconds--;
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _onScreenOffTimerExpired();
      }
    });
  }

  void _cancelScreenOffTimer() {
    _screenOffTimer?.cancel();
    _screenOffTimer = null;
  }

  void _onScreenOffTimerExpired() {
    if (!mounted) return;
    final player = context.read<PlayerProvider>();
    player.pause();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('倒计时结束，已暂停播放'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _autoPlayHandler() {
    if (!mounted || _isAutoPlaying) return;
    
    if (_playerProvider!.isFinished) {
      final settings = context.read<SettingsProvider>();
      // Auto-play next video if either Auto-play or Screen-off listening is enabled
      if (settings.autoPlayEnabled || settings.screenOffListeningEnabled) {
        _isAutoPlaying = true;
        _swipeUp().then((_) {
          _isAutoPlaying = false;
        });
      }
    }
  }

  Future<void> _initPlayback() async {
    final settings = context.read<SettingsProvider>();
    final video = context.read<VideoProvider>();

    if (settings.hasFolders) {
      // Always scan in background to refresh the library.
      // If we have cached videos, video.scan won't set state to ScanState.scanning,
      // so the UI remains interactive and playback can start immediately.
      video.scan(settings.folderUris);
    }
  }

  Future<void> _loadCurrentVideo(
      PlayerProvider player, VideoItem? video) async {
    if (video == null) return;
    final settings = context.read<SettingsProvider>();
    try {
      await player.loadCurrent(video.uri, speed: settings.playbackSpeed);
      final shouldLoop = !settings.autoPlayEnabled && !settings.screenOffListeningEnabled;
      player.current?.setLooping(shouldLoop);

      // Preload next video for instant swipe
      _preloadNextVideo();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('无法播放: ${video.name}'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
      // P1-2: Recover by going back to previous video.
      // P1-1: If the dead URI came from forwardHistory, playNext() already
      // removed it, so the next swipe won't hit it again.
      final videoProvider = context.read<VideoProvider>();
      if (videoProvider.hasHistory) {
        videoProvider.playPrevious();
        if (videoProvider.current != null) {
          _loadCurrentVideo(player, videoProvider.current);
        }
      }
    }
  }

  void _preloadNextVideo() {
    final video = context.read<VideoProvider>();
    final player = context.read<PlayerProvider>();
    final settings = context.read<SettingsProvider>();
    final autoAdvance = settings.autoPlayEnabled || settings.screenOffListeningEnabled;
    final next = video.peekNext(autoPick: !autoAdvance);
    if (next != null) {
      player.preloadNext(next.uri, speed: settings.playbackSpeed);
    }
  }

  // ---- swipe gestures ----

  void _onVerticalDragStart(DragStartDetails d) {
    _dragStartY = d.globalPosition.dy;
    _isDragging = false;
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) {
      final dy = d.globalPosition.dy - _dragStartY;
      if (dy.abs() > 60) {
        _isDragging = true;
        if (dy < 0) {
          _swipeUp();
        } else {
          _swipeDown();
        }
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    _isDragging = false;
  }

  // ---- horizontal gestures ----

  void _onHorizontalDragStart(DragStartDetails d) {
    _dragStartX = d.globalPosition.dx;
    _isDragging = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) {
      final dx = d.globalPosition.dx - _dragStartX;
      if (dx.abs() > 60) {
        _isDragging = true;
        if (dx < 0) {
          // Swipe Left -> Permanent ON
          setState(() {
            _controlsPermanent = true;
            _controlsVisible = true;
          });
          _controlsTimer?.cancel();
          HapticFeedback.lightImpact();
        } else {
          // Swipe Right -> Permanent OFF
          setState(() {
            _controlsPermanent = false;
          });
          _showControlsBriefly();
          HapticFeedback.lightImpact();
        }
      }
    }
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    _isDragging = false;
  }

  Future<void> _swipeUp() async {
    final video = context.read<VideoProvider>();
    final player = context.read<PlayerProvider>();

    // If auto-play or screen-off listening is on, pick next; otherwise random
    final settings = context.read<SettingsProvider>();
    final autoAdvance = settings.autoPlayEnabled || settings.screenOffListeningEnabled;
    final had = video.playNext(autoPick: !autoAdvance);
    if (!had) return;

    await _loadCurrentVideo(player, video.current);
  }

  Future<void> _swipeDown() async {
    final video = context.read<VideoProvider>();
    final player = context.read<PlayerProvider>();

    if (video.hasHistory) {
      video.playPrevious();
      await _loadCurrentVideo(player, video.current);
    } else {
      // No history → re-roll random
      video.playRandom();
      await _loadCurrentVideo(player, video.current);
    }
  }

  // ---- tap ----

  void _onTap() {
    final player = context.read<PlayerProvider>();
    player.togglePlayPause();
    _showControlsBriefly();
  }

  void _showControlsBriefly() {
    if (_controlsPermanent) return;
    setState(() => _controlsVisible = true);
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_controlsPermanent) setState(() => _controlsVisible = false);
    });
  }

  // ---- long press ----

  void _onLongPressStart(LongPressStartDetails _) {
    _longPressPrimed = true;
    _longPressTimer = Timer(const Duration(milliseconds: 300), () {
      if (_longPressPrimed && mounted) {
        _showLongPressMenu();
      }
    });
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    setState(() => _longPressPrimed = false);
    _longPressTimer?.cancel();
  }

  void _onLongPressCancel() {
    setState(() => _longPressPrimed = false);
    _longPressTimer?.cancel();
  }

  void _showLongPressMenu() async {
    // Reset states immediately so gestures aren't blocked
    setState(() {
      _longPressPrimed = false;
      _isDragging = false;
    });
    _longPressTimer?.cancel();

    HapticFeedback.mediumImpact();
    final player = context.read<PlayerProvider>();
    final video = context.read<VideoProvider>();
    
    // Record state and pause
    final wasPlaying = player.isPlaying;
    player.pause();

    bool goToSettings = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LongPressMenu(
        onOpenSettings: () {
          goToSettings = true;
          Navigator.pop(context);
        },
        onDelete: () async {
          final videoToDel = video.current;
          if (videoToDel == null) return;

          // Close menu
          Navigator.pop(context);

          // Perform deletion
          final success = await video.deleteVideo(videoToDel);

          if (mounted) {
            if (success) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('文件已永久删除')),
              );
              // After deletion, video.current is nullified in provider.
              // We need to play the next available video.
              if (!video.isEmpty) {
                video.playNext(autoPick: context.read<SettingsProvider>().autoPlayEnabled);
                _loadCurrentVideo(player, video.current);
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('删除失败，请检查权限'),
                  backgroundColor: Colors.red,
                ),
              );
              player.resume();
            }
          }
        },
      ),
    );

    // If "Settings" was clicked, wait for the settings screen to close
    if (goToSettings && mounted) {
      await Navigator.pushNamed(context, '/settings');
      
      if (mounted) {
        final video = context.read<VideoProvider>();
        final player = context.read<PlayerProvider>();
        
        if (video.isEmpty) {
          // Library is now empty (e.g. all folders removed)
          await player.stopAndClear();
        } else if (player.current == null && video.totalCount > 0) {
          // New videos added, start playback
          if (video.current == null) video.playRandom();
          _loadCurrentVideo(player, video.current);
        }
      }
    }

    // Resume only after everything (menu or settings) is closed
    // ADDED: only resume if we still have videos!
    if (wasPlaying && mounted) {
      final video = context.read<VideoProvider>();
      if (!video.isEmpty) {
        player.resume();
      }
    }
  }

  void _openSettings() async {
    if (!mounted) return;
    await Navigator.pushNamed(context, '/settings');

    if (mounted) {
      final video = context.read<VideoProvider>();
      final player = context.read<PlayerProvider>();
      
      if (video.isEmpty) {
        await player.stopAndClear();
      } else if (player.current == null && video.totalCount > 0) {
        if (video.current == null) video.playRandom();
        _loadCurrentVideo(player, video.current);
      }
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer3<VideoProvider, PlayerProvider, SettingsProvider>(
          builder: (context, video, player, settings, _) {
          // Need to scan?
          if (settings.hasFolders &&
              video.scanState == ScanState.idle) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) {
              video.scan(settings.folderUris);
            });
            return _buildLoading(video);
          }

          // Scanning
          if (video.scanState == ScanState.scanning) {
            return _buildLoading(video);
          }

          // Error
          if (video.scanState == ScanState.error) {
            return _buildError(video.scanError ?? '未知错误');
          }

          // Empty — either no folders or scan returned nothing
          if (!settings.hasFolders || video.scanState == ScanState.empty) {
            // Safety: ensure player is stopped if library was cleared
            if (player.current != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                player.stopAndClear();
              });
            }
            return EmptyGuide(
              onGoToSettings: _openSettings,
            );
          }

          // We have videos — start playback if not already started
          final isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? false;
          if (isCurrentRoute && video.current != null && player.current == null) {
            // Picked a video but player not loaded yet
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (player.current == null) {
                _loadCurrentVideo(player, video.current);
              }
            });
          } else if (isCurrentRoute && video.current == null && video.totalCount > 0) {
            // Scan completed but no video picked yet
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (video.current == null) {
                video.playRandom();
                _loadCurrentVideo(
                    context.read<PlayerProvider>(), video.current);
              }
            });
          }

          // Main player
          return GestureDetector(
            onTap: _onTap,
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate:
                _longPressPrimed ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            onVerticalDragCancel: () => setState(() => _isDragging = false),
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: () => setState(() => _isDragging = false),
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onLongPressCancel: _onLongPressCancel,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (player.isInitialized && player.current != null)
                  VideoPlayerWidget(
                    controller: player.current!,
                    fileName: video.current?.name ?? '',
                    showControls: _controlsPermanent || _controlsVisible,
                    onTap: _onTap,
                    onDragStart: () => player.pause(),
                    onDragEnd: () => player.resume(),
                  )
                else
                  _buildLoading(video),
              ],
            ),
          );
        },
      ),
    ));
  }

  Widget _buildLoading(VideoProvider video) {
    final isScanning = video.scanState == ScanState.scanning;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          if (isScanning) ...[
            const SizedBox(height: 24),
            if (video.currentScanningFolder != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  '正在扫描: ${video.currentScanningFolder}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '已发现 ${video.scanningCount} 个视频',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (video.scanPercent > 0) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: video.scanPercent,
                  backgroundColor: Colors.white10,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(video.scanPercent * 100).toInt()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(color: Colors.white70)),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _initPlayback,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _playerProvider?.removeListener(_autoPlayHandler);
    _settingsProvider?.removeListener(_settingsHandler);
    _controlsTimer?.cancel();
    _longPressTimer?.cancel();
    _cancelScreenOffTimer();
    // Release wake lock on dispose
    WakelockPlus.disable();
    super.dispose();
  }
}
