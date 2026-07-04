use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::process::{Child, Command};
use std::sync::Mutex;
use tauri::{Emitter, Manager};

struct BackendProcess {
    child: Mutex<Option<Child>>,
}

fn get_backend_dir() -> PathBuf {
    // 从 exe 所在目录查找 backend/ 文件夹
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let dir = parent.join("backend");
            if dir.exists() {
                return dir;
            }
        }
    }
    // 开发模式回退：项目根目录
    PathBuf::from("backend")
}

fn start_backend(backend_dir: &PathBuf) -> Child {
    let java = backend_dir.join("jre/bin/javaw.exe");
    let jar = backend_dir.join("scanner-local-service.jar");
    let lib = backend_dir.join("lib");

    Command::new(&java)
        .args([
            "-Dfile.encoding=UTF-8",
            &format!("-Djava.library.path={}", lib.display()),
            "-Dscanner.auto-open-browser=false",
            "-jar",
            &jar.display().to_string(),
            "--server.port=8899",
        ])
        .current_dir(backend_dir)
        .spawn()
        .expect("无法启动扫描仪服务，请确认 backend/ 目录结构正确")
}

fn wait_for_backend() {
    let max_retries = 60;
    for _ in 0..max_retries {
        if let Ok(mut stream) = TcpStream::connect("127.0.0.1:8899") {
            let mut buf = [0u8; 1024];
            if stream
                .write_all(b"GET /api/scan/health HTTP/1.0\r\n\r\n")
                .is_ok()
                && stream.read(&mut buf).is_ok()
                && buf.starts_with(b"HTTP/1")
            {
                return;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(1000));
    }
    eprintln!("扫描仪服务启动超时（60s），请检查日志");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let backend_dir = get_backend_dir();
            let child = start_backend(&backend_dir);
            app.manage(BackendProcess {
                child: Mutex::new(Some(child)),
            });

            let app_handle = app.handle().clone();
            std::thread::spawn(move || {
                wait_for_backend();
                let _ = app_handle.emit("backend-ready", ());
            });

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                if let Some(state) = window.app_handle().try_state::<BackendProcess>() {
                    if let Ok(mut guard) = state.child.lock() {
                        if let Some(mut child) = guard.take() {
                            let _ = child.kill();
                            let _ = child.wait();
                        }
                    }
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}