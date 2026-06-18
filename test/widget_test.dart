import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leotok/app.dart';
import 'package:leotok/providers/settings_provider.dart';
import 'package:leotok/providers/video_provider.dart';
import 'package:leotok/providers/player_provider.dart';
import 'package:leotok/providers/download_settings_provider.dart';
import 'package:leotok/providers/download_provider.dart';
import 'package:leotok/services/storage_service.dart';
import 'package:leotok/services/file_scanner.dart';
import 'package:leotok/services/api_service.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final storage = StorageService();
    await storage.init();
    final scanner = FileScanner();

    final settings = SettingsProvider(storage);
    final video = VideoProvider(scanner, storage);
    final downloadSettings = DownloadSettingsProvider();
    await downloadSettings.load();
    final downloader = DownloadProvider(ApiService());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: video),
          ChangeNotifierProvider(create: (_) => PlayerProvider()),
          ChangeNotifierProvider.value(value: downloadSettings),
          ChangeNotifierProvider.value(value: downloader),
        ],
        child: const MaterialApp(
          home: LeoTokApp(),
        ),
      ),
    );

    // Let the first frame render (don't wait for animations to settle
    // because providers kick off async work that won't complete in tests).
    await tester.pump();
    expect(find.byType(LeoTokApp), findsOneWidget);
  });
}
