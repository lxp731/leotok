# LeoTok Web — 功能设计文档

> 状态：设计阶段 | 基于 Android v1.1.0 已实现功能分析

---

## 一、与 Android 端的差异分析

### 1.1 平台约束变化

| 维度 | Android | Web |
|------|---------|-----|
| 后端运行位置 | Termux（手机本地） | 远程服务器 / VPS |
| 文件来源 | SAF 本地文件夹 | URL 下载 + 本地上传 |
| 存储 API | SharedPreferences | localStorage（自动） |
| 网络 | localhost | HTTPS 远程 API |
| 屏幕常亮 | WakelockPlus | Wake Lock API (navigator.wakeLock) |
| 后台音频 | ForegroundService | 浏览器标签页后台音频 |
| 原生调用 | MethodChannel | 不可用 |
| 系统集成 | android_intent_plus | 不可用 |
| 代理 | 用户自配 HTTP 代理 | 浏览器自动处理 |
| 下载目录 | /sdcard/Download | 浏览器默认下载目录 |
| 平台插件 | permission_handler | `web` 兼容层（无操作） |

### 1.2 可保留功能

| 功能 | 保留 | 说明 |
|------|------|------|
| Provider 状态管理 | ✅ 全部 | 平台无关，完全复用 |
| 所有数据模型 | ✅ 全部 | DownloadTask, VideoItem, ScanState |
| 暗色主题 | ✅ 全部 | 适配任意屏幕 |
| PageTabs 导航 | ✅ 保留 | 顶部文字 Tab |
| 下载页 UI | ✅ 全部 | URL 输入、时间选择、画质、进度 |
| WheelTimePicker | ✅ 全部 | 滚轮/键盘时间选择，手势一致 |
| ProgressBar | ✅ 全部 | 点击跳转、拖动精度、时间预览 |
| DownloadCard | ✅ 保留 | 下载进度卡片 |
| 下载设置 | ✅ 部分 | 服务器 URL、画质（去掉代理） |
| 视频播放器 | ✅ 保留 | Flutter video_player 支持 Web |

### 1.3 需改造功能

| 功能 | Android 实现 | Web 改造方案 |
|------|-------------|-------------|
| 视频来源 | SAF 文件夹扫描 | URL 下载 + 拖放上传 |
| 后端通信 | localhost:8000 | 配置远程服务器 URL |
| 下载进度 | HTTP 轮询 (500ms) | **WebSocket 实时推送** |
| 屏幕常亮 | wakelock_plus | **Wake Lock API** (navigator.wakeLock) |
| 文件管理器 | android_intent_plus | 浏览器下载，无需额外操作 |
| 代理设置 | 用户配置 HTTP 代理 | **去掉**，浏览器自行处理 |

### 1.4 不必要功能

| 功能 | 原因 |
|------|------|
| SAF 文件夹扫描 | Web 无文件系统访问权限 |
| FileScanner (MethodChannel) | Web 无原生通道 |
| AudioBackgroundService | Web 标签页即可后台播放 |
| StorageService | 用 SharedPreferences Web 适配层替代 |
| 代理配置 UI | 浏览器自带代理 |
| permission_handler | Web 权限模型不同 |
| android_intent_plus | 纯 Android 插件 |
| 熄屏听剧 | Web 无"熄屏"概念，改为"后台播放" |
| Termux 部署脚本 | 远程服务器部署 |

---

## 二、Web 架构设计

### 2.1 整体架构

```
┌──────────────────────────────────────────────────┐
│                  Flutter Web App                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
│  │  下载页面   │  │  刷视频页面  │  │  设置页面   │  │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  │
│        │               │               │         │
│  ┌─────┴───────────────┴───────────────┴──────┐  │
│  │              Provider 层 (复用)              │  │
│  │  DownloadProvider | VideoProvider | Player  │  │
│  └──────────────────────┬──────────────────────┘  │
│                         │                         │
│              ┌──────────┴──────────┐              │
│              │    ApiService        │              │
│              │  (Dio, 可配置 URL)   │              │
│              └──────────┬──────────┘              │
└─────────────────────────┼─────────────────────────┘
                          │ HTTPS + WebSocket
                          ▼
┌──────────────────────────────────────────────────┐
│              远程服务器 (VPS / Vercel)              │
│  ┌────────────────────────────────────────────┐  │
│  │           Python FastAPI 后端               │  │
│  │  /api/health  /api/download  /api/tasks    │  │
│  │  /ws/progress/:taskId    (🆕 WebSocket)    │  │
│  └───────────────────┬────────────────────────┘  │
│                      │                            │
│              yt-dlp CLI (子进程)                   │
│                      │                            │
│              输出到服务器临时目录                    │
│              → 完成后提供直链下载                   │
└──────────────────────────────────────────────────┘
```

### 2.2 视频来源模型重构

Web 端不再有"文件夹扫描"概念，改为统一的 `VideoSource`：

```dart
sealed class VideoSource {
  // 下载完成的本地文件（URL 或 base64 blob）
  final String id;
  final String name;
  final Duration? duration;
}

class DownloadedVideo extends VideoSource {
  final String downloadUrl;  // 服务器直链
  final int sizeBytes;
}

class UploadedVideo extends VideoSource {
  final Uint8List? thumbnailBytes;
}
```

`VideoProvider` 改为管理 `VideoSource` 列表，扫描逻辑替换为从后端任务列表 + localStorage 缓存恢复。

### 2.3 路由设计

| 路由 | 页面 | 说明 |
|------|------|------|
| `/` | MainShell | 双 Tab（下载 + 刷视频） |
| `/settings` | SettingsScreen | Web 设置（服务器 URL、画质） |
| `/download-settings` | DownloadSettingsScreen | 下载设置（精简版，无代理） |
| `/download-gallery` | DownloadGalleryScreen | 已下载列表 |
| `/player` | PlayerScreen | 独立播放器 |

与 Android 端路由完全一致，降低维护成本。

---

## 三、需新增/改造的功能

### 3.1 WebSocket 进度推送（替代轮询）

**现状（Android）**：Flutter 每 500ms HTTP GET `/api/tasks/:id` 轮询。

**Web 改造**：后端新增 WebSocket 端点 `/ws/progress/:taskId`，下载线程每收到新进度就 `ws.send(json)`。Flutter 端：

```dart
class DownloadProvider {
  WebSocketChannel? _wsChannel;

  void _startPolling(String taskId) {
    _wsChannel = WebSocketChannel.connect(
      Uri.parse('${_api.wsBaseUrl}/ws/progress/$taskId'),
    );
    _wsChannel!.stream.listen((data) {
      final json = jsonDecode(data);
      _tasks[taskId] = DownloadTask.fromJson(json);
      if (!json['isActive']) _wsChannel?.sink.close();
      notifyListeners();
    });
  }
}
```

**优势**：零延迟、零冗余请求、服务器推送即到达。

### 3.2 Wake Lock API（替代 WakelockPlus）

```dart
// lib/services/wake_lock_service.dart (Web)
import 'dart:html' if (dart.library.io) 'dart:io';

class WakeLockService {
  static Future<void> enable() async {
    // 仅浏览器环境
    try {
      await html.window.navigator.wakeLock?.request('screen');
    } catch (_) {}
  }
}
```

自动播放开启时调用 `WakeLockService.enable()`。

### 3.3 拖放上传

下载页支持拖放本地视频文件到页面区域，自动提取元数据后加入视频库：

```dart
// 在 MainShell 或 DownloadScreen 外层包裹
DragTarget<File>(
  onAcceptWithDetails: (details) {
    // 读取文件 → 存入 VideoProvider
  },
  child: ...
)
```

### 3.4 布局

始终使用与 Android 端一致的 **PageView + PageTabs 导航栏** 切换页面，桌面端也不使用双栏布局。宽屏时内容区域居中并限制最大宽度，保持阅读体验。

### 3.5 键盘快捷键（桌面端）

| 快捷键 | 功能 |
|--------|------|
| `Space` | 播放/暂停 |
| `↑` / `↓` | 音量增减 |
| `←` / `→` | 快退/快进 5 秒 |
| `F` | 全屏 |
| `M` | 静音 |
| `N` | 下一个视频 |

---

## 四、后端改造

### 4.1 新增端点

| 方法 | 路径 | 说明 |
|------|------|------|
| WebSocket | `/ws/progress/{task_id}` | 实时推送下载进度（替代轮询） |
| GET | `/api/videos/{id}/download` | 触发浏览器下载（Content-Disposition） |
| POST | `/api/upload` | 接收上传的视频文件 |

### 4.2 部署方案

| 方案 | 适用场景 |
|------|---------|
| VPS + systemd | 自有服务器，直接运行 FastAPI |
| Vercel + Serverless | 轻量部署（需适配，yt-dlp 有冷启动延迟） |
| Docker + Fly.io | 容器化部署，yt-dlp 预装镜像 |

推荐 VPS 方案：最少的适配工作，FastAPI 直接部署，yt-dlp 和 ffmpeg 预装。

### 4.3 安全考量（🆕 Web 独有）

| 措施 | 说明 |
|------|------|
| API 鉴权 | 简单的 token 认证（环境变量配置） |
| 下载限流 | 单 IP 同时最多 N 个下载任务 |
| 临时文件清理 | 定时清理超过 24 小时的下载文件 |
| CORS 白名单 | 仅允许前端部署域名 |

---

## 五、文件结构变更

```
leotok/
├── lib/
│   ├── main.dart                          # 🔧 去掉 Android 专属依赖
│   ├── app.dart                           # ✅ 复用（去掉 Android 专有逻辑）
│   ├── models/
│   │   ├── video_source.dart              # 🆕 Web 视频来源模型
│   │   └── download_task.dart             # ✅ 复用
│   ├── providers/
│   │   ├── download_provider.dart         # 🔧 轮询 → WebSocket
│   │   ├── download_settings_provider.dart # 🔧 去掉代理字段
│   │   ├── player_provider.dart           # ✅ 复用
│   │   └── video_provider.dart            # 🔧 扫描 → 任务列表
│   ├── screens/
│   │   ├── home_screen.dart               # 🔧 去掉 Android 专属手势逻辑（横屏等）
│   │   ├── download_screen.dart           # 🔧 新增拖放上传
│   │   └── ...
│   ├── services/
│   │   ├── api_service.dart               # 🔧 新增 WebSocket 支持
│   │   └── wake_lock_service.dart         # 🆕 Web Wake Lock
│   └── widgets/
│       ├── page_tabs.dart                 # ✅ 复用
│       ├── progress_bar.dart              # ✅ 复用
│       ├── wheel_time_picker.dart         # ✅ 复用
│       └── ...
├── backend/
│   ├── server.py                          # 🔧 新增 /ws + /download + /upload
│   ├── downloader.py                      # ✅ 复用
│   └── requirements.txt                   # 🔧 新增 websockets 依赖
├── web/                                   # 🆕 Flutter Web 入口
│   └── index.html
└── Android.md                             # 📝 Android 端功能文档
```

---

## 六、实施阶段

### 阶段 1：共享代码提取（零破坏）

1. 将 Android 端 `_AppLifecycleWrapper`、SAF 扫描、MethodChannel 等用条件导入隔离（`if (dart.library.io)`）
2. Flutter Web 编译通过，UI 渲染正常

### 阶段 2：后端 Web 化

1. 新增 WebSocket 端点
2. 新增文件下载/上传端点
3. 部署到 VPS 并验证

### 阶段 3：Web 功能实现

1. WebSocket 进度推送替代轮询
2. 拖放上传
3. Wake Lock API
4. 键盘快捷键

### 阶段 4：优化与上线

1. PWA 支持（Service Worker 离线缓存）
2. API 鉴权 + 安全加固
3. 性能测试（大文件下载、多并发）

---

## 七、功能对比矩阵

| 功能 | Android | Web |
|------|---------|-----|
| 上下滑切视频 | ✅ | ✅ |
| 点击播放/暂停 | ✅ | ✅ |
| 长按菜单 | ✅ | ✅ |
| 进度条增强（点击/精度/预览） | ✅ | ✅ |
| PageTabs 导航 | ✅ | ✅ |
| URL 输入下载 | ✅ | ✅ |
| 时间范围选择 | ✅ | ✅ |
| 完整视频下载 | ✅ | ✅ |
| 画质选择 | ✅ | ✅ |
| 下载进度实时显示 | ✅ 轮询 | ✅ WebSocket |
| 下载记录管理 | ✅ | ✅ |
| 服务器连接检测 | ✅ | ✅ |
| 本地文件夹扫描 | ✅ SAF | ❌ 改为 URL/上传 |
| 横屏沉浸 | ✅ | 自适应 |
| 自动播放 | ✅ | ✅ |
| 屏幕常亮 | ✅ WakelockPlus | ✅ Wake Lock API |
| 熄屏听剧 | ✅ | ❌ 改为后台播放 |
| 代理配置 | ✅ | ❌ |
| 打开文件管理器 | ✅ | ❌ |
| 视频删除 | ✅ | ✅ |
| 视频预加载 | ✅ | ✅ |
| 暗色主题 | ✅ | ✅ |
| 拖放上传 | ❌ | 🆕 |
| 键盘快捷键 | ❌ | 🆕 |
| PWA 离线支持 | ❌ | 🆕 |
