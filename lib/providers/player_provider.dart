import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../services/audio_background_service.dart';

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

    // If a preload for this URI is still in flight, wait for it and adopt
    // the result instead of racing it with a fresh controller (which would
    // leak the preloaded one and double-initialize the same source).
    final inFlight = _preloadInFlight[uri];
    if (inFlight != null) {
      try {
        final preloaded = await inFlight.timeout(const Duration(seconds: 10));
        if (preloaded != null) {
          _nextController = preloaded;
          _preloadedUri = uri;
        }
      } catch (_) {
        // Preload timed out or failed — fall through to _getOrCreate.
      }
    }

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
    if (_preloadedUri == uri && _nextController?.value.isInitialized == true) {
      return _nextController; // already ready
    }
    // A preload for this URI is already running — share its future instead
    // of creating a second controller (which would leak the first and
    // double-initialize the same native resource).
    final inFlight = _preloadInFlight[uri];
    if (inFlight != null) return inFlight;

    final future = _doPreload(uri, speed: speed);
    _preloadInFlight[uri] = future;
    try {
      return await future;
    } finally {
      if (identical(_preloadInFlight[uri], future)) {
        _preloadInFlight.remove(uri);
      }
    }
  }

  /// Actual preload work. Never called twice concurrently for the same URI
  /// (guarded by [_preloadInFlight]).
  Future<VideoPlayerController?> _doPreload(String uri,
      {double speed = 1.0}) async {
    final cached = _controllerCache[uri];
    if (cached != null) {
      // Fully initialized — just promote it.
      if (cached.value.isInitialized) {
        _nextController = cached;
        _preloadedUri = uri;
        return _nextController;
      }
      // Cached but initializing (e.g. created by loadCurrent) — wait for
      // it and adopt it. Do NOT call initialize() again here: video_player
      // creates a fresh platform player per initialize() call.
      return _finishPreload(cached, uri, speed);
    }

    final controller = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllerCache[uri] = controller;
    // Set _nextController BEFORE _trimCache so the in-progress controller
    // is considered "active" and won't be disposed while initializing.
    _nextController = controller;
    _trimCache();
    return _finishPreload(controller, uri, speed);
  }

  Future<VideoPlayerController?> _finishPreload(
      VideoPlayerController controller, String uri, double speed) async {
    try {
      // Timeout guard: if this controller gets disposed while initializing
      // (e.g. by stopAndClear), video_player's initialize() future may never
      // complete. Don't let the in-flight entry block loadCurrent forever.
      await controller.initialize().timeout(const Duration(seconds: 10));
      // If loadCurrent claimed this controller while we were initializing,
      // skip the preload-side setup — the current path owns its state now
      // and pausing it here would stop playback.
      if (_currentController == controller) return controller;
      await controller.setPlaybackSpeed(speed);
      await controller.setLooping(true);
      await controller.pause(); // paused, ready to play on swap
      if (_currentController != controller) {
        // Mark as ready for loadCurrent consumption.
        _nextController = controller;
        _preloadedUri = uri;
      }
      return controller;
    } catch (e) {
      debugPrint('Preload failed for $uri: $e');
      if (_currentController != controller) {
        if (identical(_controllerCache[uri], controller)) {
          _controllerCache.remove(uri);
        }
        if (_nextController == controller) _nextController = null;
        if (_preloadedUri == uri) _preloadedUri = null;
        controller.dispose();
      }
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
      // Keep the native wake lock in sync with actual playback: it must
      // only be held while audio is really playing (screen-off mode).
      if (wasPlaying != _isPlaying) {
        AudioBackgroundService.setPlaying(_isPlaying);
      }
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
    AudioBackgroundService.setPlaying(false);

    for (final c in _controllerCache.values) {
      await c.pause();
      await c.dispose();
    }
    _controllerCache.clear();
    _currentController = null;
    _prevController = null;
    _nextController = null;
    _preloadedUri = null;
    // In-flight preloads are left running; their continuations see
    // _currentController == null and safely skip promotion/cleanup.
    _preloadInFlight.clear();
    _isPlaying = false;
    _isInitialized = false;
    _isFinished = false;
    notifyListeners();
  }

  /// Internal handle for cancellation
  /// Tracks preloads that are still initializing, so concurrent
  /// [preloadNext] / [loadCurrent] calls for the same URI share one
  /// controller instead of leaking duplicates.
  final Map<String, Future<VideoPlayerController?>> _preloadInFlight = {};

  final Map<String, VideoPlayerController> _controllerCache = {};

  VideoPlayerController _getOrCreate(String uri) {
    final cached = _controllerCache[uri];
    if (cached != null) {
      // Only reuse if fully initialized.  Otherwise (e.g. a previous load
      // errored) create a fresh one and dispose the stale entry so its
      // native resources are freed.
      if (cached.value.isInitialized) {
        return cached;
      }
      _controllerCache.remove(uri);
      if (!identical(cached, _currentController) &&
          !identical(cached, _nextController) &&
          !identical(cached, _prevController)) {
        cached.dispose();
      }
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
    AudioBackgroundService.setPlaying(false);
    for (final c in _controllerCache.values) {
      c.dispose();
    }
    _controllerCache.clear();
    super.dispose();
  }
}
