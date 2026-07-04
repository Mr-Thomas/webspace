# 扫描仪管理系统 — Scanner Local Service

企业级桌面扫描仪管理系统，面向 Windows 10/11 内网环境，集成 TWAIN 扫描协议、Spring Boot 后端服务和 Tauri 桌面壳，支持 TWAIN 扫描仪的高速连续采集、实时图片推送和 WebSocket 状态同步。

---

## 目录结构

```
scanner-system/
├── backend/                 Spring Boot 后端（jar + jre + lib + config）
├── frontend/                前端页面（Vite 构建产物）
│   └── dist/index.html
├── tauri/                   Tauri 桌面壳（Rust 进程管理）
│   ├── package.json         @tauri-apps/cli 构建依赖
│   └── src-tauri/           Rust 源码 + tauri.conf.json
│       ├── src/lib.rs       后端进程启动/停止/健康检查
│       ├── src/main.rs      入口
│       └── tauri.conf.json  窗口/安全/CSP/前端路径配置
├── installer/               NSIS 安装脚本
│   └── installer.nsi        自定义安装程序（含 WebView2 检测与安装）
├── release/                 构建输出目录（最终安装包）
├── build-release.bat        主构建脚本（一键构建全部组件）
├── build.bat                开发构建脚本（仅构建后端和 Tauri）
└── README.md                本文件
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
1. **构建后端** — Maven 编译 Spring Boot，产出 `scanner-local-service.jar`
2. **验证前端** — 确认 `frontend/dist/index.html` 存在
3. **编译 Tauri** — `cargo tauri build`，生成 `scanner-client.exe`
4. **准备 WebView2** — 下载离线安装包到 `installer/`
5. **打包 NSIS** — 编译 `installer.nsi`，输出安装包到 `release/`

### 开发构建（不打包安装程序）

```batch
build.bat
```

仅执行步骤 1~3，用于快速验证功能。

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

## 安装程序功能

`Scanner_2.0.0_x64-setup.exe` 由自定义 NSIS 脚本生成，提供以下功能：

- **WebView2 运行时管理**
  - 检测系统是否已安装 WebView2 Runtime（注册表检查）
  - 未安装时：优先使用同目录离线包安装 → 自动下载 → 用户选择跳过
  - 内网部署：提前下载 `MicrosoftEdgeWebView2RuntimeInstallerX64.exe` 放到安装包同目录
- **后端部署** — 安装 `scanner-client.exe` + `backend/`（含 JRE 17）到 `C:\Program Files\Scanner\`
- **快捷方式** — 桌面快捷方式 + 开始菜单
- **注册表卸载信息** — 控制面板「程序和功能」可卸载
- **自动清理** — 卸载时停止进程 → 删除文件 → 清理快捷方式

### 内网部署流程

1. 在有网络的机器上运行 `build-release.bat`，或从 CI 获取构建产物
2. 将 `release/Scanner_2.0.0_x64-setup.exe` 拷贝到目标机器
3. （推荐）将 `MicrosoftEdgeWebView2RuntimeInstallerX64.exe` 放在同目录
4. 双击安装包，以管理员身份运行
5. 安装完成后自动启动扫描仪管理程序

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
- WebView2 离线安装包（未打包，安装时部署）：~130MB

---

## 技术栈

| 层次 | 技术 | 版本 |
|------|------|------|
| 桌面壳 | Tauri | 2.x |
| 桌面壳语言 | Rust | 2021 edition |
| 后端框架 | Spring Boot | 3.5.4 |
| JDK | Eclipse Temurin JDK 17 | 17.0.x |
| 扫描协议 | DTWAIN JNI | 1.9.6 |
| API 文档 | Knife4j | 4.5.0 |
| 实时推送 | STOMP over WebSocket | Spring WebSocket |
| 前端 | 原生 HTML/JS + STOMP.js | 7.x |
| 安装程序 | NSIS | 3.09+ |

---

## 关键设计

### 双采集模式

`TransferStrategy` 接口支持两种采集模式：

- **BUFFERED 模式（`NativeTransferStrategy`）**：图像数据传至内存 → 解码 → 裁边 → JPEG → 推送上送。每完成一页即通过 WebSocket 推送状态。
- **FILE 模式（`FileTransferStrategy`）**：驱动直接写文件 → `TwainCallback.onFilePageSaveOk` 回调→逐页上传。零 Java 侧解码，质量无损，速度最快。

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
  └─ start_backend() → java -jar scanner-local-service.jar
  └─ wait_for_backend() → TCP 轮询 127.0.0.1:8899（最长 60s）
  └─ emit "backend-ready" → 前端开始连接 WebSocket

Tauri 窗口关闭 (WindowEvent::Destroyed)
  └─ child.kill() → 终止 java 进程
  └─ child.wait() → 等待退出
```

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