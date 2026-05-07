import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_item.dart';

/// Thin wrapper around SharedPreferences for LeoTok settings.
/// Video metadata cache is stored as a JSON file (not SharedPreferences)
/// to avoid the performance penalty of large StringList reads on cold start.
///
/// Keys managed:
/// - `folder_uris`                : comma-separated SAF tree URIs
/// - `auto_play_enabled`          : bool
/// - `screen_off_listening`       : bool
/// - `screen_off_timer_minutes`   : int (1-30)
/// - `playback_speed`             : double (1.0, 1.5, 2.0)
class StorageService {
  static const _keyFolders = 'folder_uris';
  static const _keyAutoPlay = 'auto_play_enabled';
  static const _keyScreenOffListening = 'screen_off_listening';
  static const _keyScreenOffTimerMinutes = 'screen_off_timer_minutes';
  static const _keySpeed = 'playback_speed';
  static const _keyVideoCache = 'video_cache'; // legacy key for migration
  static const _cacheFileName = 'video_cache.json';

  late final SharedPreferences _prefs;
  String? _cacheFilePath;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationDocumentsDirectory();
    _cacheFilePath = '${dir.path}/$_cacheFileName';
  }

  // ---- folder URIs ----

  List<String> getFolderUris() {
    return _prefs.getStringList(_keyFolders) ?? [];
  }

  Future<bool> addFolderUri(String uri) async {
    final list = getFolderUris();
    if (list.contains(uri)) return false;
    list.add(uri);
    return _prefs.setStringList(_keyFolders, list);
  }

  Future<bool> removeFolderUri(String uri) async {
    final list = getFolderUris();
    list.remove(uri);
    return _prefs.setStringList(_keyFolders, list);
  }

  // ---- auto-play ----

  bool getAutoPlayEnabled() => _prefs.getBool(_keyAutoPlay) ?? false;

  Future<bool> setAutoPlayEnabled(bool value) =>
      _prefs.setBool(_keyAutoPlay, value);

  // ---- screen-off listening ----

  bool getScreenOffListeningEnabled() =>
      _prefs.getBool(_keyScreenOffListening) ?? false;

  Future<bool> setScreenOffListeningEnabled(bool value) =>
      _prefs.setBool(_keyScreenOffListening, value);

  // ---- screen-off timer ----

  int getScreenOffTimerMinutes() =>
      _prefs.getInt(_keyScreenOffTimerMinutes) ?? 15;

  Future<bool> setScreenOffTimerMinutes(int minutes) =>
      _prefs.setInt(_keyScreenOffTimerMinutes, minutes.clamp(1, 30));

  // ---- playback speed ----

  double getPlaybackSpeed() => _prefs.getDouble(_keySpeed) ?? 1.0;

  Future<bool> setPlaybackSpeed(double speed) =>
      _prefs.setDouble(_keySpeed, speed);

  // ---- video cache (JSON file) ----

  Future<List<VideoItem>> getCachedVideos() async {
    final path = _cacheFilePath;
    if (path == null) return [];

    try {
      final file = File(path);
      if (!await file.exists()) {
        return _migrateFromSharedPrefs();
      }
      final json = await file.readAsString();
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => VideoItem.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Failed to read video cache: $e');
      return [];
    }
  }

  Future<void> setCachedVideos(List<VideoItem> videos) async {
    final path = _cacheFilePath;
    if (path == null) return;

    try {
      final file = File(path);
      final json = jsonEncode(videos.map((v) => v.toMap()).toList());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('Failed to write video cache: $e');
    }
  }

  /// One-time migration: read old SharedPreferences StringList cache,
  /// write it to the JSON file, then clear the legacy key.
  Future<List<VideoItem>> _migrateFromSharedPrefs() async {
    final legacy = _prefs.getStringList(_keyVideoCache);
    if (legacy == null || legacy.isEmpty) return [];

    final videos = legacy.map((s) {
      try {
        return VideoItem.fromMap(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<VideoItem>().toList();

    if (videos.isNotEmpty) {
      await setCachedVideos(videos);
    }
    await _prefs.remove(_keyVideoCache);
    return videos;
  }
}
