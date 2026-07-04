@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cd /d "%~dp0"
set PRODUCT_VERSION=2.0.0
echo ============================================
echo  扫描仪管理系统 — 发行版构建
echo  Scanner System %PRODUCT_VERSION%
echo ============================================

REM ---------- 1. 构建后端 ----------
echo [1/5] 构建 Spring Boot 后端...
set BACKEND_SRC=D:\workspace\scanner-local-service
pushd %BACKEND_SRC%
call mvn clean package -DskipTests -q
if errorlevel 1 (
    echo 后端构建失败！
    popd
    exit /b 1
)
popd

echo [1/5] 组装后端发行包（jar + jlink JRE + 配置）...
set DIST_DIR=%BACKEND_SRC%\dist\scanner-local-service
if exist "%DIST_DIR%" rmdir /s /q "%DIST_DIR%"
mkdir "%DIST_DIR%\lib" "%DIST_DIR%\config" "%DIST_DIR%\logs" 2>nul

REM jlink 裁剪 JRE（约 40MB）
if not "%JAVA_HOME%"=="" (
    if exist "%JAVA_HOME%\bin\jlink.exe" (
        "%JAVA_HOME%\bin\jlink.exe" ^
            --add-modules java.base,java.logging,java.xml,jdk.unsupported,java.management,java.security.jgss,java.instrument,java.naming,java.desktop,java.sql,java.scripting,java.prefs,java.security.sasl,jdk.management,jdk.crypto.ec,jdk.crypto.cryptoki,jdk.naming.dns,jdk.zipfs,java.compiler,jdk.management.agent ^
            --output "%DIST_DIR%\jre" ^
            --strip-debug --compress=2 --no-header-files --no-man-pages >nul 2>&1
        if !errorlevel! equ 0 (echo         jlink JRE 就绪) else (echo         jlink 失败，将使用系统 JRE)
    ) else (
        echo         JAVA_HOME 中未找到 jlink.exe，跳过裁剪 JRE
    )
) else (
    echo         JAVA_HOME 未设置，跳过裁剪 JRE
)

REM 复制构建产物和本地库
copy /y "%BACKEND_SRC%\target\scanner-local-service.jar" "%DIST_DIR%\" >nul || (echo JAR 未找到！& exit /b 1)
copy /y "%BACKEND_SRC%\lib\*.dll" "%DIST_DIR%\lib\" >nul 2>&1
copy /y "%BACKEND_SRC%\lib\dtwainjni.info" "%DIST_DIR%\lib\" >nul 2>&1
copy /y "%BACKEND_SRC%\lib\*.txt" "%DIST_DIR%\lib\" >nul 2>&1
copy /y "%BACKEND_SRC%\lib\*.INI" "%DIST_DIR%\lib\" >nul 2>&1
copy /y "%BACKEND_SRC%\src\main\resources\application*.yml" "%DIST_DIR%\config\" >nul 2>&1
copy /y "%BACKEND_SRC%\src\main\resources\logback.xml" "%DIST_DIR%\config\" >nul 2>&1

echo [1/5] 复制后端到 scanner-system/backend/...
if exist backend rmdir /s /q backend
mkdir backend
xcopy /E /I /Q "%DIST_DIR%\*" backend\ >nul
if errorlevel 1 (
    echo 后端复制失败！
    exit /b 1
)
echo 后端就绪

REM ---------- 2. 前端 ----------
echo [2/5] 验证前端资源...
if not exist frontend\dist\index.html (
    echo 警告：frontend\dist 中未找到 index.html！
    echo 请确保前端已构建完成（Vite build）
) else (
    echo 前端就绪
)

REM ---------- 3. 构建 Tauri 壳 ----------
echo [3/5] 构建 Tauri 桌面壳...

REM 确保 Cargo 在 PATH 中（PowerShell → CMD 可能丢失）
where cargo >nul 2>&1 || set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

pushd tauri
if not exist node_modules (
    call npm install
)
call npx tauri build
if errorlevel 1 (
    echo Tauri 构建失败！
    popd
    exit /b 1
)
popd
echo Tauri 构建完成

REM ---------- 4. 准备 WebView2 离线包（固定版本） ----------
echo [4/5] 准备 WebView2 离线安装包...
set WV2_DIR=installer\runtime
set WV2_FILE=%WV2_DIR%\WebView2Offline.exe
if not exist %WV2_DIR% mkdir %WV2_DIR%
if not exist %WV2_FILE% (
    echo 正在下载 WebView2 Runtime（130MB）到 %WV2_FILE%...
    curl -sL -o %WV2_FILE% "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
    if errorlevel 1 (
        echo 下载失败！请手动下载后放入 %WV2_FILE%
        echo 下载地址: https://go.microsoft.com/fwlink/p/?LinkId=2124703
        pause
        exit /b 1
    ) else (
        echo WebView2 下载完成
    )
) else (
    echo WebView2 离线包已存在：%WV2_FILE%
)

REM ---------- 5. 编译 NSIS 安装程序 ----------
echo [5/5] 编译安装程序...
set NSIS="C:\Program Files (x86)\NSIS\makensis.exe"
if not exist %NSIS% (
    echo NSIS 未安装！请先安装 NSIS 3.09+
    exit /b 1
)

pushd installer
%NSIS% installer.nsi
if errorlevel 1 (
    echo NSIS 编译失败！
    popd
    exit /b 1
)
popd

REM ---------- 完成 ----------
echo.
echo ===== 构建完成 =====
for %%f in (release\Scanner_%PRODUCT_VERSION%_x64-setup.exe) do (
    set FILESIZE=%%~zf
)
echo 安装包: release\Scanner_%PRODUCT_VERSION%_x64-setup.exe
if defined FILESIZE (
    echo 大小:     !FILESIZE! 字节
)
echo.
echo 目录结构:
echo   backend/         - Spring Boot + JRE
echo   frontend/        - 前端页面（已嵌入 Tauri binary）
echo   tauri/           - Rust 桌面壳
echo   installer/       - NSIS 安装脚本 + runtime/WebView2Offline.exe
echo   release/         - 最终安装包（含 WebView2）
echo.
echo 内网部署: 将 release\Scanner_*.exe 拷贝至目标机器运行即可
echo           WebView2 已嵌入安装包，无需额外文件
pause\r