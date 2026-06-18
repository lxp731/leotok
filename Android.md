# LeoTok 功能清单

> 最后更新：2026-06-18

---

## 一、项目概述

LeoTok 是一款 Android 本地视频播放与下载一体化应用。采用 Flutter 构建前端，Python FastAPI 作为下载后端（运行在 Termux 中），通过 Provider 进行状态管理，严格遵循 Android SAF（存储访问框架）规范。

**技术栈**：Flutter (Dart) + Provider + Python FastAPI + yt-dlp + Termux
**最低支持**：Android API 26
**包名**：com.localtok.local_tok

---

## 二、架构设计

### 2.1 导航结构

```
MainShell (PageView)
├── Tab 0：下载页  (DownloadScreen)
└── Tab 1：刷视频页 (HomeScreen)
```

- **PageTabs**：TikTok 风格纯文字导航（`下载 | 刷视频`），嵌入两个页面内容顶部，横屏时隐藏
- **切换方式**：点击 Tab / 左右滑动手势（竖屏）
- **横屏**：PageView physics 锁定为 `NeverScrollableScrollPhysics`，Tab 完全隐藏

### 2.2 状态管理层级

```
MultiProvider
├── SettingsProvider          (播放设置：文件夹、自动播放、熄屏听剧、播放速度)
├── VideoProvider             (视频库：扫描、播放队列、历史、随机)
├── PlayerProvider            (播放控制：加载、播放/暂停、倍速、预加载)
├── DownloadSettingsProvider  (下载设置：代理、画质、服务器URL、下载目录)
└── DownloadProvider          (下载任务：启动、轮询、取消、删除记录)
```

### 2.3 通信架构

```
Flutter App ──HTTP localhost:8000──▶ Termux Python FastAPI
                                        │
                                   yt-dlp CLI (subprocess)
                                        │
                                   /sdcard/Download/ (共享存储)
```

---

## 三、刷视频功能

### 3.1 手势交互

| 手势 | 竖屏行为 | 横屏行为 |
|------|---------|---------|
| 上下滑动 | 切换视频（下一个/上一个） | 同竖屏 |
| 左右滑动 | 切换 Tab（PageView） | 显示/锁定控件 |
| 点击 | 播放/暂停 | 同竖屏 |
| 长按 (500ms) | 弹出功能菜单 | 同竖屏 |
| 左滑（横屏） | — | 控件永久显示 |
| 右滑（横屏） | — | 控件恢复自动隐藏 |

### 3.2 长按菜单

- 触发时间：通过 `LongPressGestureRecognizer(duration: 500ms)` 控制
- 菜单项：
  - **删除此视频**：永久删除磁盘文件 + 后台刷新视频索引
  - **设置**：跳转到播放设置页面

### 3.3 删除视频

- 删除后自动调用 `VideoProvider.scan()` 刷新索引
- 删除后尝试播放下一个可用视频
- 若为最后一个视频，保持空状态
- 删除失败时恢复播放

### 3.4 进度条功能

| 功能 | 实现 |
|------|------|
| 点击跳转 | `onTapDown` → 计算水平位置比例 → `seekTo()` |
| 拖动跳转 | `onHorizontalDragUpdate` → 实时更新位置 |
| 拖动精度 | 手指垂直偏移超过 30px 时，scrub 灵敏度降低（最多可精确到 0.1×） |
| 时间预览 | 拖动时在进度条上方显示当前位置时间浮层 |
| 时间显示 | 左下角已播放时间，右下角剩余时间（负号格式） |

### 3.5 控件显隐

- **竖屏**：进度条、文件名、播放状态图标**始终显示**
- **横屏**：
  - 进入横屏 3 秒后自动隐藏
  - 点击屏幕 → 显示 3 秒后再次隐藏
  - 左滑 → 永久显示（锁定）
  - 右滑 → 取消锁定，3 秒后隐藏

### 3.6 生命周期

| 事件 | 行为 |
|------|------|
| 切到下载 Tab | 自动暂停视频 |
| 切回刷视频 Tab | 保持暂停，等待手动播放 |
| App 进入后台 | 自动暂停 |
| App 回到前台 | 保持暂停，不做任何操作 |
| 横竖屏切换 | 横屏时隐藏导航栏+锁定 PageView |

### 3.7 设置项

| 设置 | 默认值 | 说明 |
|------|--------|------|
| 已添加文件夹 | 空 | SAF DocumentTree URI 列表 |
| 自动播放 | 关闭 | 播完自动切下一个（与熄屏听剧互斥） |
| 熄屏听剧 | 关闭 | 锁屏/后台继续播放音频（与自动播放互斥） |
| 熄屏计时器 | 15 分钟 | 到达时间后自动暂停 |
| 播放速度 | 1.0× | 0.5× ~ 2.0× |
| 刷新视频索引 | — | 增量扫描，按文件夹检测变化 |

### 3.8 视频扫描

- 使用 `DocumentsContract` API 高性能查询
- 缓存扫描结果（SharedPreferences + JSON）
- 增量扫描：仅处理修改时间变化的文件夹
- 进度实时反馈（当前文件夹、已发现视频数、百分比）
- 支持预加载下一个视频（双缓冲播放池）

### 3.9 播放控制器池 (PlayerProvider)

- 最多维护 3 个 `VideoPlayerController`：前一个、当前、下一个
- URI → Controller 映射缓存，LRU 修剪（优先保留当前/前后）
- `loadCurrent(uri)`：优先复用已预加载的 controller，避免重新初始化的黑屏
- `preloadNext(uri)`：后台初始化下一个视频的 controller
- `isFinished` 检测：位置距末尾 50ms 容差 + 非循环模式

### 3.10 视频库 (VideoProvider)

- **历史栈**：`_backwardHistory` / `_forwardHistory`（各最多 20 条），支持双向回退
- **随机去重**：`RandomPicker`（windowSize=20），最近 20 个视频不会立即重复
- 视频列表随机打乱（打破文件夹目录顺序）
- 增量同步：未修改的文件复用缓存时长信息
- 删除视频后同步清理缓存、历史、随机选择器
- 缓存文件：`video_cache.json`，支持从旧版 SharedPreferences 自动迁移

### 3.11 长按菜单详细项

| 菜单项 | 行为 |
|--------|------|
| 自动播放 | 开关切换（与熄屏听剧互斥） |
| 熄屏听剧 | 开关切换，开启后展开倒计时选择（5/10/15/20/25/30 分钟） |
| 播放速度 | 1× / 1.5× / 2× 三档 |
| 删除此视频 | SAF 永久删除 → 刷新索引 |
| 设置 | 跳转到设置页 |

---

## 四、下载功能

### 4.1 下载页面布局

```
┌──────────────────────────────┐
│     下载  │  刷视频           │  ← PageTabs（固定顶部）
├──────────────────────────────┤
│ 🔑 代理: 关闭     ☁️🟢  ⚙️    │  ← 代理行（左：状态，右：云朵+齿轮）
│ 🔗 [URL 输入框]        [📋] │  ← 支持粘贴、清空
│ ⏱ 开始时间  │ 耗时           │  ← 滚轮选择器
│ 📺 画质 ▼   │ 📁 下载到      │  ← 画质下拉 + 目录选择
│ [══════ 开始下载 ══════]     │  ← 下载按钮
├──────────────────────────────┤
│ ⏳ 下载中... 45%             │  ← 激活下载卡片
│ ████████░░░░░░░░░░           │
│ 速度 2.3MB/s · ETA 15s      │
│ [取消]                       │
├──────────────────────────────┤
│ 下载记录              [🗑️]   │  ← 历史记录（最多 5 条）
│ ✅ 下载完成 - video.mp4      │
│ 2.3 MB                       │
└──────────────────────────────┘
```

### 4.2 下载参数

| 参数 | 格式 | 默认值 | 说明 |
|------|------|--------|------|
| URL | 文本 | 空 | 支持粘贴 |
| 开始时间 | MM:SS（滚轮） | 10:30 | 0:00 ~ 59:59 |
| 耗时 | 秒（滚轮） | 10 | 0 ~ 360 秒；设为 0 = 下载完整视频 |
| 画质 | 480p/720p/1080p | 720p | 持久化 |
| 下载到 | 目录路径 | /sdcard/Download | FilePicker 选择 |
| 代理 | host:port | 127.0.0.1:7890 | 可开关 |

### 4.3 完整视频下载

- 条件：开始时间 = `00:00`，耗时 = `0`
- 行为：yt-dlp 不传 `--download-sections`，下载视频全部内容
- 文件名：`<title>.<ext>`（不带时间范围后缀）

### 4.4 下载流程

1. 用户填写参数 → 点击"开始下载"
2. Flutter POST `/api/download`
3. FastAPI 创建 DownloadTask，在线程池中调用 yt-dlp
4. Flutter 每 500ms 轮询 `GET /api/tasks/:id` 获取进度
5. 进度实时显示：百分比、速度（如 `2.3MiB/s`）、ETA
6. 完成后显示文件大小，卡片变绿色
7. 失败/取消显示对应状态

### 4.5 下载记录管理

| 操作 | 行为 | 是否删文件 |
|------|------|-----------|
| 滑删记录 | 移除本地记录 | ❌ 不动文件 |
| 清空全部 | 移除所有记录 | ❌ 不动文件 |
| 点击完成卡片 | 打开系统文件管理器 | — |

### 4.6 下载设置

| 设置 | 默认值 | 说明 |
|------|--------|------|
| 代理开关 | 开启 | 全局代理 |
| 代理主机 | 127.0.0.1 | — |
| 代理端口 | 7890 | — |
| 测试代理 | — | 通过后端请求 google.com 验证 |
| 默认画质 | 720p | 480p/720p/1080p |
| 服务器 URL | http://127.0.0.1:8000 | 后端地址 |
| 测试连接 | — | 调用 /api/health |

### 4.7 服务器状态

- 应用启动时自动检测（非阻塞）
- 下载页代理行右侧云朵图标：
  - 🟢 `cloud_done` → 在线
  - 🔴 `cloud_off` → 离线
  - 🟠 loading → 检测中
- 点击云朵图标可手动重新检测
- 下拉刷新也会触发检测

---

## 五、后端 API

### 5.1 端点列表

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/health | 健康检查，返回 yt-dlp 版本和输出目录 |
| POST | /api/download | 发起下载（非阻塞，立即返回 task） |
| GET | /api/tasks | 列出所有任务（最近优先） |
| GET | /api/tasks/{id} | 获取单个任务状态（轮询用） |
| DELETE | /api/tasks/{id} | 取消运行中的下载 |
| DELETE | /api/videos/{id} | 删除已完成下载（文件 + 记录） |
| GET | /api/videos/{id}/file | 流式传输视频文件 |
| POST | /api/proxy/test | 测试代理连通性 |

### 5.2 请求/响应格式

**POST /api/download**
```json
{
  "url": "https://...",
  "start_time": "01:30",
  "duration": 10,
  "quality": "720p",
  "proxy": "http://127.0.0.1:7890",
  "output_dir": "/sdcard/Download"
}
```

**任务状态字段**
```json
{
  "task_id": "abc123",
  "url": "...",
  "start_time": "01:30",
  "duration": 10,
  "quality": "720p",
  "status": "downloading|done|failed|cancelled",
  "progress": 45.2,
  "speed": "2.3MiB/s",
  "eta": "00:15",
  "filename": "video_0130-0140.mp4",
  "filepath": "/sdcard/Download/video_0130-0140.mp4",
  "filesize": "5.2 MB",
  "error": null,
  "created_at": "2024-01-01T00:00:00"
}
```

### 5.3 下载引擎

- 使用 yt-dlp CLI（子进程），保证与 bash 脚本行为完全一致
- 格式选择：优先非 HLS MP4 分片 → 回退 m3u8 → 回退合并流
  ```
  bv[height=720][ext=mp4]+ba[ext=m4a]/
  bv[height=720][ext=mp4][protocol=m3u8]+ba[ext=m4a][protocol=m3u8]/
  b[height=720][ext=mp4]
  ```
- 进度解析：支持 yt-dlp 原生 `[download] XX.X%` 和 ffmpeg `out_time=` 两种格式
- 取消支持：`SIGTERM` → `os.killpg()` 进程组终止
- 线程安全：`ThreadPoolExecutor(max_workers=2)` 执行同步下载

### 5.4 部署（Termux）

```bash
# 首次部署
cd ~/leotok/backend
./setup.sh

# 服务控制
./start_server.sh start|stop|restart|status
```

- Python 3.13 + uv 包管理
- pydantic-core 预编译 ARM64 wheel（避免 Termux 上编译 Rust）
- PID 文件管理，启动验证，优雅关闭
- 输出目录：`~/storage/downloads`

---

## 六、UI/UX 设计

### 6.1 主题

- 全局暗色主题（`Brightness.dark`）
- 主背景：`Colors.black`
- 导航栏/底部栏：`Color(0xFF0D0D0D)`
- 强调色：`Colors.blue`
- 文字：`Colors.white` / `Colors.white54` / `Colors.white30`

### 6.2 交互反馈

- 触觉反馈：长按菜单 `mediumImpact`，横屏左右滑 `lightImpact`
- SnackBar 消息：成功（绿色）/ 错误（红色）
- 确认对话框：删除视频、清空记录等破坏性操作
- 下拉刷新：下载页支持，检测后端 + 刷新任务列表

### 6.3 空状态

- 刷视频无文件夹：引导页（EmptyGuide）+ 跳转设置
- 刷视频无视频：文件夹已添加但无内容
- 下载列表为空：图标 + 提示文字
- 下载错误：红色错误信息卡片

### 6.4 视频播放器

- 竖屏横视频：居中显示 + "横屏播放"按钮
- 横屏：沉浸式全屏，隐藏所有 chrome
- 退出横屏按钮（左上角）
- 播放中暂停显示半透明播放图标

---

## 七、Android 原生配置

### 7.1 权限

```xml
INTERNET                          ← 下载功能
FOREGROUND_SERVICE                ← 熄屏听剧
FOREGROUND_SERVICE_MEDIA_PLAYBACK ← 后台音频
POST_NOTIFICATIONS                ← Android 14+ 前台服务通知
```

### 7.2 构建配置

| 配置项 | 值 |
|--------|---|
| minSdk | 26 |
| compileSdk | flutter.compileSdkVersion |
| targetSdk | flutter.targetSdkVersion |
| AGP | 8.11.1 |
| Kotlin | 2.2.20 |
| Gradle | 8.14 |
| Java | VERSION_17 |
| namespace | com.localtok.local_tok |
| Maven 镜像 | 阿里云 |

### 7.3 Flutter 插件

| 插件 | 用途 |
|------|------|
| video_player | 视频播放 |
| provider | 状态管理 |
| shared_preferences | 用户设置持久化 |
| path_provider | 路径获取 |
| wakelock_plus | 屏幕常亮控制 |
| package_info_plus | 版本信息 |
| dio | HTTP 客户端（后端通信） |
| file_picker | 目录选择 |
| permission_handler | 权限管理 |
| android_intent_plus | 打开系统文件管理器 |

---

## 八、数据流图

### 8.1 下载流程

```
User Input (URL, time, quality, proxy)
  │
  ▼
DownloadScreen._startDownload()
  │
  ▼
DownloadProvider.startDownload()
  │
  ▼
ApiService.startDownload() ──POST──▶ FastAPI /api/download
  │                                     │
  │                                ThreadPoolExecutor
  │                                     │
  │                                yt-dlp subprocess
  │                                     │
  │◀── poll 500ms ── GET /api/tasks/:id ──▶
  │
  ▼
DownloadCard (progress, speed, ETA)
  │
  ▼
status = "done" ▶ DownloadCard turns green
```

### 8.2 视频播放流程

```
App Start
  │
  ▼
SettingsProvider.load() → 读取已保存文件夹
  │
  ▼
VideoProvider.scan(folderUris) → DocumentsContract 扫描
  │
  ▼
ScanState.idle / empty / scanning / error
  │
  ▼ (有视频)
VideoProvider.playRandom() → PlayerProvider.loadCurrent(uri)
  │
  ▼
VideoPlayerWidget + ProgressBar
  │
  ▼ (播完)
autoPlayEnabled? → playNext()
screenOffListening? → playNext() (后台)
else → loop current
```

---

## 九、项目文件结构

```
leotok/
├── lib/
│   ├── main.dart                              # 入口 + 生命周期 + MultiProvider
│   ├── app.dart                               # 路由 + LeoTokApp + MainShell
│   ├── models/
│   │   ├── video_item.dart                    # 视频文件模型
│   │   ├── scan_state.dart                    # 扫描状态枚举
│   │   └── download_task.dart                 # 下载任务模型
│   ├── providers/
│   │   ├── settings_provider.dart             # 播放设置 (StorageService)
│   │   ├── video_provider.dart                # 视频库管理
│   │   ├── player_provider.dart               # 播放控制 + 预加载
│   │   ├── download_provider.dart             # 下载任务管理 + 轮询
│   │   └── download_settings_provider.dart    # 下载设置 (SharedPreferences)
│   ├── screens/
│   │   ├── home_screen.dart                   # 刷视频主页
│   │   ├── settings_screen.dart               # 播放设置页
│   │   ├── download_screen.dart               # 下载主页
│   │   ├── download_settings_screen.dart      # 下载设置页
│   │   ├── download_gallery_screen.dart       # 已下载列表
│   │   └── player_screen.dart                 # 下载视频独立播放
│   ├── services/
│   │   ├── api_service.dart                   # Dio HTTP 客户端
│   │   ├── file_scanner.dart                  # DocumentsContract 扫描
│   │   ├── storage_service.dart               # SharedPreferences 封装
│   │   └── audio_background_service.dart      # 前台音频服务
│   └── widgets/
│       ├── video_player_widget.dart            # 视频播放器组件
│       ├── progress_bar.dart                  # 进度条（点击+拖动+精度+预览）
│       ├── empty_guide.dart                   # 空状态引导
│       ├── long_press_menu.dart               # 长按菜单
│       ├── page_tabs.dart                     # TikTok 风格顶部 Tab
│       ├── download_card.dart                 # 下载进度/状态卡片
│       ├── time_range_picker.dart             # 时间范围选择器
│       └── wheel_time_picker.dart             # 滚轮时间选择器
├── backend/                                   # Python FastAPI 后端
│   ├── server.py                              # API 服务 (8 端点)
│   ├── downloader.py                          # yt-dlp 封装 + 进度解析
│   ├── requirements.txt                       # Python 依赖
│   ├── setup.sh                               # Termux 一键部署
│   ├── start_server.sh                        # 服务控制脚本
│   └── wheels/                                # Android ARM64 预编译 wheel
└── android/                                   # Android 原生配置
```
