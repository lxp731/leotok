import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app.dart';
import 'providers/player_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/video_provider.dart';
import 'providers/download_settings_provider.dart';
import 'providers/download_provider.dart';
import 'services/file_scanner.dart';
import 'services/storage_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init services
  final storage = StorageService();
  await storage.init();
  final scanner = FileScanner();

  // Build providers
  final settings = SettingsProvider(storage);
  final video = VideoProvider(scanner, storage);

  // Download module
  final downloadSettings = DownloadSettingsProvider();
  await downloadSettings.load();
  final api = ApiService(baseUrl: downloadSettings.serverUrl);
  final downloader = DownloadProvider(api);
  // Check server status on startup (non-blocking)
  downloader.checkServer();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: video),
        ChangeNotifierProvider(create: (_) => PlayerProvider()),
        ChangeNotifierProvider.value(value: downloadSettings),
        ChangeNotifierProvider.value(value: downloader),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.paused) {
      // Always pause when leaving the app. User must manually resume.
      context.read<PlayerProvider>().pause();
    } else if (state == AppLifecycleState.resumed) {
      // Re-apply wake lock in case the system released it while backgrounded.
      // Some OEM ROMs clear wake locks when the app goes to background.
      if (context.read<SettingsProvider>().autoPlayEnabled) {
        WakelockPlus.enable();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
