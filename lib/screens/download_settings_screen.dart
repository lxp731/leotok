import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_settings_provider.dart';
import '../providers/download_provider.dart';
import '../services/api_service.dart';

/// Download settings: proxy config, default quality, server URL.
class DownloadSettingsScreen extends StatefulWidget {
  const DownloadSettingsScreen({super.key});

  @override
  State<DownloadSettingsScreen> createState() => _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState extends State<DownloadSettingsScreen> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _serverCtrl;

  @override
  void initState() {
    super.initState();
    final sp = context.read<DownloadSettingsProvider>();
    _hostCtrl = TextEditingController(text: sp.proxyHost);
    _portCtrl = TextEditingController(text: sp.proxyPort);
    _serverCtrl = TextEditingController(text: sp.serverUrl);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('⚙️ 下载设置'),
        backgroundColor: Colors.black,
      ),
      body: Consumer2<DownloadSettingsProvider, DownloadProvider>(
        builder: (_, sp, dp, __) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---- Proxy ----
            const _SectionHeader('🌐 代理设置'),
            SwitchListTile(
              title: const Text('启用代理',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                sp.proxyEnabled
                    ? 'http://${sp.proxyHost}:${sp.proxyPort}'
                    : '不使用代理',
                style: const TextStyle(color: Colors.white54),
              ),
              value: sp.proxyEnabled,
              onChanged: (v) => sp.setProxyEnabled(v),
              activeTrackColor: Colors.blue,
            ),
            if (sp.proxyEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _hostCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: '主机',
                        hintText: '127.0.0.1',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) => sp.setProxy(v, _portCtrl.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '端口',
                        hintText: '7890',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) => sp.setProxy(_hostCtrl.text, v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final api = ApiService(baseUrl: sp.serverUrl);
                  final ok = await api.testProxy(sp.proxyUrl!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? '✅ 代理可用' : '❌ 代理不可达'),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.wifi_find),
                label: const Text('测试代理'),
              ),
            ],
            const SizedBox(height: 24),

            // ---- Default Quality ----
            const _SectionHeader('📺 默认画质'),
            ...['480p', '720p', '1080p'].map((q) => ListTile(
                  title: Text(q, style: const TextStyle(color: Colors.white)),
                  leading: Radio<String>(
                    value: q,
                    groupValue: sp.defaultQuality,
                    onChanged: (v) {
                      if (v != null) sp.setQuality(v);
                    },
                    fillColor: WidgetStateProperty.all(Colors.blue),
                  ),
                  onTap: () => sp.setQuality(q),
                )),
            const SizedBox(height: 24),

            // ---- Server URL ----
            const _SectionHeader('🖥️ 后端服务器'),
            TextField(
              controller: _serverCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: '服务器 URL',
                hintText: 'http://127.0.0.1:8000',
                border: OutlineInputBorder(),
                helperText: 'Termux 中运行的 Python 后端地址',
                helperStyle: TextStyle(color: Colors.white30),
              ),
              onSubmitted: (v) {
                final url = v.trim();
                if (url.isEmpty) return;
                sp.setServerUrl(url);
                // Apply immediately — the running ApiService keeps its
                // startup URL otherwise, so this setting was a no-op until
                // the next app launch.
                dp.updateServerUrl(url);
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await dp.checkServer();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(dp.serverOnline ? '✅ 服务在线' : '❌ 无法连接'),
                      backgroundColor: dp.serverOnline ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.cloud),
              label: const Text('测试连接'),
            ),
            const SizedBox(height: 24),

            // ---- About ----
            const _SectionHeader('ℹ️ 关于'),
            const ListTile(
              title: Text('视频下载器', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                '基于 yt-dlp + Termux 后端\n前后端均在手机上运行',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
