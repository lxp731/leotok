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

  // ---- lifecycle ----

  /// Set a new current video.
  Future<void> loadCurrent(String uri, {double speed = 1.0}) async {
    final oldController = _currentController;
    _isFinished = false;

    // Swap in preloaded next controller if URI matches
    final bool usingPreloaded = (uri == _preloadedUri);
    final newController = usingPreloaded
        ? _nextController!
        : _getOrCreate(uri);

    _preloadedUri = null;

    // Promote preloaded → current, demote current → prev
    if (usingPreloaded) {
      _prevController = oldController;
      _nextController = null;
    } else if (oldController != null && oldController != newController) {
      oldController.removeListener(_onListener);
      oldController.pause();
    }

    _currentController = newController;

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
        _currentController!.setLooping(true);
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
  Future<void> preloadNext(String uri, {double speed = 1.0}) async {
    if (_preloadedUri == uri) return; // already preloading this URI
    if (_controllerCache.containsKey(uri)) {
      _nextController = _controllerCache[uri];
      _preloadedUri = uri;
      return;
    }

    final controller = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllerCache[uri] = controller;
    _nextController = controller;
    _preloadedUri = uri;

    _trimCache();

    try {
      await controller.initialize();
      await controller.setPlaybackSpeed(speed);
      controller.setLooping(true);
      controller.pause(); // paused, ready to play on swap
    } catch (e) {
      debugPrint('Preload failed for $uri: $e');
      _controllerCache.remove(uri);
      if (_nextController == controller) {
        _nextController = null;
        _preloadedUri = null;
      }
      controller.dispose();
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
      return _controllerCache[uri]!;
    }
    final c = VideoPlayerController.contentUri(
      Uri.parse(uri),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controllerCache[uri] = c;
    _trimCache();
    return c;
  }

  void _trimCache() {
    while (_controllerCache.length > 3) {
      final oldest = _controllerCache.keys.first;
      final controller = _controllerCache.remove(oldest);
      if (controller != _currentController &&
          controller != _prevController &&
          controller != _nextController) {
        controller?.dispose();
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
