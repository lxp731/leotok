import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'providers/player_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/video_provider.dart';
import 'services/file_scanner.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init services
  final storage = StorageService();
  await storage.init();
  final scanner = FileScanner();

  // Build providers
  final settings = SettingsProvider(storage);
  final video = VideoProvider(scanner, storage);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: video),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
      ],
      child: const _AppLifecycleWrapper(child: LeoTokApp()),
    ),
  );
}

/// Listens to app lifecycle events to pause/resume playback.
class _AppLifecycleWrapper extends StatefulWidget {
  final Widget child;
  const _AppLifecycleWrapper({required this.child});

  @override
  State<_AppLifecycleWrapper> createState() => _AppLifecycleWrapperState();
}

class _AppLifecycleWrapperState extends State<_AppLifecycleWrapper>
    with WidgetsBindingObserver {
  bool _wasPlayingBeforeBackground = false;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    final player = context.read<PlayerProvider>();
    final settings = context.read<SettingsProvider>();

    if (state == AppLifecycleState.paused) {
      _resumeTimer?.cancel();
      if (settings.screenOffListeningEnabled) {
        // Some Android devices automatically pause video players when the
        // activity is backgrounded or the screen turns off. We attempt to
        // override this by forcing a resume after a short delay.
        _resumeTimer = Timer(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          final currentSettings = context.read<SettingsProvider>();
          final currentPlayer = context.read<PlayerProvider>();
          if (currentSettings.screenOffListeningEnabled &&
              currentPlayer.current != null &&
              !currentPlayer.isPlaying) {
            currentPlayer.resume();
          }
        });
      } else {
        _wasPlayingBeforeBackground = player.isPlaying;
        player.pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      _resumeTimer?.cancel();
      if (settings.autoPlayEnabled) {
        WakelockPlus.enable();
      }

      if (!settings.screenOffListeningEnabled && _wasPlayingBeforeBackground) {
        player.resume();
        _wasPlayingBeforeBackground = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
