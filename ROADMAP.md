# LeoTok — 项目路线图

> 本地视频短视频播放器，抖音式交互体验。

---

## 基本信息

| 项目 | 详情 |
|------|------|
| **应用名称** | LeoTok |
| **技术栈** | Flutter (Dart), Kotlin |
| **状态管理** | Provider |
| **存储方案** | SAF + Video Cache (JSON File) |
| **当前状态** | P0 技术债务已清零，进行 P1 功能优化 |

---

## 功能清单

### ✅ 已实现 (Done)

#### 核心播放 (P0)
- [x] 主页面全屏视频播放
- [x] TikTok 式垂直切换手势（上划下划）
- [x] 智能历史栈：支持回看及循环逻辑
- [x] 沉浸式 UI 隐藏逻辑（单击暂停/恢复）
- [x] 进度条拖拽与文件名显示
- [x] 长按功能菜单：倍速切换、自动播放开关、熄屏听剧

#### 性能优化 (P0 - Hardcore)
- [x] **数据持久化缓存**：启动无需全量扫描，实现秒级冷启动。
- [x] **增量索引同步**：基于 `lastModified` 的智能更新，复用视频元数据。
- [x] **高性能底层查询**：从 `DocumentFile` 迁移至 `DocumentsContract` 原生查询。
- [x] **异步进度反馈**：扫描时实时回传当前路径与数量，解决界面卡死问题。
- [x] **后台播放管理**：优化多级路由下的播放器生命周期，解决"幽灵声音" Bug。

#### 存储与设置 (P0)
- [x] SAF 文件夹多路径持久化授权
- [x] 递归文件过滤（.mp4, .mkv, .webm）
- [x] 设置页管理（增删文件夹、刷新索引、进度展示）
- [x] 随机去重算法（Window Size: 20）

### 🛡️ 技术债务与缺陷修复 (P0 — 已完成)

- [x] **实现真正的双缓冲播放池** — 新增 `peekNext()` / `preloadNext()` 方法，在视频加载成功后预初始化下一个 controller，切换时直接 swap。消除网络存储和本地切换时的黑屏闪烁。
- [x] **修复 SharedPreferences 存储大 JSON 的性能问题** — 视频缓存从 SharedPreferences StringList 迁移到独立 JSON 文件（`video_cache.json`），冷启动异步加载，旧数据自动迁移。
- [x] **修复熄屏听剧的 resume 竞态条件** — `Future.delayed` 替换为可取消的 `Timer`，生命周期变化时取消旧回调，resume 前检查 controller 状态。
- [x] **配置 AudioFocus 鸭式行为** — 所有 `VideoPlayerController` 创建时使用 `VideoPlayerOptions(mixWithOthers: true)`，不再打断其他 app 的后台音频。
- [x] **防止 scanPercent 除零 NaN** — `folderUris.isEmpty` 时提前返回，避免 `i / 0` 产生 NaN。

### 🔜 待办 (P1 — 功能计划)

- [ ] **播放历史栈支持跨跳选** — 当前双栈模型只能线性前进/后退，无法跳过某个视频。用户回溯时如果想快速定位，需要把栈全清空。
- [x] **删除视频后校验 forwardHistory** — `deleteVideo()` 会移除被删视频的 uri。手动删除场景下 `playNext()` 弹出死 URI 后自动从 forwardHistory 移除，加载失败时回退到上一个视频。
- [x] **添加视频加载错误恢复机制** — `_loadCurrentVideo` 失败时自动调用 `playPrevious()` 回退到上一个正常播放的视频，避免播放位置丢失。
- [x] **SettingsScreen 应通过 Provider 获取 FileScanner** — Settings 页面通过 `context.read<VideoProvider>().scanner` 获取共享实例，不再 `new FileScanner()`。
- [x] **修复进度条圆点偏移** — `_seekTo()` 中移除了重复扣减的 32px horizontal padding，边界处 seek 位置不再偏移。

### 🔮 待办 (P2 — 未来迭代)

- [ ] **列表视图** — 网格化预览所有视频，支持快速定位。
- [ ] **缩略图支持** — 扫描时静默生成本地缩略图，提升列表美感。
- [ ] **视频信息详情** — 分辨率、编码格式、文件大小的详细展示。
- [ ] **画中画 (PiP)** — 支持 Android 原生 PiP 模式。
- [ ] **文件夹重命名/分类** — 支持在应用内给索引的文件夹起别名。

### ❌ 不做 (Out of Scope)

- ~~云端同步~~（纯本地隐私播放器）
- ~~社交/分享功能~~
- ~~视频编辑/剪辑~~

---

## 技术指标

- **启动耗时**: < 500ms (有缓存) / < 3s (首扫 100+ 视频)
- **内存占用**: 约 150MB - 300MB (取决于视频分辨率与预加载池)
- **Android 支持**: Android 8.0 (API 26) 及以上
- **权限需求**: 仅 SAF 文件夹授权，无需文件权限

---

## 进度追踪 (Phase View)

### Phase 1: 核心链路交付 (Completed)
- [x] 基础设施构建
- [x] SAF 扫描服务
- [x] 基础播放与手势

### Phase 2: 性能与体验打磨 (Completed)
- [x] 启动加速计划 (Cache System)
- [x] 扫描性能飞跃 (DocumentsContract)
- [x] 交互 Bug 清理 (Audio Lifecycle)
- [x] 技术债务清零 (双缓冲播放池 / 存储迁移 / 竞态修复 / AudioFocus / NaN 保护)

### Phase 3: 功能丰富化 (In Progress)
- [x] 进度条修复 / 错误恢复 / 死 URI 跳过 / DI 重构
- [ ] 播放历史栈跨跳选
- [ ] 列表预览模式
- [ ] 性能监控与自动埋点
