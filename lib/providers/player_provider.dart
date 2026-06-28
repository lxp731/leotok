import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Manages the active VideoPlayerController pool.
///
/// Maintains up to 3 controllers (prev / current / next) to avoid
/// black frames during swipe transitions.
class PlayerProvider extends ChangeNotifier {
  VideoPlayerController? _currentController;
  VideoPlayerController? _prevController;
  VideoPlayerController? _nextController;
  String? _preloadedUri;

  bool _isPlaying = false;
  bool _isInitialized = false;

  // ---- getters ----

  VideoPlayerController? get current => _currentController;
  VideoPlayerController? get prev => _prevController;
  VideoPlayerController? get next => _nextController;
  bool get isPlaying => _isPlaying;
  bool get isInitialized => _isInitialized;

  /// When true, the periodic keep-alive timer in HomeScreen is allowed to
  /// resume playback after an external (system-level) pause.  Set only when
  /// the app is backgrounded while actively playing with screen-off listening
  /// enabled.  Cleared on user-initiated pause, timer expiry, or feature off.
  bool _audioKeepAlive = false;
  bool get audioKeepAlive => _audioKeepAlive;
  void enableAudioKeepAlive() => _audioKeepAlive = true;
  void disableAudioKeepAlive() => _audioKeepAlive = false;

  // ---- lifecycle ----

  /// Set a new current video.
  Future<void> loadCurrent(String uri, {double speed = 1.0}) async {
    final oldController = _currentController;
    _isFinished = false;

    // Only use the preloaded controller if it has actually finished initializing.
    // _preloadedUri is now set only after preloadNext's initialize() succeeds,
    // so this check is a belt-and-suspenders safety against the race.
    final bool usingPreloaded = uri == _preloadedUri &&
        _nextController != null &&
        _nextController!.value.isInitialized;
    final newController = usingPreloaded
        ? _nextController!
        : _getOrCreate(uri);

    _preloadedUri = null;

    // Promote preloaded → current, demote current → prev
    if (usingPreloaded) {
      oldController?.removeListener(_onListener);
      oldController?.pause();
      _prevController = oldController;
      _nextController = null;
    } else if (oldController != null && oldController != newController) {
      oldController.removeListener(_onListener);
      oldController.pause();
      // Don't clear _nextController — it may be protecting an in-progress
      // preload from being disposed by _trimCache.  It will be overwritten
      // by the next _preloadNextVideo call, and loadCurrent guards against
      // using an uninitialized controller via the isInitialized check.
    }

    _currentController = newController;

    // Safe to trim now — the new controller is protected as _currentController.
    _trimCache();

    _currentController!.removeListener(_onListener);
    _currentController!.addListener(_onListener);

    _isInitialized = _currentController!.value.isInitialized;
    _isPlaying = _currentController!.value.isPlaying;
    notifyListeners();

    if (!_isInitialized) {
      try {
        await _currentController!.initialize();
        _isInitialized = true;
        await _currentController!.play();
        await _currentController!.setLooping(true);
        await _currentController!.setPlaybackSpeed(speed);
        notifyListeners();
      } catch (e) {
        debugPrint('Failed to initialize video: $uri — $e');
        rethrow;
      }
    } else {
      await _currentController!.setPlaybackSpeed(speed);
      if (!_currentController!.value.isPlaying) {
        await _currentController!.play();
      }
      notifyListeners();
    }
  }

  /// Pre-initialize the next video controller in background.
  /// Should be called after [loadCurrent] succeeds so the next swipe
  /// can swap instantly without a black frame.
  ///
  /// Returns the initialized controller on success, or null on failure.
  /// The controller is only promoted to [_nextController] / [_preloadedUri]
  /// **after** initialization completes, avoiding the race where
  /// [loadCurrent] picks up a controller that is still initializing.
  Future<VideoPlayerController?> preloadNext(String uri,
      {double speed = 1.0}) async {
    if (_preloadedUri == uri) return _nextController; // already ready
    if (_controllerCache.containsKey(uri)) {
      final cached = _controllerCache[uri];
      // Only promote to _nextController if the cached controller is fully
      // initialized. Otherwise we'd advertise an uninitialized controller
      // as ready, and loadCurrent's isInitialized guard would reject it.
      if (cached!.value.isInitialized) {
        _nextController = cached;
        _preloadedUri = uri;
        return _nextController;
      }
      // Still initializing — fall through and wait for it, or create fresh.
    }

    final controller = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllerCache[uri] = controller;
    // Set _nextController BEFORE _trimCache so the in-progress controller
    // is considered "active" and won't be disposed while initializing.
    // loadCurrent's isInitialized guard will still reject it until ready.
    _nextController = controller;
    _trimCache();

    try {
      await controller.initialize();
      await controller.setPlaybackSpeed(speed);
      await controller.setLooping(true);
      await controller.pause(); // paused, ready to play on swap

      // Mark as ready for loadCurrent consumption.
      _preloadedUri = uri;
      return controller;
    } catch (e) {
      debugPrint('Preload failed for $uri: $e');
      _controllerCache.remove(uri);
      _nextController = null;
      _preloadedUri = null;
      controller.dispose();
      return null;
    }
  }

  void _onListener() {
    if (_currentController == null) return;

    final value = _currentController!.value;

    final wasPlaying = _isPlaying;
    _isPlaying = value.isPlaying;

    final isAtEnd = _isInitialized &&
        !value.isLooping &&
        value.position >= (value.duration - const Duration(milliseconds: 50)) &&
        value.duration > Duration.zero;

    if (isAtEnd && !value.isPlaying) {
      _isFinished = true;
    } else {
      _isFinished = false;
    }

    if (wasPlaying != _isPlaying || _isFinished) {
      notifyListeners();
    }
  }

  bool _isFinished = false;
  bool get isFinished => _isFinished;

  // ---- playback controls ----

  Future<void> togglePlayPause() async {
    if (_currentController == null || !_isInitialized) return;
    if (_currentController!.value.isPlaying) {
      await _currentController!.pause();
    } else {
      await _currentController!.play();
    }
  }

  Future<void> pause() async {
    if (_currentController == null) return;
    await _currentController!.pause();
  }

  Future<void> resume() async {
    if (_currentController == null) return;
    await _currentController!.play();
  }

  Future<void> setSpeed(double speed) async {
    await _currentController?.setPlaybackSpeed(speed);
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    await _currentController?.seekTo(position);
  }

  Future<void> stopAndClear() async {
    _currentController?.removeListener(_onListener);
    await _currentController?.pause();

    for (final c in _controllerCache.values) {
      await c.pause();
      await c.dispose();
    }
    _controllerCache.clear();
    _currentController = null;
    _prevController = null;
    _nextController = null;
    _preloadedUri = null;
    _isPlaying = false;
    _isInitialized = false;
    _isFinished = false;
    notifyListeners();
  }

  // ---- internal pool ----

  final Map<String, VideoPlayerController> _controllerCache = {};

  VideoPlayerController _getOrCreate(String uri) {
    if (_controllerCache.containsKey(uri)) {
      final cached = _controllerCache[uri]!;
      // Only reuse if fully initialized.  Otherwise (e.g. a preload is
      // still in progress) calling initialize() on it again would cause
      // "VideoPlayerController used after being disposed".
      if (cached.value.isInitialized) {
        return cached;
      }
      // Cached but uninitialized — remove and create fresh to avoid
      // double-initialize collision with the in-progress preload.
      _controllerCache.remove(uri);
    }
    final c = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllerCache[uri] = c;
    // Don't trim here — the caller (loadCurrent / preloadNext) will trim
    // after protecting the new controller via _currentController or
    // _nextController.  Trimming now could dispose this very controller.
    return c;
  }

  void _trimCache() {
    while (_controllerCache.length > 3) {
      // Find a non-active entry to evict, starting from the oldest.
      String? toEvict;
      for (final key in _controllerCache.keys) {
        final c = _controllerCache[key];
        if (c != _currentController &&
            c != _prevController &&
            c != _nextController) {
          toEvict = key;
          break;
        }
      }
      if (toEvict != null) {
        final evicted = _controllerCache.remove(toEvict);
        evicted?.removeListener(_onListener); // prevent "used after disposed" error
        evicted?.dispose();
      } else {
        // All cached controllers are active — can't trim further.
        break;
      }
    }
  }

  // ---- cleanup ----

  @override
  void dispose() {
    _currentController?.removeListener(_onListener);
    for (final c in _controllerCache.values) {
      c.dispose();
    }
    _controllerCache.clear();
    super.dispose();
  }
}
