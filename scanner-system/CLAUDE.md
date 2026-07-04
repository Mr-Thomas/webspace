# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

企业级桌面扫描仪管理系统，面向 Windows 10/11 内网环境。三层架构：

- **Tauri 桌面壳** (Rust) — 进程管理：启动 Spring Boot 后端、TCP 健康检查轮询、窗口关闭时 kill 进程
- **Spring Boot 后端** (Java 17) — 扫描仪控制、WebSocket 实时推送、REST API
- **前端** (原生 HTML/JS) — STOMP.js WebSocket 客户端，单页应用

## 目录结构

```
scanner-system/
├── backend/          ← Spring Boot 发行包（jar + jlink JRE + DTWAIN dll + config）
├── frontend/dist/    ← 前端页面（Vite 构建产物，仅 index.html）
├── tauri/            ← Tauri 桌面壳
│   ├── package.json
│   └── src-tauri/
│       ├── src/lib.rs  ← 后端进程启动/停止/健康检查
│       ├── src/main.rs ← #![windows_subsystem = "windows"] 入口
│       └── tauri.conf.json
├── installer/        ← NSIS 安装脚本（含 WebView2 检测/安装）
├── release/          ← 构建输出（最终安装包）
├── build.bat         ← 开发构建（后端 + Tauri）
└── build-release.bat ← 完整构建（后端 + Tauri + WebView2 + NSIS 安装包）
```

**注意：后端 Java 源码不在本仓库中**，位于 `D:\workspace\scanner-local-service`。构建脚本通过绝对路径引用该目录。

## 构建命令

```batch
build.bat           ← 开发构建（后端 jar + Tauri exe，跳过安装包）
build-release.bat   ← 发行构建（全套，含 NSIS 安装包）
```

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

## 架构关键点

### Tauri 壳 (Rust)

- `lib.rs` 的 `run()` 在 `setup` 阶段启动 java 进程，另起线程 TCP 轮询 `127.0.0.1:8899`（最多 60 次，间隔 1s），就绪后 emit `backend-ready` 事件
- `WindowEvent::Destroyed` 时 `child.kill()` + `child.wait()` 终止后端
- 使用 `javaw.exe`（无窗口版 JVM）启动，生产环境通过 `#![windows_subsystem = "windows"]` 隐藏控制台

### 后端 (Spring Boot)

包结构 (`D:\workspace\scanner-local-service`):
- `controller/` — `ScannerController` (REST) + `ScanController` (WebSocket STOMP 命令)
- `scanner/` — `ScannerManager` (线程池管理)、`ScanEngine` (采集引擎)、`TransferStrategy` (双模式采集)
- `websocket/` — `ScanWebSocketController` (STOMP 消息处理)、`PushService` (实时推送)
- `task/` — `TaskManager` (任务生命周期)、`ScanTask` (单次扫描任务)
- `auth/` — `JwtUtil` (JWT 认证)

### 双采集模式

配置 `scanner.acquire-mode`:
- **FILE 模式**（默认）：驱动直写文件 → 回调上传，零 Java 侧解码，质量无损
- **BUFFERED 模式**：内存传输 → 解码 → 裁边 → JPEG → 推送

### WebSocket 协议

- 端点: `/ws` (STOMP over WebSocket)
- 心跳: 双向 20s
- 客户端发布: `/app/scan/start`、`/app/scan/status`、`/app/scan/stop` 等
- 服务端推送: `/user/queue/task/{taskId}`（任务进度）、`/user/queue/reply`（命令回复）、`/topic/scanner`（扫描仪状态变更）

### TWAIN 熔断器

超时 15s → OPEN → 冷却 30s → HALF_OPEN → 探测 → CLOSED

### 前端

- 单页应用 `frontend/dist/index.html`（纯静态，无构建工具）
- STOMP.js v7 WebSocket 客户端
- 功能：扫描仪状态、启动扫描、日志、图片画廊（含 Lightbox 预览）、历史文件三层浏览

### 配置文件

| 文件 | 用途 |
|------|------|
| `backend/config/application.yml` | 主配置（端口 8899、扫描模式 FILE、Knife4j） |
| `backend/config/application-dev.yml` | 开发环境（DEBUG 日志、不认证） |
| `backend/config/application-prod.yml` | 生产环境（INFO 日志、JWT 认证、禁用 API 文档） |
| `backend/config/logback.xml` | 按级别分文件日志（debug/info/warn/error）+ 滚动策略 |

## 技术栈

| 层次 | 技术 | 版本 |
|------|------|------|
| 桌面壳 | Tauri | 2.x |
| 后端 | Spring Boot | 3.5.4 (Java 17) |
| 扫描协议 | DTWAIN JNI | 1.9.6 |
| API 文档 | Knife4j | 4.5.0 |
| 实时推送 | STOMP over WebSocket | Spring WebSocket |
| 安装程序 | NSIS | 3.09+ |