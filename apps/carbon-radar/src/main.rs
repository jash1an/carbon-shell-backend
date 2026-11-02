use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::sync::Mutex;
use tokio::time::sleep;

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct NoteItem {
    pub name: String,
    pub path: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ClipboardItem {
    pub id: String,
    pub preview: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AgendaItem {
    pub date: String,
    pub title: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RadarPayload {
    pub vault: Vec<NoteItem>,
    pub clipboard: Vec<ClipboardItem>,
    pub apps: Vec<String>,
    pub agenda: Vec<AgendaItem>,
}

fn scan_markdown_files(dir: &Path, files: &mut Vec<(SystemTime, PathBuf)>) {
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            let file_name = entry.file_name();
            let name_str = file_name.to_string_lossy();
            if name_str.starts_with('.') {
                continue;
            }
            if path.is_dir() {
                scan_markdown_files(&path, files);
            } else if path.is_file() {
                if let Some(ext) = path.extension() {
                    if ext.eq_ignore_ascii_case("md") {
                        let mtime = entry
                            .metadata()
                            .and_then(|m| m.modified())
                            .unwrap_or(SystemTime::UNIX_EPOCH);
                        files.push((mtime, path));
                    }
                }
            }
        }
    }
}

fn fetch_obsidian_notes() -> Vec<NoteItem> {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/shogun".to_string());
    let candidate_dirs = [
        format!("{}/Documents/Obsidian", home),
        format!("{}/Documents/Obsidian Vault", home),
        format!("{}/Obsidian", home),
        format!("{}/Documents", home),
    ];

    let mut found_files = Vec::new();
    for cand in candidate_dirs.iter() {
        let p = Path::new(cand);
        if p.is_dir() {
            scan_markdown_files(p, &mut found_files);
            if !found_files.is_empty() {
                break;
            }
        }
    }

    found_files.sort_by(|a, b| b.0.cmp(&a.0));
    let mut notes = Vec::new();
    let mut seen_paths = HashSet::new();
    for (_, path) in found_files.into_iter().take(20) {
        let path_str = path.to_string_lossy().to_string();
        if seen_paths.insert(path_str.clone()) {
            let name = path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "note.md".to_string());
            notes.push(NoteItem {
                name,
                path: path_str,
            });
        }
    }

    if notes.is_empty() {
        notes.push(NoteItem {
            name: "Welcome.md".to_string(),
            path: format!("{}/Documents/Obsidian/Welcome.md", home),
        });
    }

    notes
}

fn fetch_clipboard() -> Vec<ClipboardItem> {
    let output = Command::new("sh")
        .arg("-c")
        .arg("cliphist list 2>/dev/null | head -n 15")
        .output();

    let mut items = Vec::new();
    if let Ok(out) = output {
        let text = String::from_utf8_lossy(&out.stdout);
        for line in text.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }
            if let Some((id, rest)) = trimmed.split_once('\t') {
                items.push(ClipboardItem {
                    id: id.trim().to_string(),
                    preview: rest.trim().to_string(),
                });
            } else if let Some((id, rest)) = trimmed.split_once(' ') {
                items.push(ClipboardItem {
                    id: id.trim().to_string(),
                    preview: rest.trim().to_string(),
                });
            } else {
                items.push(ClipboardItem {
                    id: "".to_string(),
                    preview: trimmed.to_string(),
                });
            }
        }
    }

    if items.is_empty() {
        items.push(ClipboardItem {
            id: "1".to_string(),
            preview: "Clipboard buffer active".to_string(),
        });
    }

    items
}

fn fetch_agenda() -> Vec<AgendaItem> {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/shogun".to_string());
    let agenda_path = format!("{}/.config/carbon/agenda.json", home);

    if let Ok(content) = fs::read_to_string(&agenda_path) {
        if let Ok(items) = serde_json::from_str::<Vec<AgendaItem>>(&content) {
            if !items.is_empty() {
                return items;
            }
        }
    }

    vec![
        AgendaItem {
            date: "Nov 12".to_string(),
            title: "SAT Prep & Review".to_string(),
        },
        AgendaItem {
            date: "Nov 14".to_string(),
            title: "Carbon Shell Sprint".to_string(),
        },
        AgendaItem {
            date: "Nov 18".to_string(),
            title: "Kernel Timings Check".to_string(),
        },
    ]
}

// ─────────────────────────────────────────────────────────────────────────────
// Hyprland Socket2 IPC & App Usage Tracking
// ─────────────────────────────────────────────────────────────────────────────

fn is_ignored_class(cls: &str) -> bool {
    let lower = cls.trim().to_lowercase();
    lower.is_empty()
        || lower == "nil"
        || lower == "null"
        || lower.contains("quickshell")
        || lower.contains("carbon-shell")
        || lower.contains("xwaylandvideobridge")
        || lower.contains("desktop-portal")
        || lower.contains("hyprlock")
        || lower.contains("rofi")
        || lower.contains("wofi")
        || lower.contains("fuzzel")
}

fn get_usage_file_path() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/shogun".to_string());
    PathBuf::from(home).join(".config/carbon/app_usage.json")
}

fn load_app_usage(path: &Path) -> HashMap<String, u32> {
    if let Ok(content) = fs::read_to_string(path) {
        if let Ok(map) = serde_json::from_str::<HashMap<String, u32>>(&content) {
            return map;
        }
    }
    HashMap::new()
}

fn save_app_usage(path: &Path, tally: &HashMap<String, u32>) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(json_str) = serde_json::to_string_pretty(tally) {
        let tmp_path = path.with_extension("json.tmp");
        if fs::write(&tmp_path, json_str.as_bytes()).is_ok() {
            let _ = fs::rename(&tmp_path, path);
        } else {
            let _ = fs::write(path, json_str.as_bytes());
        }
    }
}

fn seed_from_clients(tally: &mut HashMap<String, u32>) {
    let output = Command::new("hyprctl")
        .arg("clients")
        .arg("-j")
        .output();

    if let Ok(out) = output {
        if let Ok(json_val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
            if let Some(arr) = json_val.as_array() {
                for item in arr {
                    if let Some(cls) = item.get("class").and_then(|c| c.as_str()) {
                        let trimmed = cls.trim();
                        if !is_ignored_class(trimmed) {
                            tally.entry(trimmed.to_string()).or_insert(1);
                        }
                    }
                }
            }
        }
    }
}

fn find_socket2_path() -> Option<PathBuf> {
    // 1. Signature-based lookup in XDG_RUNTIME_DIR and /tmp
    if let Ok(sig) = env::var("HYPRLAND_INSTANCE_SIGNATURE") {
        if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
            let p = PathBuf::from(&xdg).join("hypr").join(&sig).join(".socket2.sock");
            if p.exists() {
                return Some(p);
            }
        }
        let p = PathBuf::from("/tmp/hypr").join(&sig).join(".socket2.sock");
        if p.exists() {
            return Some(p);
        }
    }

    // 2. Scan XDG_RUNTIME_DIR/hypr/*/
    if let Ok(xdg) = env::var("XDG_RUNTIME_DIR") {
        let hypr_dir = PathBuf::from(&xdg).join("hypr");
        if let Ok(entries) = fs::read_dir(hypr_dir) {
            for entry in entries.flatten() {
                let p = entry.path().join(".socket2.sock");
                if p.exists() {
                    return Some(p);
                }
            }
        }
    }

    // 3. Scan /tmp/hypr/*/
    let tmp_hypr = Path::new("/tmp/hypr");
    if let Ok(entries) = fs::read_dir(tmp_hypr) {
        for entry in entries.flatten() {
            let p = entry.path().join(".socket2.sock");
            if p.exists() {
                return Some(p);
            }
        }
    }

    None
}

async fn start_ipc_listener(
    tally: Arc<Mutex<HashMap<String, u32>>>,
    usage_path: PathBuf,
) {
    let mut last_active = String::new();

    loop {
        if let Some(sock_path) = find_socket2_path() {
            if let Ok(stream) = tokio::net::UnixStream::connect(&sock_path).await {
                let mut reader = BufReader::new(stream).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    let trimmed = line.trim();
                    let mut class_to_record = None;

                    if let Some(payload) = trimmed.strip_prefix("activewindow>>") {
                        let class = payload.split(',').next().unwrap_or("").trim();
                        if is_ignored_class(class) {
                            last_active.clear();
                        } else if class != last_active {
                            last_active = class.to_string();
                            class_to_record = Some(class.to_string());
                        }
                    } else if let Some(payload) = trimmed.strip_prefix("openwindow>>") {
                        let parts: Vec<&str> = payload.splitn(4, ',').collect();
                        if parts.len() >= 3 {
                            let class = parts[2].trim();
                            if !is_ignored_class(class) {
                                class_to_record = Some(class.to_string());
                            }
                        }
                    }

                    if let Some(cls) = class_to_record {
                        let mut map = tally.lock().await;
                        let count = map.entry(cls).or_insert(0);
                        *count += 1;
                        save_app_usage(&usage_path, &map);
                    }
                }
            }
        }

        sleep(Duration::from_secs(2)).await;
    }
}

fn get_top_apps(tally: &HashMap<String, u32>) -> Vec<String> {
    let mut entries: Vec<(&String, &u32)> = tally.iter().collect();
    entries.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
    entries.into_iter().take(5).map(|(k, _)| k.clone()).collect()
}

async fn build_payload(tally: &Arc<Mutex<HashMap<String, u32>>>) -> RadarPayload {
    let apps = {
        let map = tally.lock().await;
        get_top_apps(&map)
    };

    RadarPayload {
        vault: fetch_obsidian_notes(),
        clipboard: fetch_clipboard(),
        apps,
        agenda: fetch_agenda(),
    }
}

fn emit_payload(payload: &RadarPayload) {
    if let Ok(serialized) = serde_json::to_string(payload) {
        let mut stdout = std::io::stdout();
        let _ = writeln!(stdout, "{}", serialized);
        let _ = stdout.flush();
    }
}

#[tokio::main]
async fn main() {
    let usage_path = get_usage_file_path();
    let mut initial_tally = load_app_usage(&usage_path);

    // If no previous history exists, seed initial entries from currently open clients
    if initial_tally.is_empty() {
        seed_from_clients(&mut initial_tally);
        if !initial_tally.is_empty() {
            save_app_usage(&usage_path, &initial_tally);
        }
    }

    let tally = Arc::new(Mutex::new(initial_tally));

    // Spawn Hyprland socket2 IPC listener in background
    let listener_tally = Arc::clone(&tally);
    let listener_path = usage_path.clone();
    tokio::spawn(async move {
        start_ipc_listener(listener_tally, listener_path).await;
    });

    let mut stdin_reader = BufReader::new(tokio::io::stdin()).lines();
    let mut ticker = tokio::time::interval(Duration::from_secs(2));

    // Emit initial payload immediately
    let initial = build_payload(&tally).await;
    emit_payload(&initial);

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                let payload = build_payload(&tally).await;
                emit_payload(&payload);
            }
            line = stdin_reader.next_line() => {
                match line {
                    Ok(Some(_)) => {
                        let payload = build_payload(&tally).await;
                        emit_payload(&payload);
                    }
                    Ok(None) => {
                        // EOF on stdin, continue on ticker
                        sleep(Duration::from_millis(100)).await;
                    }
                    Err(_) => {
                        sleep(Duration::from_millis(500)).await;
                    }
                }
            }
        }
    }
}
