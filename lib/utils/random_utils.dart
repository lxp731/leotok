import 'dart:collection';
import 'dart:math';

import '../models/video_item.dart';

/// Picks a random video while avoiding recently-played items.
///
/// Maintains a rolling window of the last [windowSize] URIs.
/// When all candidates are exhausted (e.g. library is smaller
/// than the window), the queue is flushed and a new cycle begins.
class RandomPicker {
  final int windowSize;
  final Queue<String> _recent = Queue<String>();
  final Random _rng = Random();

  RandomPicker({this.windowSize = 20});

  /// Returns a random [VideoItem] from [pool] that is not in the recent window.
  VideoItem pick(List<VideoItem> pool) {
    if (pool.isEmpty) throw StateError('Cannot pick from empty pool');

    var candidates = pool.where((v) => !_recent.contains(v.uri)).toList();
    if (candidates.isEmpty) {
      _recent.clear();
      candidates = pool;
    }

    final picked = candidates[_rng.nextInt(candidates.length)];
    _recent.add(picked.uri);
    while (_recent.length > windowSize) {
      _recent.removeFirst();
    }
    return picked;
  }

  /// Check if a URI is in the recent queue.
  bool contains(String uri) => _recent.contains(uri);

  /// Remove a URI from the recent queue (useful if a video is deleted).
  void forget(String uri) {
    _recent.remove(uri);
  }

  void clear() => _recent.clear();
}
