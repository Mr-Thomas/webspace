@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

cd /d "%~dp0"
echo ============================================
echo  扫描仪管理系统 — 开发构建
echo  Scanner System 2.0.0 (dev)
echo ============================================

REM ---------- 1. 构建后端 ----------
echo [1/3] 构建 Spring Boot 后端...
set BACKEND_SRC=D:\workspace\scanner-local-service
pushd %BACKEND_SRC%
call mvn clean package -DskipTests -q
if errorlevel 1 (
    echo 后端构建失败！
    popd
    exit /b 1
)
popd

echo [1/3] 组装后端发行包（jar + jlink JRE + 配置）...
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

echo [1/3] 复制后端到 scanner-system/backend/...
if exist backend rmdir /s /q backend
mkdir backend
xcopy /E /I /Q "%DIST_DIR%\*" backend\ >nul
if errorlevel 1 (
    echo 后端复制失败！
    exit /b 1
)
echo 后端就绪

REM ---------- 2. 验证前端 ----------
echo [2/3] 验证前端资源...
if not exist frontend\dist\index.html (
    echo 警告：frontend\dist 中未找到 index.html！
    echo 请确保前端已构建完成
) else (
    echo 前端就绪
)

REM ---------- 3. 构建 Tauri 壳 ----------
echo [3/3] 构建 Tauri 桌面壳...

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

echo.
echo ===== 开发构建完成 =====
echo 可执行文件: tauri\src-tauri\target\release\scanner-client.exe
echo 后端代码:    backend\
echo.
echo 提示：运行 build-release.bat 可打包为 NSIS 安装程序
pause