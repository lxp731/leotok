import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/video_provider.dart';
import '../models/scan_state.dart';

/// Settings screen: manage folder paths, auto-play, refresh.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer2<SettingsProvider, VideoProvider>(
        builder: (context, settings, video, _) {
          final isScanning = video.scanState == ScanState.scanning;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              if (video.scanError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[900]?.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[900]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          video.scanError!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              
              // ---- Section: Folders ----
              const _SectionHeader(title: '已添加的文件夹'),
              if (settings.folderUris.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '还没有添加文件夹',
                    style: TextStyle(color: Colors.white38, fontSize: 14),
                  ),
                )
              else
                ...settings.folderUris.map(
                  (uri) => _FolderRow(
                    uri: uri,
                    onDelete: isScanning ? null : () => _confirmDelete(context, uri),
                  ),
                ),

              const SizedBox(height: 12),
              _AddFolderButton(onAdd: isScanning ? null : () => _addFolder(context)),

              const SizedBox(height: 12),
              if (settings.folderUris.isNotEmpty)
                Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isScanning ? null : () => _refreshScan(context),
                      icon: isScanning 
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))
                        : const Icon(Icons.refresh, size: 18),
                      label: Text(isScanning ? '正在索引...' : '刷新视频索引'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: isScanning ? Colors.white38 : Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (isScanning) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: video.scanPercent > 0 ? video.scanPercent : null,
                        backgroundColor: Colors.white10,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已发现 ${video.scanningCount} 个视频 ${video.currentScanningFolder != null ? "\n正在处理: ${video.currentScanningFolder}" : ""}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ]
                  ],
                ),

              const SizedBox(height: 32),

              // ---- Section: Playback ----
              const _SectionHeader(title: '播放设置'),
              SwitchListTile(
                value: settings.autoPlayEnabled,
                activeTrackColor: Colors.white38,
                activeThumbColor: Colors.white,
                title: const Text(
                  '自动播放',
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                subtitle: const Text(
                  '播放完毕后自动切换到下一个视频',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => settings.setAutoPlayEnabled(v),
              ),

              const SizedBox(height: 32),

              // ---- Section: About ----
              const _SectionHeader(title: '关于'),
              ListTile(
                title: const Text('LeoTok',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text('版本 ${settings.appVersion}',
                    style: TextStyle(color: Colors.white38)),
                leading: const Icon(Icons.info_outline, color: Colors.white38),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    final scanner = context.read<VideoProvider>().scanner;
    final result = await scanner.pickAndScan();
    if (result == null) return; // user cancelled

    if (!context.mounted) return;
    final settings = context.read<SettingsProvider>();
    final ok = await settings.addFolder(result.treeUri);

    if (!context.mounted) return;
    if (ok) {
      final video = context.read<VideoProvider>();
      // Add scanned files directly — avoids a re-scan.
      video.addScannedFiles(result.files);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件夹添加成功'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该文件夹已添加')),
      );
    }
  }

  void _confirmDelete(BuildContext context, String uri) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('移除文件夹', style: TextStyle(color: Colors.white)),
        content: const Text(
          '该文件夹中的视频将不再出现在应用中。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteFolder(context, uri);
            },
            child: const Text('移除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(BuildContext context, String uri) {
    final settings = context.read<SettingsProvider>();
    final video = context.read<VideoProvider>();
    settings.removeFolder(uri);
    video.removeByFolder(uri);
  }

  Future<void> _refreshScan(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    await context.read<VideoProvider>().scan(settings.folderUris);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String uri;
  final VoidCallback? onDelete;

  const _FolderRow({required this.uri, required this.onDelete});

  String _formatUri(String uriString) {
    try {
      // 1. Decode percent-encoded characters
      final decoded = Uri.decodeFull(uriString);

      // 2. Handle SAF identifiers (primary: -> /)
      if (decoded.contains(':')) {
        String relativePath = decoded.split(':').last;
        if (!relativePath.startsWith('/')) {
          relativePath = '/$relativePath';
        }
        return relativePath;
      }
      return decoded;
    } catch (e) {
      return uriString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayLabel = _formatUri(uri);
    final display = displayLabel.length > 50
        ? '...${displayLabel.substring(displayLabel.length - 47)}'
        : displayLabel;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              display,
              style: TextStyle(
                  color: onDelete == null ? Colors.white24 : Colors.white70,
                  fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close,
                color: onDelete == null ? Colors.transparent : Colors.white38,
                size: 18),
          ),
        ],
      ),
    );
  }
}

class _AddFolderButton extends StatelessWidget {
  final VoidCallback? onAdd;
  const _AddFolderButton({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('添加文件夹'),
      style: OutlinedButton.styleFrom(
        foregroundColor: onAdd == null ? Colors.white24 : Colors.white70,
        side: BorderSide(color: onAdd == null ? Colors.white10 : Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
