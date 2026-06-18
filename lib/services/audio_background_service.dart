import 'package:flutter/services.dart';

/// Controls the Android foreground service that keeps audio playing
/// when the screen is off (screen-off listening mode).
class AudioBackgroundService {
  static const _channel = MethodChannel('com.localtok.local_tok/background_audio');

  /// Start the foreground notification service.
  /// Required for keeping audio alive when screen turns off.
  static Future<void> start() async {
    try {
      await _channel.invokeMethod('startBackgroundService');
    } catch (e) {
      // Ignore — fails gracefully on non-Android or if service unavailable
    }
  }

  /// Stop the foreground notification service.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopBackgroundService');
    } catch (e) {
      // Ignore
    }
  }
}
