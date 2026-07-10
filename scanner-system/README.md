# 扫描仪管理系统 — Scanner System

企业级桌面扫描仪管理系统，面向 Windows 10/11 内网环境，集成 TWAIN 扫描协议、Spring Boot 后端服务和 Tauri 桌面壳，支持高速连续采集、实时图片推送和 WebSocket 状态同步。

```
┌───────────────────────────────────────────────┐
│  Tauri 桌面壳 (scanner-client.exe)             │
│  ├─ WebView2 窗口 ── 前端 SPA                  │
│  └─ 后端进程管理: 启动 → 健康检查 → 优雅关闭    │
├───────────────────────────────────────────────┤
│  Spring Boot 后端 (scanner-local-service.jar)  │
│  ├─ Controller → ScanService → ScannerManager  │
│  ├─ WebSocket (STOMP) 实时推送                 │
│  └─ 端口 8899                                  │
├───────────────────────────────────────────────┤
│  JRE 17 (jlink 裁剪 ~40MB) + DTWAIN JNI        │
└───────────────────────────────────────────────┘
```

## 目录结构

```
scanner-system/
├── backend/                 Spring Boot 发行包（jar + jlink JRE + lib + config）
│   ├── scanner-local-service.jar   后端主程序
│   ├── jre/                        裁剪 JRE 17（~40MB）
│   ├── lib/                        DTWAIN JNI 本地库
│   ├── config/                     application.yml + logback.xml
│   └── logs/                       运行时日志
├── frontend/                前端页面（Vite 构建产物）
│   └── dist/index.html      单页应用（原生 HTML/JS + STOMP.js）
├── tauri/                   Tauri 桌面壳
│   ├── package.json         @tauri-apps/cli 构建依赖
│   └── src-tauri/
│       ├── src/lib.rs       后端进程启动/停止/健康检查
│       ├── src/main.rs      入口（windows_subsystem = "windows"）
│       └── tauri.conf.json  窗口/安全/CSP/前端路径
├── installer/               NSIS 安装脚本
│   ├── installer.nsi
│   └── runtime/             WebView2 离线安装包（构建时下载）
├── release/                 构建输出
├── build.bat                开发构建
├── build-release.bat        发行构建（含 NSIS 安装包）
└── README.md
```

## 环境要求

| 组件 | 版本 | 说明 |
|------|------|------|
| JDK | 17+ | 构建 Spring Boot 后端 |
| Maven | 3.8+ | 后端构建 |
| Rust | 1.77+ | `rustup target add x86_64-pc-windows-msvc` |
| Node.js | 18+ | Tauri CLI |
| Visual Studio Build Tools | 2022 | MSVC 工具链 |
| NSIS | 3.09+ | 安装程序编译 |

## 构建

### 一键发行构建

```batch
build-release.bat
```

流程：
1. **构建后端** — Maven 编译 `D:\workspace\scanner-local-service`，产出 jar + jlink JRE
2. **验证前端** — 确认 `frontend/dist/index.html` 存在
3. **编译 Tauri** — `npx tauri build`，生成 `scanner-client.exe`
4. **准备 WebView2** — 下载离线安装包到 `installer/runtime/`
5. **打包 NSIS** — 编译 `installer.nsi`，输出 `release/Scanner_2.0.0_x64-setup.exe`

### 开发构建

```batch
build.bat
```

仅执行步骤 1~3，跳过 WebView2 下载和安装包制作。

### 手动运行

**后端：**
```bash
cd backend
jre/bin/java -Dfile.encoding=UTF-8 -Djava.library.path=./lib -jar scanner-local-service.jar --server.port=8899
```

**Tauri 开发模式（需后端已启动）：**
```bash
cd tauri
npm install
npx tauri dev
```

## 架构要点

### 进程生命周期

```
Tauri 启动 → start_backend() → wait_for_backend()（TCP 轮询 60s，1s间隔）
  → emit "backend-ready" → 前端连接 WebSocket
  ↓
窗口关闭：CloseRequested 阻止关闭，隐藏到系统托盘
托盘退出 或 Destroyed：child.kill() → child.wait()
```

### Tauri 壳功能

- 系统托盘（左键显示窗口，右键菜单：显示窗口/退出）
- 单实例锁（`tauri_plugin_single_instance`）
- 窗口 1280x900，居中，可调整大小
- `devUrl: http://localhost:8899` — 开发模式直接加载后端页面

### 前端功能

1785 行单页应用，原生 HTML/JS + STOMP.js v7：
- 连接管理（服务器地址 + JWT Token）
- 扫描仪设备列表与状态刷新
- 扫描任务配置（DPI、色彩模式、输出格式、双面、图像增强）
- 任务管理（启动/停止/查询/列表/健康检查/历史文件）
- 实时日志（彩色编码：发送/接收/信息/错误/警告）
- 图片画廊（5 列网格 + Lightbox 大图预览 + 键盘导航）
- 历史文件三层浏览（日期 → 任务 → 文件）
- Tauri 桌面环境自动检测后端就绪后连接 WebSocket

### CSP 安全策略

```json
"connect-src 'self' http://localhost:8899 ws://localhost:8899"
"img-src 'self' data: http://localhost:8899"
```

调试时出现加载问题，优先检查 `tauri.conf.json` 中 CSP 配置。

### 安装程序（NSIS）

- 安装路径：`C:\Program Files\Scanner`
- 提权等级：admin
- 先杀已有进程（`taskkill /f /im scanner-client.exe` 和 `java.exe`）
- WebView2 检测注册表 → 缺失则运行离线安装包 → 失败则在线下载兜底
- 创建桌面快捷方式 + 开始菜单
- 语言：简体中文

## API 参考

### REST

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/scan/health` | 健康检查 |
| GET | `/api/scan/scanners` | 扫描仪列表及状态 |
| GET | `/api/scan/files/{taskId}/{page}` | 扫描页图片 |
| GET | `/api/scan/history/folders` | 历史日期文件夹 |
| GET | `/api/scan/history/folders/{dateDir}` | 某日期下的任务列表 |
| GET | `/api/scan/history/folders/{dateDir}/{taskId}` | 某任务的文件列表 |

### WebSocket（STOMP）

端点：`ws://{host}:8899/ws`。心跳 20s。

| 方向 | 目标 | 说明 |
|------|------|------|
| 发送 | `/app/scan/start` | 启动扫描 |
| 发送 | `/app/scan/stop` | 停止扫描 |
| 发送 | `/app/scan/status` | 查询任务状态 |
| 发送 | `/app/scanner/status` | 扫描仪状态刷新 |
| 接收 | `/user/queue/reply` | 命令回复 |
| 接收 | `/user/queue/task/{taskId}` | 任务进度推送 |
| 接收 | `/topic/scanner` | 扫描仪状态变更广播 |

## 配置 Profile

| Profile | 日志级别 | 认证 | Knife4j | 用途 |
|---------|---------|------|---------|------|
| dev（默认） | DEBUG | 关闭 | 启用 | 开发调试 |
| prod | INFO | JWT | 禁用 | 生产部署 |

## 构建产物

| 产物 | 路径 | 大小 |
|------|------|------|
| 安装包 | `release/Scanner_2.0.0_x64-setup.exe` | ~200MB |
| 桌面壳 | `tauri/src-tauri/target/release/scanner-client.exe` | ~8MB |
| 后端发行 | `backend/` | ~80MB |
| 前端页面 | `frontend/dist/index.html` | ~60KB |

## 开发说明

**后端 Java 源码**在独立仓库 `D:\workspace\scanner-local-service` 中管理，本仓库 `backend/` 是构建产物。修改后端逻辑需编辑该仓库，然后运行 `build.bat` 同步。

**前端**是纯静态单页应用，无构建工具链。`frontend/index.html` 与 `frontend/dist/index.html` 内容相同。

## 技术栈

| 层次 | 技术 | 版本 |
|------|------|------|
| 桌面壳 | Tauri | 2.x |
| 后端 | Spring Boot | 3.5.4 (Java 17) |
| 扫描协议 | DTWAIN JNI | 1.9.7 |
| API 文档 | Knife4j | 4.5.0 |
| 实时推送 | STOMP over WebSocket | Spring WebSocket |
| 安装程序 | NSIS | 3.09+ |

## 常见问题

**Q: 安装后点击桌面快捷方式没反应？**
A: 检查 WebView2 是否已安装。Win10/11 通常内置，早期版本需手动安装。

**Q: 扫描仪连接不上？**
A: 确认 TWAIN 驱动已安装，查看 `backend/logs/info.log` 排查初始化日志。

**Q: 构建时 MSVC 工具链报错？**
A: 安装 Visual Studio Build Tools 2022，选择「使用 C++ 的桌面开发」工作负载。

**Q: 内网无法下载 WebView2？**
A: 在有网络的机器提前下载 `MicrosoftEdgeWebView2RuntimeInstallerX64.exe`，放入 `installer/runtime/` 目录。

## 许可证

MIT License