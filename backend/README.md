# DroidDL Backend

FastAPI 后端，运行在 Termux (Android) 上，通过 `yt-dlp` CLI 下载视频片段。Flutter 前端通过 localhost HTTP 与后端通信。

## 目录结构

```
backend/
├── server.py           # FastAPI 应用 (7 个 API 端点)
├── downloader.py       # yt-dlp 子进程调用 + 进度解析
├── setup.sh            # 一键初始化脚本 (Termux 首次部署用)
├── start_server.sh     # 服务控制脚本 (start/stop/restart/status)
├── requirements.txt    # 依赖清单 (含 --find-links 本地 wheel)
├── .python-version     # Python 版本锁定 (3.13)
├── wheels/             # Android ARM64 预编译 wheel
 └── pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl
```

## API 端点

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET` | `/api/health` | 健康检查，返回 yt-dlp 版本和输出目录 |
| `POST` | `/api/download` | 发起下载任务 (非阻塞，立即返回 task) |
| `GET` | `/api/tasks` | 列出所有任务 (最近优先) |
| `GET` | `/api/tasks/{id}` | 轮询单个任务 (Flutter 用此获取进度) |
| `DELETE` | `/api/tasks/{id}` | 取消运行中的下载 |
| `DELETE` | `/api/videos/{id}` | 删除已完成下载 (文件 + 记录) |
| `GET` | `/api/videos/{id}/file` | 流式传输下载完成的视频文件 |
| `POST` | `/api/proxy/test` | 测试代理连通性 |

## 快速开始

### 前置条件

- **Python 3.13** (Termux 上 `pkg install python-3.13`)
- **uv** (Termux 上 `pip install uv`)
- **yt-dlp** CLI (uv 会自动安装)
- **Termux 存储权限** (`termux-setup-storage`)

### 一键部署 (Termux)

```bash
cd ~/yt-dlp-android/backend
./setup.sh
```

`setup.sh` 做了这些事：
1. 用 Python 3.13 创建虚拟环境
2. **优先安装本地 pydantic-core wheel**（跳过 Rust 编译）
3. 安装其余依赖

### 启动服务

```bash
./start_server.sh start
```

服务将在 `127.0.0.1:8000` 启动，日志输出到 `~/server.log`。

## start_server.sh 使用指南

```bash
# 启动
./start_server.sh start

# 停止 (优雅关闭 → 5 秒后强杀)
./start_server.sh stop

# 重启
./start_server.sh restart

# 查看状态 (PID + 端口)
./start_server.sh status
```

脚本特性：
- **PID 文件管理** — PID 写入 `~/server.pid`，启动时检测重复运行，避免端口冲突
- **优雅关闭** — `stop` 先发 SIGTERM，等 5 秒无响应再 SIGKILL
- **启动验证** — `start` 等待 1.5 秒后确认进程存活，失败则报错
- **自动清理** — 进程已死时，`status`/`stop` 自动清理残留 PID 文件
- **输出目录** — 默认 `/data/data/com.termux/files/home/storage/downloads`，可通过 `VD_OUTPUT_DIR` 环境变量覆盖

### 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VD_OUTPUT_DIR` | Termux 中: `~/storage/downloads`<br>桌面: `/sdcard/Download` | 视频下载输出目录 |

## 桌面测试

在电脑上临时运行后端进行调试：

```bash
cd backend

# 安装依赖 (桌面不需要 Android wheel 也能编译 pydantic-core)
uv venv --python python3.13
source .venv/bin/activate
uv pip install -r requirements.txt

# 启动
python server.py
```

> **注意**: 桌面端不需要 `--find-links ./wheels` 也能工作，因为 PyPI 提供 Linux x86_64 的 pydantic-core 预编译 wheel。

## pydantic-core 编译指南

`pydantic-core` 是 Pydantic v2 的 Rust 核心库，PyPI **不提供** Android ARM64 预编译 wheel。所以需要在自己的手机上编译一次，产物放入 `wheels/` 目录。

### 为什么会出问题？

```
pydantic-core 编译需要:
  1. Rust 工具链 (rustc, cargo)
  2. maturin (Rust → Python wheel 构建工具)
  3. Android 交叉编译目标: aarch64-unknown-linux-android
```

rustup 并不支持 `aarch64-unknown-linux-android` 这个 target triple，普通的 NDK 交叉编译流程在 Termux 上走不通。

### 解决办法：本地编译 + 修改平台标签

Termux 本身就是一个 Linux 环境，不需要交叉编译——直接 native 编译即可，只是编译产物的 WHEEL 平台标签需要修正。

### 步骤 (在你的 Android 手机上操作)

#### 1. 安装 Rust 和 maturin

```bash
pkg install rust binutils
pip install maturin
```

Termux 的 `rust` 包自带 `rustc` + `cargo`，编译目标就是 `aarch64-linux-android`。

#### 2. 下载 pydantic-core 源码

```bash
cd /tmp
pip download pydantic-core==2.46.4 --no-binary :all: --no-deps
tar xzf pydantic_core-2.46.4.tar.gz
cd pydantic_core-2.46.4
```

#### 3. 编译 wheel

```bash
maturin build --release --interpreter python3.13
```

编译大约需要 5-10 分钟。完成后在 `target/wheels/` 下会生成一个 `.whl` 文件，文件名类似：

```
pydantic_core-2.46.4-cp313-cp313-android_33_arm64_v8a.whl
```

#### 4. 修正平台标签 ⚠️

这是最关键的一步。编译出来的 wheel 标签是 `android_33`，但 Termux 的 Python 报告的平台是 `android_24`。如果直接安装，pip 会拒绝：

```
ERROR: pydantic_core-...-android_33_arm64_v8a.whl is not a supported wheel on this platform.
```

修复方法：把 wheel 文件名和内部 `WHEEL` 记录中的 `android_33` 都改成 `android_24`。

```bash
# 1. 重命名文件
mv pydantic_core-2.46.4-cp313-cp313-android_33_arm64_v8a.whl \
   pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl

# 2. 修改 wheel 内部的 WHEEL 记录
unzip pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl \
     pydantic_core-2.46.4.dist-info/WHEEL -d /tmp/wheel_fix

# 编辑 WHEEL 文件，把 Tag 行里的 android_33 改成 android_24
sed -i 's/android_33/android_24/g' /tmp/wheel_fix/pydantic_core-2.46.4.dist-info/WHEEL

# 写回 wheel
cd /tmp/wheel_fix
zip -u ../pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl \
       pydantic_core-2.46.4.dist-info/WHEEL
```

#### 5. 验证安装

```bash
pip install pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl
python -c "import pydantic_core; print(pydantic_core.__version__)"
```

输出 `2.46.4` 就说明成功了。

#### 6. 放入项目

```bash
mkdir -p ~/yt-dlp-android/backend/wheels
cp pydantic_core-2.46.4-cp313-cp313-android_24_arm64_v8a.whl \
   ~/yt-dlp-android/backend/wheels/
```

已经在本项目中的 wheel 复制过去即可，不需要每次编译。

### 什么时候需要重新编译？

- **Python 版本变更**（wheel 标签 `cp313` 与解释器绑定）——例如从 3.13 升级到 3.14
- **pydantic-core 版本升级**——`requirements.txt` 中版本更新时需要对应新 wheel
- **Termux API 版本变更**（极少见）——如果平台标签 `android_24` 不再匹配

### 验证 wheel 是否存在

```bash
ls -lh backend/wheels/*.whl
# 应显示约 1.9MB 的 .whl 文件
```

## 下载流程

```
Flutter App                    FastAPI Server               yt-dlp CLI
    │                                │                          │
    ├── POST /api/download ─────────►│                          │
    │   {url, start_time, duration}  │                          │
    │                                ├── Popen(yt-dlp ...) ────►│
    │◄── task_id (immediate) ────────│                          │
    │                                │                          │
    │  (每 500ms 轮询)                │                          │
    ├── GET /api/tasks/{id} ────────►│                          │
    │◄── {progress: 45.2%} ─────────│  (读取 stderr 进度)       │
    │                                │                          │
    │  (下载完成)                     │                          │
    ├── GET /api/tasks/{id} ────────►│                          │
    │◄── {status: "done", ...} ──────│                          │
```

`downloader.py` 通过**子进程**调用 `yt-dlp` CLI（而非 Python API），确保 `--download-sections` 行为与命令行完全一致。

## 常见问题

### `uv add -r requirements.txt` 报 pydantic-core 编译失败

不要在 Termux 上运行时 `uv add` —— 使用 `./setup.sh`，它会先安装本地 wheel 再装其他依赖。

### `./setup.sh` 报 `python3.13 not found`

```bash
pkg install python-3.13
```

### 服务器端口被占用

```bash
./start_server.sh restart
```

### 在桌面运行时 `--impersonate chrome` 报错

```bash
source .venv/bin/activate
uv pip install curl-cffi
```

### 手机通知 Flutter App "后端未运行"

可能原因：
1. 服务器未启动 — `./start_server.sh status` 检查
2. 手机没开 WiFi 热点 / 未在同一网络
3. 在前端设置中检查服务器地址是否为 `127.0.0.1:8000`
