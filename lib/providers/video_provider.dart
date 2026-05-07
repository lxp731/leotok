import 'package:flutter/foundation.dart';

import '../models/video_item.dart';
import '../models/scan_state.dart';
import '../services/file_scanner.dart';
import '../services/storage_service.dart';
import '../utils/random_utils.dart';

/// Manages the video library: scanning, lazy loading, playback history.
class VideoProvider extends ChangeNotifier {
  final FileScanner _scanner;
  final StorageService _storage;
  FileScanner get scanner => _scanner;
  final RandomPicker _picker = RandomPicker(windowSize: 20);

  List<VideoItem> _allVideos = [];
  final List<VideoItem> _backwardHistory = []; // stack: previously watched (for going back)
  final List<VideoItem> _forwardHistory = [];  // stack: popped from backward (for going forward)
  static const int _maxHistory = 20;
  VideoItem? _current;
  ScanState _scanState = ScanState.idle;
  String? _scanError;
  int _scanningCount = 0;
  String? _currentScanningFolder;
  double _scanPercent = 0.0;

  VideoProvider(this._scanner, this._storage) {
    _loadFromCache();
    _setupProgress();
  }

  Future<void> _loadFromCache() async {
    final cached = await _storage.getCachedVideos();
    if (cached.isNotEmpty) {
      _allVideos = cached;
      _scanState = ScanState.done;
      notifyListeners();
    }
  }

  void _setupProgress() {
    _scanner.onProgress = (count, folder) {
      _scanningCount = count;
      if (folder != null) _currentScanningFolder = folder;
      notifyListeners();
    };
  }

  // ---- getters ----

  List<VideoItem> get allVideos => List.unmodifiable(_allVideos);
  VideoItem? get current => _current;
  bool get hasHistory => _backwardHistory.isNotEmpty;
  int get totalCount => _allVideos.length;
  ScanState get scanState => _scanState;
  String? get scanError => _scanError;
  bool get isEmpty => _allVideos.isEmpty;
  int get scanningCount => _scanningCount;
  String? get currentScanningFolder => _currentScanningFolder;
  double get scanPercent => _scanPercent;

  // ---- scanning ----

  /// Directly insert already-scanned files (from pickAndScan).
  void addScannedFiles(List<VideoItem> files) {
    _allVideos.addAll(files);
    _allVideos.shuffle(); // Shuffle to ensure global random even on first add
    _scanState = _allVideos.isEmpty ? ScanState.empty : ScanState.done;
    _storage.setCachedVideos(_allVideos);
    _picker.clear();
    notifyListeners();
  }

  /// Scans all configured folders. Call this manually (refresh).
  Future<void> scan(List<String> folderUris) async {
    if (folderUris.isEmpty) return;
    // If we have videos, don't show "scanning" state to avoid blocking UI with a loader
    if (_allVideos.isEmpty) {
      _scanState = ScanState.scanning;
    }
    _scanError = null;
    _scanningCount = 0;
    _scanPercent = 0.0;
    _currentScanningFolder = '准备中...';
    notifyListeners();

    try {
      final oldMap = {for (var v in _allVideos) v.uri: v};
      final results = <VideoItem>[];
      bool somePermissionsLost = false;

      for (int i = 0; i < folderUris.length; i++) {
        _scanPercent = i / folderUris.length;
        notifyListeners();
        
        try {
          final videos = await _scanner.scan(folderUris[i]);
          for (var v in videos) {
            // Incremental sync: reuse duration if file hasn't changed
            final old = oldMap[v.uri];
            if (old != null && old.lastModified == v.lastModified) {
              v.duration = old.duration;
            }
          }
          results.addAll(videos);
        } catch (e) {
          if (e.toString().contains('PERMISSION_LOST')) {
            somePermissionsLost = true;
          } else {
            rethrow;
          }
        }
      }

      _allVideos = results;
      _allVideos.shuffle(); // Shuffle globally to break directory-based ordering
      
      _scanState = results.isEmpty ? ScanState.empty : ScanState.done;
      _scanPercent = 1.0;
      _currentScanningFolder = null;
      _scanningCount = 0;
      _storage.setCachedVideos(_allVideos);

      // Reset picker and history since the library has changed significantly
      _picker.clear();
      _backwardHistory.clear();
      _forwardHistory.clear();

      if (somePermissionsLost) {
        _scanError = '部分文件夹权限已失效，请重新添加。';
        // We don't set ScanState.error here because we might still have other videos to show
      }
    } catch (e) {
      if (_allVideos.isEmpty) {
        _scanError = e.toString();
        _scanState = ScanState.error;
      }
    }
    notifyListeners();
  }

  // ---- playback navigation ----

  /// Peek at what the next video would be without modifying state.
  /// Returns null if library is empty or no next candidate is available.
  VideoItem? peekNext({bool autoPick = false}) {
    if (_allVideos.isEmpty) return null;

    if (_forwardHistory.isNotEmpty) return _forwardHistory.last;

    if (autoPick) {
      final candidates = _allVideos.where((v) => !_picker.contains(v.uri)).toList();
      if (candidates.isEmpty) return _allVideos.first;
      candidates.shuffle();
      return candidates.first;
    }

    if (_current == null) return _allVideos.first;
    final idx = _allVideos.indexOf(_current!);
    if (idx < 0) return _allVideos.first;
    return _allVideos[(idx + 1) % _allVideos.length];
  }

  /// Pick a random video and set it as current.
  /// Returns `true` if a video was picked, `false` if library is empty.
  bool playRandom() {
    if (_allVideos.isEmpty) return false;
    final next = _picker.pick(_allVideos);
    if (_current != null) {
      _addToBackwardHistory(_current!);
    }
    _forwardHistory.clear(); // user took a new path, discard forward history
    _current = next;
    notifyListeners();
    return true;
  }

  /// Move to the next video.
  /// First checks forward history (when going back up after going down),
  /// then falls back to picking the next video.
  /// If [autoPick] is true, picks randomly; otherwise picks sequential.
  bool playNext({bool autoPick = false}) {
    if (_allVideos.isEmpty) return false;

    // Check forward history first (user swiped up after swiping down)
    if (_forwardHistory.isNotEmpty) {
      if (_current != null) {
        _addToBackwardHistory(_current!);
      }
      _current = _forwardHistory.removeLast();
      notifyListeners();
      return true;
    }

    VideoItem next;
    if (autoPick) {
      next = _picker.pick(_allVideos);
    } else {
      final idx = _allVideos.indexOf(_current!);
      final nextIdx = (idx + 1) % _allVideos.length;
      next = _allVideos[nextIdx];
    }
    if (_current != null) {
      _addToBackwardHistory(_current!);
    }
    _current = next;
    notifyListeners();
    return true;
  }

  /// Go back to the previous video from history.
  /// Returns `null` if backward history is empty.
  VideoItem? playPrevious() {
    if (_backwardHistory.isEmpty) return null;
    // Push current to forward history first
    if (_current != null) {
      _addToForwardHistory(_current!);
    }
    _current = _backwardHistory.removeLast();
    notifyListeners();
    return _current;
  }

  /// Add a video to backward history, respecting max size.
  void _addToBackwardHistory(VideoItem video) {
    _backwardHistory.add(video);
    while (_backwardHistory.length > _maxHistory) {
      _backwardHistory.removeAt(0);
    }
  }

  /// Add a video to forward history, respecting max size.
  void _addToForwardHistory(VideoItem video) {
    _forwardHistory.add(video);
    while (_forwardHistory.length > _maxHistory) {
      _forwardHistory.removeAt(0);
    }
  }

  /// Reset state: clear history, current, picker; play a random new video.
  bool resetAndPlayRandom() {
    _backwardHistory.clear();
    _forwardHistory.clear();
    _picker.clear();
    _current = null;
    return playRandom();
  }

  /// Remove a video from the library (if its folder was removed).
  void removeByFolder(String folderUri) {
    _allVideos.removeWhere((v) => v.folder == folderUri);
    _backwardHistory.removeWhere((v) => v.folder == folderUri);
    _forwardHistory.removeWhere((v) => v.folder == folderUri);
    _picker.forget(folderUri);
    if (_current != null && _current!.folder == folderUri) {
      _current = null;
    }
    _scanState = _allVideos.isEmpty ? ScanState.empty : ScanState.done;
    notifyListeners();
  }

  /// Permanently delete a video from disk and the library.
  Future<bool> deleteVideo(VideoItem video) async {
    try {
      final bool? success = await _scanner.deleteFile(video.uri);
      if (success == true) {
        _allVideos.removeWhere((v) => v.uri == video.uri);
        _backwardHistory.removeWhere((v) => v.uri == video.uri);
        _forwardHistory.removeWhere((v) => v.uri == video.uri);
        _picker.forget(video.uri);
        _storage.setCachedVideos(_allVideos);
        if (_current?.uri == video.uri) {
          _current = null;
        }
        _scanState = _allVideos.isEmpty ? ScanState.empty : ScanState.done;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Delete failed: $e');
      return false;
    }
  }
}
