import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../providers/download_settings_provider.dart';
import '../widgets/time_range_picker.dart';
import '../widgets/download_card.dart';
import '../widgets/page_tabs.dart';
import '../app.dart';

/// Download screen: URL input, time picker, download button, progress.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final _urlCtrl = TextEditingController();
  final _urlScrollCtrl = ScrollController();
  String _startTime = '10:30';
  int _duration = 10;

  @override
  void initState() {
    super.initState();
    _urlCtrl.addListener(() => setState(() {})); // toggle suffix icon
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkServer();
    });
  }

  Future<void> _checkServer() async {
    final dp = context.read<DownloadProvider>();
    await dp.checkServer();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _urlCtrl.value = TextEditingValue(
        text: data.text!,
        selection: TextSelection.collapsed(offset: data.text!.length),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_urlScrollCtrl.hasClients) {
          _urlScrollCtrl.jumpTo(_urlScrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _clearUrl() {
    _urlCtrl.clear();
  }

  Future<void> _startDownload() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _showSnack('请输入视频URL');
      return;
    }

    final dp = context.read<DownloadProvider>();
    final sp = context.read<DownloadSettingsProvider>();

    if (!dp.serverOnline) {
      final ok = await dp.checkServer();
      if (!ok) {
        _showSnack('❌ Termux 后端未运行\n请在 Termux 中启动: python server.py');
        return;
      }
    }

    final taskId = await dp.startDownload(
      url: url,
      startTime: _startTime,
      duration: _duration,
      quality: sp.defaultQuality,
      proxy: sp.proxyUrl,
      outputDir: sp.downloadDir,
    );

    if (taskId == null) {
      _showSnack('❌ 启动下载失败，请检查网络和URL');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  /// Builds the fixed control panel (URL, time, quality, proxy, button).
  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Proxy indicator + server status + settings ----
        Consumer2<DownloadSettingsProvider, DownloadProvider>(
          builder: (_, sp, dp, __) => Row(
            children: [
              Icon(
                sp.proxyEnabled ? Icons.vpn_key : Icons.vpn_key_off,
                color: sp.proxyEnabled ? Colors.green : Colors.grey,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                sp.proxyEnabled
                    ? '代理: ${sp.proxyHost}:${sp.proxyPort}'
                    : '代理: 关闭',
                style: TextStyle(
                  color: sp.proxyEnabled ? Colors.green.shade300 : Colors.grey,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              // Server status cloud icon
              if (dp.checkingServer)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                )
              else
                GestureDetector(
                  onTap: () => dp.checkServer(),
                  child: Icon(
                    dp.serverOnline ? Icons.cloud_done : Icons.cloud_off,
                    color: dp.serverOnline ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
              const SizedBox(width: 4),
              // Settings gear
              IconButton(
                icon: const Icon(Icons.settings, size: 20, color: Colors.white54),
                tooltip: '下载设置',
                onPressed: () => Navigator.pushNamed(context, '/download-settings'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---- URL Input ----
        TextField(
          controller: _urlCtrl,
          scrollController: _urlScrollCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: '视频 URL',
            hintText: '粘贴视频链接...',
            hintStyle: const TextStyle(color: Colors.white30),
            prefixIcon: const Icon(Icons.link),
            suffixIcon: _urlCtrl.text.isEmpty
                ? IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: '从剪贴板粘贴',
                    onPressed: _pasteFromClipboard,
                  )
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: '清空',
                    onPressed: _clearUrl,
                  ),
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 20),

        // ---- Time Picker ----
        TimeRangePicker(
          initialStartTime: _startTime,
          initialDuration: _duration,
          onStartTimeChanged: (v) => _startTime = v,
          onDurationChanged: (v) => _duration = v,
        ),
        const SizedBox(height: 20),

        // ---- Quality + Download dir (50/50 row) ----
        Consumer<DownloadSettingsProvider>(
          builder: (_, sp, __) {
            final border = OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade700),
            );
            const focusBorder = OutlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            );
            return Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: '画质',
                      prefixIcon: const Icon(Icons.hd),
                      enabledBorder: border,
                      focusedBorder: focusBorder,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    child: DropdownButton<String>(
                      value: sp.defaultQuality,
                      dropdownColor: Colors.grey.shade900,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      underline: const SizedBox.shrink(),
                      isDense: true,
                      isExpanded: true,
                      items: ['480p', '720p', '1080p']
                          .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) sp.setQuality(v);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final path = await FilePicker.getDirectoryPath(
                        dialogTitle: '选择下载目录',
                      );
                      if (path != null && path.isNotEmpty) {
                        sp.setDownloadDir(path);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: '下载到',
                        prefixIcon: const Icon(Icons.folder_open),
                        enabledBorder: border,
                        focusedBorder: focusBorder,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(
                        sp.downloadDir.split('/').last.isEmpty
                            ? sp.downloadDir
                            : sp.downloadDir.split('/').last,
                        style: const TextStyle(color: Colors.white60, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // ---- Download Button ----
        Consumer<DownloadProvider>(
          builder: (_, dp, __) {
            final hasActive = dp.hasActive;
            return ElevatedButton.icon(
              onPressed: hasActive ? null : _startDownload,
              icon: Icon(hasActive ? Icons.hourglass_bottom : Icons.download),
              label: Text(hasActive ? '下载进行中...' : '开始下载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey.shade800,
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.findAncestorStateOfType<MainShellState>();
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        // Page tabs — fixed at top, same position as 刷视频 page
        if (shell != null)
          Padding(
            padding: EdgeInsets.only(top: topPadding + 8, bottom: 8),
            child: Center(
              child: PageTabs(
                currentIndex: 0,
                onTabChanged: (i) => shell.switchToTab(i),
              ),
            ),
          ),
        // Scrollable content
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final dp = context.read<DownloadProvider>();
              await dp.checkServer();
              await dp.refreshTasks();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _ControlsDelegate(),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                // ---- Active Download Card ----
                Consumer<DownloadProvider>(
                  builder: (_, dp, __) {
                    final task = dp.activeTask;
                    if (task == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: DownloadCard(
                        task: task,
                        onCancel: () => dp.cancelActive(),
                      ),
                    );
                  },
                ),

                // ---- Recent Tasks ----
                Consumer<DownloadProvider>(
                  builder: (_, dp, __) {
                    final completed = dp.completedTasks;
                    if (completed.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row: title + one-click clear all
                        Row(
                          children: [
                            const Text(
                              '下载记录',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep, size: 20),
                              color: Colors.red.shade300,
                              tooltip: '清空全部记录',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    backgroundColor: Colors.grey.shade900,
                                    title: const Text('清空记录',
                                        style: TextStyle(color: Colors.white)),
                                    content: const Text('删除所有下载记录？',
                                        style: TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, false),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(c, true),
                                        child: const Text('清空',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  final messenger = ScaffoldMessenger.of(context);
                                  dp.clearAllRecords();
                                  messenger.showSnackBar(
                                    const SnackBar(content: Text('已清空全部记录')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...completed.take(5).map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: Key(t.taskId),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              color: Colors.red.shade700,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red.shade700,
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => dp.removeRecord(t.taskId),
                            child: DownloadCard(task: t),
                          ),
                        )),
                      ],
                    );
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    ),
        ),
      ],
    );
  }
}

// ---- Pinned header delegate — keeps controls fixed during scroll ----

class _ControlsDelegate extends SliverPersistentHeaderDelegate {
  static const double _kContentHeight = 340.0;

  @override
  double get minExtent => _kContentHeight + 20; // 20 = top padding

  @override
  double get maxExtent => minExtent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final state = context.findAncestorStateOfType<_DownloadScreenState>()!;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: SizedBox(
        height: _kContentHeight,
        child: state._buildControls(),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _ControlsDelegate oldDelegate) => false;
}
