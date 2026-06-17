import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/download_screen.dart';
import 'screens/download_settings_screen.dart';
import 'screens/download_gallery_screen.dart';
import 'screens/player_screen.dart';
import 'providers/player_provider.dart';

/// Root widget: configures the dark theme and routing.
class LeoTokApp extends StatelessWidget {
  const LeoTokApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Force immersive dark mode
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'LeoTok',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.white,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const MainShell(),
        '/settings': (_) => const SettingsScreen(),
        '/download-settings': (_) => const DownloadSettingsScreen(),
        '/download-gallery': (_) => const DownloadGalleryScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/player') {
          final taskId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => PlayerScreen(taskId: taskId),
          );
        }
        return null;
      },
    );
  }
}

/// 2-tab shell with PageView. Screens access [MainShellState] to read the
/// current tab index and trigger switches.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  int currentIndex = 0;
  final pageController = PageController();

  void switchToTab(int index) {
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    // In landscape + video tab: lock PageView (horizontal swipe controls overlay)
    final hideChrome = isLandscape && currentIndex == 1;

    return Scaffold(
      body: PageView(
        controller: pageController,
        physics: hideChrome
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        onPageChanged: (i) {
          // Pause video when switching away from 刷视频 tab
          if (i == 0) {
            context.read<PlayerProvider>().pause();
          }
          setState(() => currentIndex = i);
        },
        children: const [
          DownloadScreen(),
          HomeScreen(),
        ],
      ),
    );
  }
}
