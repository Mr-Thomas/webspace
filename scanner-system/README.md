# 扫描仪管理系统 — Scanner Local Service

企业级桌面扫描仪管理系统，面向 Windows 10/11 内网环境，集成 TWAIN 扫描协议、Spring Boot 后端服务和 Tauri 桌面壳，支持 TWAIN 扫描仪的高速连续采集、实时图片推送和 WebSocket 状态同步。

---

## 目录结构

```
scanner-system/
├── backend/                 Spring Boot 发行包（jar + jlink JRE + lib + config）
│   ├── scanner-local-service.jar   后端主程序
│   ├── jre/                        裁剪后的 JRE 17（~40MB，构建时由 jlink 生成）
│   ├── lib/                        DTWAIN JNI 本地库（dtwain64u.dll 等）
│   ├── config/                     配置文件（application.yml/prod/dev + logback.xml）
│   └── logs/                       运行时日志（按级别分文件）
├── frontend/                前端页面（Vite 构建产物）
│   └── dist/index.html      单页应用（原生 HTML/JS + STOMP.js）
├── tauri/                   Tauri 桌面壳（Rust 进程管理）
│   ├── package.json         @tauri-apps/cli 构建依赖
│   └── src-tauri/           Rust 源码 + tauri.conf.json
│       ├── src/lib.rs       后端进程启动/停止/健康检查
│       ├── src/main.rs      入口（windows_subsystem = "windows"）
│       └── tauri.conf.json  窗口/安全/CSP/前端路径配置
├── installer/               NSIS 安装脚本
│   ├── installer.nsi        自定义安装程序
│   └── runtime/             WebView2 离线安装包（构建时下载）
├── release/                 构建输出目录（最终安装包 .exe）
├── CLAUDE.md                Claude Code 项目指引
├── README.md                本文件
├── build-release.bat        发行构建脚本（后端 + Tauri + WebView2 + NSIS）
├── build.bat                开发构建脚本（仅后端和 Tauri）
└── LICENSE.txt              MIT 许可证
```

### 架构分层

```
┌──────────────────────────────────────────────────┐
│  Tauri 桌面壳 (scanner-client.exe)               │
│  ├─ WebView2 窗口 ── frontend/dist/index.html    │
│  └─ 后端进程管理: 启动 → 健康检查 → 优雅关闭     │
├──────────────────────────────────────────────────┤
│  Spring Boot 后端 (scanner-local-service.jar)    │
│  ├─ Controller → ScanService → ScannerManager    │
│  ├─ WebSocket (STOMP) 实时推送                    │
│  └─ 端口 8899                                    │
├──────────────────────────────────────────────────┤
│  JRE 17 (jlink 裁剪 ~40MB) + DTWAIN JNI          │
└──────────────────────────────────────────────────┘
```

---

## 快速开始

### 环境要求

| 组件 | 版本 | 说明 |
|------|------|------|
| JDK | 17+ | 构建 Spring Boot 后端 |
| Maven | 3.8+ | 后端构建 |
| Rust | 1.77+ | 编译 Tauri 壳（`rustup target add x86_64-pc-windows-msvc`） |
| Node.js | 18+ | Tauri CLI 构建工具 |
| Visual Studio Build Tools | 2022 | MSVC 工具链（`cl.exe`、`link.exe`） |
| NSIS | 3.09+ | 安装程序编译 |
| TWAIN 扫描仪 | — | 硬件设备（开发调试需要） |

### 一键构建

```batch
build-release.bat
```

执行流程：

1. **构建后端** — Maven 编译 Spring Boot 后端源码（位于 `D:\workspace\scanner-local-service`），产出 jar + jlink 裁剪 JRE
2. **验证前端** — 确认 `frontend/dist/index.html` 存在
3. **编译 Tauri** — `cargo tauri build`，生成 `scanner-client.exe`
4. **准备 WebView2** — 下载离线安装包到 `installer/runtime/`
5. **打包 NSIS** — 编译 `installer.nsi`，输出 `release/Scanner_2.0.0_x64-setup.exe`

### 开发构建（不打包安装程序）

```batch
build.bat
```

仅执行步骤 1~3，适用于快速验证功能。

### 手动运行

**后端：**

```bash
cd backend
jre/bin/java -Dfile.encoding=UTF-8 -Djava.library.path=./lib -jar scanner-local-service.jar --server.port=8899
```

**Tauri 壳（开发模式，需后端已启动）：**

```bash
cd tauri
npm install
npx tauri dev
```

---

## API 参考

### REST 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/scan/health` | 健康检查（Tauri 启动时轮询此接口） |
| GET | `/api/scan/scanners` | 获取扫描仪列表及状态 |
| GET | `/api/scan/files/{taskId}/{page}` | 获取扫描页图片 |
| GET | `/api/scan/history/folders` | 历史文件：日期文件夹列表 |
| GET | `/api/scan/history/folders/{dateDir}` | 历史文件：某日期下的任务列表 |
| GET | `/api/scan/history/folders/{dateDir}/{taskId}` | 历史文件：某任务的文件列表 |

### WebSocket (STOMP)

**端点：** `ws://{host}:8899/ws`

**客户端 → 服务端：**

| 目标 (Destination) | 请求体 | 说明 |
|------|------|------|
| `/app/scan/start` | `{ task_id, dpi, color_mode, duplex, output_format, ... }` | 启动扫描任务 |
| `/app/scan/status` | `{ task_id }` | 查询任务状态 |
| `/app/scan/stop` | `{ task_id }` | 停止扫描任务 |
| `/app/scan/list` | `{}` | 任务列表 |
| `/app/scanner/status` | `{}` | 扫描仪状态刷新 |

**服务端 → 客户端：**

| 目标 (Destination) | 说明 |
|------|------|
| `/user/queue/reply` | 命令回复（含扫描仪列表、采集模式等） |
| `/user/queue/task/{taskId}` | 任务进度推送（含事件类型 `task_progress`、`task_status`、`task_error`） |
| `/topic/scanner` | 扫描仪状态变更广播 |

---

## 配置参考

### application.yml 核心配置项

| 配置项 | 默认值 | 说明 |
|------|------|------|
| `server.port` | `8899` | 服务端口 |
| `scanner.twain` | `SAFE` | 线程模式：`SAFE`（全局串行）或 `MULTI`（多扫描仪并行） |
| `scanner.acquire-mode` | `FILE` | 采集模式：`FILE`（驱动直出文件）或 `BUFFERED`（内存缓冲+后处理） |
| `scanner.show-ui` | `false` | 是否显示 TWAIN 驱动界面 |
| `scanner.upload-url` | `""` | 远程上传地址（为空则仅本地保存） |
| `scanner.temp-dir` | `./temp` | 扫描临时文件目录 |
| `scanner.check-interval` | `5` | 扫描仪状态轮询间隔（秒） |
| `scanner.auto-open-browser` | `true` | 启动后自动打开浏览器（Launch4j 启动器用 -D 控制） |
| `scanner.auth.enabled` | `false` | 是否启用 JWT 认证 |

### 环境配置

| 文件 | Profile | 日志级别 | 认证 | Knife4j |
|------|---------|---------|------|---------|
| `application-dev.yml` | dev（默认） | DEBUG | 关闭 | 启用 |
| `application-prod.yml` | prod | INFO | 开启 | 禁用 |

---

## 关键设计

### 双采集模式

`TransferStrategy` 接口支持两种采集模式：

- **BUFFERED 模式（`NativeTransferStrategy`）**：图像数据传至内存 → 解码 → 裁边 → JPEG → 推送上送。每完成一页即通过 WebSocket 推送状态。
- **FILE 模式（`FileTransferStrategy`）**：驱动直接写文件 → `TwainCallback.onFilePageSaveOk` 回调 → 逐页上传。零 Java 侧解码，质量无损，速度最快。

### 线程模型

- TWAIN 操作必须在独立于 Spring 主线程的线程中执行
- `ScannerManager` 维护固定大小线程池（等于扫描仪数量，最少 1）
- 每台扫描仪由 `Semaphore(1)` 保护（ScannerSlot）
- SAFE 模式使用全局 `Semaphore(1)` 串行化所有采集（30s 超时）

### WebSocket 心跳

- 双向 20 秒心跳（`heartbeatIncoming: 20000, heartbeatOutgoing: 20000`）
- 专用 `ThreadPoolTaskScheduler(poolSize=2)`
- STOMP.js v7 自动重连，断开时不置空 stomp 引用

### TWAIN 熔断器

超时 15s → OPEN → 冷却 30s → HALF_OPEN → 探测 → CLOSED

### 进程生命周期

```
Tauri 启动
  └─ start_backend() → javaw -jar scanner-local-service.jar
  └─ wait_for_backend() → TCP 轮询 127.0.0.1:8899（最长 60s）
  └─ emit "backend-ready" → 前端开始连接 WebSocket

Tauri 窗口关闭 (WindowEvent::Destroyed)
  └─ child.kill() → 终止 java 进程
  └─ child.wait() → 等待退出
```

### 前端功能

- 原生 HTML/JS 单页应用，通过 STOMP.js v7 与后端 WebSocket 通信
- 扫描仪状态监控（就绪/繁忙/缺纸/卡纸等）
- 扫描任务管理（启动/停止/查询）
- 实时图片画廊预览（含 Lightbox 大图浏览）
- 历史文件三层浏览（日期 → 任务 → 文件）
- Tauri 桌面环境自动连接后端

---

## 构建产物说明

| 产物 | 路径 | 大小 | 说明 |
|------|------|------|------|
| 安装包 | `release/Scanner_2.0.0_x64-setup.exe` | ~200MB | 完整安装程序（含 JRE + WebView2） |
| 桌面壳 | `tauri/src-tauri/target/release/scanner-client.exe` | ~8MB | Tauri 独立可执行文件 |
| 后端发行 | `backend/` | ~80MB | Spring Boot jar + JRE + lib |
| 前端页面 | `frontend/dist/index.html` | ~60KB | 单页应用（嵌入 Tauri 壳） |

安装包大小明细：
- Tauri 壳 + 前端：~8MB
- JRE 17（jlink 裁剪）：~40MB
- Spring Boot jar + DTWAIN lib：~40MB
- WebView2 离线安装包（嵌入安装包）：~130MB

---

## 开发说明

**后端源码位置：**`D:\workspace\scanner-local-service`

本仓库中的 `backend/` 目录是构建产物，后端 Java 源码在独立仓库中管理。如需修改后端逻辑，请直接编辑 `D:\workspace\scanner-local-service` 中的源码，然后运行 `build.bat` 重新构建。

---

## 常见问题

**Q: 安装后点击桌面快捷方式没反应？**
A: 检查 WebView2 是否已安装。Win10/11 通常内置，Win10 早期版本可能需要手动安装。

**Q: 扫描仪连接不上？**
A: 确认 TWAIN 驱动已正确安装。在 `backend/logs/` 中查看 `info.log` 排查初始化日志。

**Q: 构建时 MSVC 工具链报错？**
A: 安装 Visual Studio Build Tools 2022，选择「使用 C++ 的桌面开发」工作负载。

**Q: 内网无法下载 WebView2？**
A: 在有网络的机器提前下载 `MicrosoftEdgeWebView2RuntimeInstallerX64.exe`，和安装包放在同一目录即可。

---

## 许可证

MIT License — 详见 [LICENSE.txt](LICENSE.txt)