import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists download-related settings (proxy, quality, server URL).
class DownloadSettingsProvider extends ChangeNotifier {
  SharedPreferences? _prefs;

  // Defaults matching the pd script
  String _proxyHost = '127.0.0.1';
  String _proxyPort = '7890';
  bool _proxyEnabled = true;
  String _defaultQuality = '720p';
  String _serverUrl = 'http://127.0.0.1:8000';
  String _downloadDir = '/sdcard/Download';
  bool _loaded = false;

  // ---- getters ----

  bool get loaded => _loaded;
  String get proxyHost => _proxyHost;
  String get proxyPort => _proxyPort;
  bool get proxyEnabled => _proxyEnabled;
  String? get proxyUrl => _proxyEnabled
      ? 'http://$_proxyHost:$_proxyPort'
      : null;
  String get defaultQuality => _defaultQuality;
  String get serverUrl => _serverUrl;
  String get downloadDir => _downloadDir;

  static const _kProxyHost = 'proxy_host';
  static const _kProxyPort = 'proxy_port';
  static const _kProxyEnabled = 'proxy_enabled';
  static const _kQuality = 'default_quality';
  static const _kServerUrl = 'server_url';
  static const _kDownloadDir = 'download_dir';

  // ---- lifecycle ----

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _proxyHost = _prefs?.getString(_kProxyHost) ?? '127.0.0.1';
    _proxyPort = _prefs?.getString(_kProxyPort) ?? '7890';
    _proxyEnabled = _prefs?.getBool(_kProxyEnabled) ?? true;
    _defaultQuality = _prefs?.getString(_kQuality) ?? '720p';
    _serverUrl = _prefs?.getString(_kServerUrl) ?? 'http://127.0.0.1:8000';
    _downloadDir = _prefs?.getString(_kDownloadDir) ?? '/sdcard/Download';
    _loaded = true;
    notifyListeners();
  }

  // ---- setters ----

  Future<void> setProxy(String host, String port) async {
    _proxyHost = host;
    _proxyPort = port;
    await _prefs?.setString(_kProxyHost, host);
    await _prefs?.setString(_kProxyPort, port);
    notifyListeners();
  }

  Future<void> setProxyEnabled(bool enabled) async {
    _proxyEnabled = enabled;
    await _prefs?.setBool(_kProxyEnabled, enabled);
    notifyListeners();
  }

  Future<void> setQuality(String quality) async {
    _defaultQuality = quality;
    await _prefs?.setString(_kQuality, quality);
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    await _prefs?.setString(_kServerUrl, url);
    notifyListeners();
  }

  Future<void> setDownloadDir(String path) async {
    _downloadDir = path;
    await _prefs?.setString(_kDownloadDir, path);
    notifyListeners();
  }
}
