# LeoTok

本地视频播放与下载一体化的 Android 应用。TikTok 式沉浸刷视频 + yt-dlp 视频片段下载，全部在手机上运行。

## 🌟 核心特性

### 刷视频
- **沉浸式交互**：TikTok 式垂直滑动切视频，单击暂停/播放，长按调出功能菜单
- **极致启动速度**：本地视频元数据缓存，启动即播
- **双缓冲播放池**：预加载下一个视频，切换无缝衔接
- **横屏沉浸**：横屏时自动隐藏控件和导航栏，全屏播放
- **进度条增强**：点击跳转、拖动精度（手指拉远减速）、时间预览浮层
- **SAF 安全标准**：遵循 Android Scoped Storage，无需高风险权限

### 下载
- **视频片段下载**：指定起止时间 + 时长，通过 yt-dlp 下载任意视频片段
- **全手机运行**：基于 Termux + Python FastAPI 后端，无需外部服务器
- **实时进度**：下载速度、百分比、ETA 实时反馈
- **代理支持**：HTTP 代理配置，支持网络受限环境

## 🛠 技术栈

- **Frontend**：Flutter (Dart) + Provider 状态管理
- **Backend**：Python FastAPI + yt-dlp (运行在 Termux 中)
- **通信**：HTTP localhost:8000
- **存储**：SharedPreferences + SAF DocumentsContract
- **平台**：Android (Min API 26)

## 🚀 快速开始

### 前提条件
- Flutter SDK
- Android 设备或模拟器 (API 26+)

### 构建安装
```bash
flutter pub get
flutter build apk --release
```

### 后端部署（在手机 Termux 中执行一次）
```bash
cd ~/leotok/backend
./setup.sh
./start_server.sh start
```

## 📂 项目结构

```
leotok/
├── lib/
│   ├── main.dart                          # 应用入口 + 生命周期
│   ├── app.dart                           # 路由 + MainShell (PageView)
│   ├── models/                            # 数据模型
│   ├── providers/                         # Provider 状态管理
│   │   ├── settings_provider.dart         # 播放设置
│   │   ├── video_provider.dart            # 视频库管理
│   │   ├── player_provider.dart           # 播放控制
│   │   ├── download_provider.dart         # 下载任务管理
│   │   └── download_settings_provider.dart # 下载设置
│   ├── screens/
│   │   ├── home_screen.dart               # 刷视频主页
│   │   ├── settings_screen.dart           # 播放设置
│   │   ├── download_screen.dart           # 下载主页
│   │   ├── download_settings_screen.dart  # 下载设置
│   │   ├── download_gallery_screen.dart   # 已下载列表
│   │   └── player_screen.dart             # 下载视频独立播放
│   ├── services/                          # 文件扫描、存储、API 客户端
│   └── widgets/                           # UI 组件
├── backend/                               # Python 后端 (Termux)
│   ├── server.py                          # FastAPI 服务
│   ├── downloader.py                      # yt-dlp 封装
│   ├── setup.sh                           # 一键部署
│   ├── start_server.sh                    # 服务控制
│   └── requirements.txt                   # Python 依赖
└── android/                               # Android 原生配置
```

## 📄 开源协议
[MIT License](LICENSE)
