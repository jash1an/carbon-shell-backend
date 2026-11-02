use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime};
use tokio::io::{AsyncBufReadExt, BufReader};
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

fn fetch_system_radar() -> Vec<String> {
    let output = Command::new("hyprctl")
        .arg("clients")
        .arg("-j")
        .output();

    let mut apps = Vec::new();
    let mut seen = HashSet::new();

    if let Ok(out) = output {
        if let Ok(json_val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
            if let Some(arr) = json_val.as_array() {
                for item in arr {
                    if let Some(cls) = item.get("class").and_then(|c| c.as_str()) {
                        let trimmed = cls.trim();
                        if !trimmed.is_empty() && seen.insert(trimmed.to_string()) {
                            apps.push(trimmed.to_string());
                        }
                    }
                }
            }
        }
    }

    if apps.is_empty() {
        apps.push("hyprland".to_string());
    }

    apps
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

fn build_payload() -> RadarPayload {
    RadarPayload {
        vault: fetch_obsidian_notes(),
        clipboard: fetch_clipboard(),
        apps: fetch_system_radar(),
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
    let mut stdin_reader = BufReader::new(tokio::io::stdin()).lines();
    let mut ticker = tokio::time::interval(Duration::from_secs(2));

    // Emit initial payload immediately
    let initial = build_payload();
    emit_payload(&initial);

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                let payload = build_payload();
                emit_payload(&payload);
            }
            line = stdin_reader.next_line() => {
                match line {
                    Ok(Some(_)) => {
                        let payload = build_payload();
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
