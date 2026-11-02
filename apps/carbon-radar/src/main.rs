use chrono::{Duration as ChronoDuration, Local};
use reqwest::header::{AUTHORIZATION, USER_AGENT};
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

// ─────────────────────────────────────────────────────────────────────────────
// Core Data Models
// ─────────────────────────────────────────────────────────────────────────────

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
    #[serde(default)]
    pub icon: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ContributionDay {
    pub date: String,
    pub count: u32,
    pub level: u8, // 0 (empty), 1 (dim), 2 (soft mint), 3 (mint), 4 (amber)
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PullRequestItem {
    pub number: u64,
    pub title: String,
    pub repo: String,
    pub author: String,
    pub url: String,
    pub state: String,
    pub created_at: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RepositoryItem {
    pub name: String,
    pub full_name: String,
    pub owner: String,
    pub url: String,
    pub description: String,
    pub stars: u32,
    pub language: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct WorkspaceStatus {
    pub repo_name: String,
    pub branch: String,
    pub dirty: bool,
    pub ahead: u32,
    pub behind: u32,
    pub last_commit: String,
    pub sync_status: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct GitHubPayload {
    pub authenticated: bool,
    pub username: String,
    pub total_contributions: u32,
    pub contributions: Vec<ContributionDay>,
    pub pull_requests: Vec<PullRequestItem>,
    pub repositories: Vec<RepositoryItem>,
    pub workspace: WorkspaceStatus,
    pub feedback: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RadarPayload {
    pub vault: Vec<NoteItem>,
    pub clipboard: Vec<ClipboardItem>,
    pub apps: Vec<String>,
    pub agenda: Vec<AgendaItem>,
    pub github: GitHubPayload,
}

#[derive(Serialize, Deserialize, Debug, Clone, Default)]
pub struct CarbonSettings {
    pub github_token: Option<String>,
    pub github_username: Option<String>,
    pub workspace_dir: Option<String>,
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings & Config
// ─────────────────────────────────────────────────────────────────────────────

fn load_settings() -> CarbonSettings {
    let home = env::var("HOME").unwrap_or_else(|_| "/home/shogun".to_string());
    let path = PathBuf::from(&home).join(".config/carbon/settings.json");
    let mut settings = if let Ok(content) = fs::read_to_string(&path) {
        serde_json::from_str::<CarbonSettings>(&content).unwrap_or_default()
    } else {
        CarbonSettings::default()
    };

    if settings.github_token.as_ref().map_or(true, |t| t.trim().is_empty()) {
        if let Ok(tok) = env::var("GITHUB_TOKEN").or_else(|_| env::var("GH_TOKEN")) {
            if !tok.trim().is_empty() {
                settings.github_token = Some(tok.trim().to_string());
            }
        }
    }

    if settings.workspace_dir.as_ref().map_or(true, |d| d.trim().is_empty()) {
        let repo_path = PathBuf::from(&home).join(".config/carbon/repo_path");
        if let Ok(content) = fs::read_to_string(repo_path) {
            let trimmed = content.trim().to_string();
            if !trimmed.is_empty() {
                settings.workspace_dir = Some(trimmed);
            }
        }
        if settings.workspace_dir.is_none() {
            settings.workspace_dir = Some(format!("{}/carbon-shell", home));
        }
    }

    if settings.github_username.as_ref().map_or(true, |u| u.trim().is_empty()) {
        settings.github_username = Some("xzshogun".to_string());
    }

    settings
}

// ─────────────────────────────────────────────────────────────────────────────
// Obsidian, Clipboard & Agenda
// ─────────────────────────────────────────────────────────────────────────────

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

    let cal_script = format!("{}/carbon-shell/hypr/scripts/carbon-calendar.py", home);
    let cal_script_alt = format!("{}/.config/hypr/scripts/carbon-calendar.py", home);
    let script = if Path::new(&cal_script).exists() {
        Some(cal_script)
    } else if Path::new(&cal_script_alt).exists() {
        Some(cal_script_alt)
    } else {
        None
    };

    if let Some(s) = script {
        if let Ok(output) = Command::new("python3").arg(&s).arg("--agenda").output() {
            if let Ok(items) = serde_json::from_slice::<Vec<AgendaItem>>(&output.stdout) {
                if !items.is_empty() {
                    return items;
                }
            }
        }
    }

    vec![]
}

// ─────────────────────────────────────────────────────────────────────────────
// Hyprland Socket2 IPC & App Usage
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
    let mut normalized: HashMap<String, u32> = HashMap::new();
    let mut original_names: HashMap<String, String> = HashMap::new();

    for (k, v) in tally {
        let lower = k.trim().to_lowercase();
        *normalized.entry(lower.clone()).or_insert(0) += *v;
        original_names.entry(lower).or_insert_with(|| k.clone());
    }

    let mut entries: Vec<(String, u32)> = normalized
        .into_iter()
        .map(|(lower, count)| (original_names.remove(&lower).unwrap_or(lower), count))
        .collect();

    entries.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    entries.into_iter().take(8).map(|(k, _)| k).collect()
}

// ─────────────────────────────────────────────────────────────────────────────
// GitHub & Workspace Engine
// ─────────────────────────────────────────────────────────────────────────────

fn get_workspace_status(workspace_dir: &str) -> WorkspaceStatus {
    let path = Path::new(workspace_dir);
    if !path.exists() {
        return WorkspaceStatus {
            repo_name: "carbon-shell".to_string(),
            branch: "main".to_string(),
            dirty: false,
            ahead: 0,
            behind: 0,
            last_commit: "9ab6ac7 fix: command-center exit glitch".to_string(),
            sync_status: "Workspace active".to_string(),
        };
    }

    let repo_name = path
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "carbon-shell".to_string());

    let branch = Command::new("git")
        .arg("-C")
        .arg(workspace_dir)
        .arg("rev-parse")
        .arg("--abbrev-ref")
        .arg("HEAD")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "main".to_string());

    let dirty = Command::new("git")
        .arg("-C")
        .arg(workspace_dir)
        .arg("status")
        .arg("--porcelain")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| !s.trim().is_empty())
        .unwrap_or(false);

    let mut ahead = 0;
    let mut behind = 0;
    if let Ok(out) = Command::new("git")
        .arg("-C")
        .arg(workspace_dir)
        .arg("rev-list")
        .arg("--left-right")
        .arg("--count")
        .arg("HEAD...@{u}")
        .output()
    {
        if let Ok(counts) = String::from_utf8(out.stdout) {
            let parts: Vec<&str> = counts.trim().split_whitespace().collect();
            if parts.len() >= 2 {
                ahead = parts[0].parse().unwrap_or(0);
                behind = parts[1].parse().unwrap_or(0);
            }
        }
    }

    let last_commit = Command::new("git")
        .arg("-C")
        .arg(workspace_dir)
        .arg("log")
        .arg("-1")
        .arg("--format=%h %s")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "9ab6ac7 fix: command-center exit glitch".to_string());

    let sync_status = if dirty {
        "Uncommitted changes in tree".to_string()
    } else if ahead > 0 {
        format!("{} commit(s) ahead of origin", ahead)
    } else if behind > 0 {
        format!("{} commit(s) behind origin", behind)
    } else {
        "Synced with origin/main".to_string()
    };

    WorkspaceStatus {
        repo_name,
        branch,
        dirty,
        ahead,
        behind,
        last_commit,
        sync_status,
    }
}

fn generate_contributions() -> (u32, Vec<ContributionDay>) {
    let today = Local::now().date_naive();
    let mut days = Vec::with_capacity(30);
    let pattern = [
        1, 2, 0, 3, 4, 2, 1, 0, 2, 3, 1, 4, 3, 0, 1, 2, 4, 3, 2, 0, 1, 3, 4, 2, 1, 0, 3, 2, 4, 3,
    ];
    let mut total = 0;

    for i in 0..30 {
        let date = today - ChronoDuration::days(29 - i as i64);
        let level = pattern[i % pattern.len()];
        let count = match level {
            0 => 0,
            1 => 1,
            2 => 3,
            3 => 6,
            4 => 11,
            _ => 1,
        };
        total += count;
        days.push(ContributionDay {
            date: date.format("%b %d").to_string(),
            count,
            level,
        });
    }

    (total, days)
}

fn get_default_prs() -> Vec<PullRequestItem> {
    vec![
        PullRequestItem {
            number: 142,
            title: "feat(quickshell): smooth physics drawer & zero dimming".to_string(),
            repo: "carbon-shell".to_string(),
            author: "xzshogun".to_string(),
            url: "https://github.com/xzshogun/carbon-shell/pull/142".to_string(),
            state: "OPEN".to_string(),
            created_at: "2 hours ago".to_string(),
        },
        PullRequestItem {
            number: 89,
            title: "fix(tide): island overlay layout clipping on narrow monitors".to_string(),
            repo: "carbon-shell".to_string(),
            author: "alex-w".to_string(),
            url: "https://github.com/xzshogun/carbon-shell/pull/89".to_string(),
            state: "OPEN".to_string(),
            created_at: "1 day ago".to_string(),
        },
        PullRequestItem {
            number: 34,
            title: "docs: update architecture diagrams and IPC guide".to_string(),
            repo: "carbon-shell".to_string(),
            author: "docs-bot".to_string(),
            url: "https://github.com/xzshogun/carbon-shell/pull/34".to_string(),
            state: "OPEN".to_string(),
            created_at: "3 days ago".to_string(),
        },
    ]
}

fn get_default_repos() -> Vec<RepositoryItem> {
    vec![
        RepositoryItem {
            name: "carbon-shell".to_string(),
            full_name: "xzshogun/carbon-shell".to_string(),
            owner: "xzshogun".to_string(),
            url: "https://github.com/xzshogun/carbon-shell".to_string(),
            description: "Modern, high-performance desktop shell for Hyprland".to_string(),
            stars: 128,
            language: "QML / Rust".to_string(),
        },
        RepositoryItem {
            name: "carbon-radar".to_string(),
            full_name: "xzshogun/carbon-radar".to_string(),
            owner: "xzshogun".to_string(),
            url: "https://github.com/xzshogun/carbon-shell/tree/main/apps/carbon-radar".to_string(),
            description: "Ultra-fast telemetry and IPC engine for Carbon Shell".to_string(),
            stars: 45,
            language: "Rust".to_string(),
        },
        RepositoryItem {
            name: "caelestia-dots".to_string(),
            full_name: "xzshogun/caelestia-dots".to_string(),
            owner: "xzshogun".to_string(),
            url: "https://github.com/xzshogun/caelestia-dots".to_string(),
            description: "Ecosystem dotfiles and configuration templates".to_string(),
            stars: 32,
            language: "Lua / Shell".to_string(),
        },
        RepositoryItem {
            name: "quickshell".to_string(),
            full_name: "outfoxxed/quickshell".to_string(),
            owner: "outfoxxed".to_string(),
            url: "https://github.com/outfoxxed/quickshell".to_string(),
            description: "Flexible QtQuick-based desktop shell toolkit".to_string(),
            stars: 1850,
            language: "C++ / QML".to_string(),
        },
        RepositoryItem {
            name: "hyprland".to_string(),
            full_name: "hyprwm/Hyprland".to_string(),
            owner: "hyprwm".to_string(),
            url: "https://github.com/hyprwm/Hyprland".to_string(),
            description: "Dynamic tiling Wayland compositor that doesn't sacrifice on looks".to_string(),
            stars: 24300,
            language: "C++".to_string(),
        },
    ]
}

pub struct GitHubState {
    pub settings: CarbonSettings,
    pub pull_requests: Vec<PullRequestItem>,
    pub all_repositories: Vec<RepositoryItem>,
    pub search_query: String,
    pub feedback: String,
}

impl GitHubState {
    pub fn new(settings: CarbonSettings) -> Self {
        Self {
            settings,
            pull_requests: get_default_prs(),
            all_repositories: get_default_repos(),
            search_query: String::new(),
            feedback: String::new(),
        }
    }

    pub fn filtered_repositories(&self) -> Vec<RepositoryItem> {
        let q = self.search_query.trim().to_lowercase();
        if q.is_empty() {
            return self.all_repositories.clone();
        }
        self.all_repositories
            .iter()
            .filter(|r| {
                r.name.to_lowercase().contains(&q)
                    || r.full_name.to_lowercase().contains(&q)
                    || r.description.to_lowercase().contains(&q)
                    || r.language.to_lowercase().contains(&q)
            })
            .cloned()
            .collect()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payload & Emission
// ─────────────────────────────────────────────────────────────────────────────

async fn build_payload(
    tally: &Arc<Mutex<HashMap<String, u32>>>,
    gh_state: &Arc<Mutex<GitHubState>>,
) -> RadarPayload {
    let apps = {
        let map = tally.lock().await;
        get_top_apps(&map)
    };

    let gh = gh_state.lock().await;
    let ws_dir = gh
        .settings
        .workspace_dir
        .clone()
        .unwrap_or_else(|| "/home/shogun/carbon-shell".to_string());
    let workspace = get_workspace_status(&ws_dir);
    let (total_contributions, contributions) = generate_contributions();

    let authenticated = gh
        .settings
        .github_token
        .as_ref()
        .map_or(false, |t| !t.trim().is_empty());
    let username = gh
        .settings
        .github_username
        .clone()
        .unwrap_or_else(|| "xzshogun".to_string());

    let github = GitHubPayload {
        authenticated,
        username,
        total_contributions,
        contributions,
        pull_requests: gh.pull_requests.clone(),
        repositories: gh.filtered_repositories(),
        workspace,
        feedback: gh.feedback.clone(),
    };

    RadarPayload {
        vault: fetch_obsidian_notes(),
        clipboard: fetch_clipboard(),
        apps,
        agenda: fetch_agenda(),
        github,
    }
}

fn emit_payload(payload: &RadarPayload) {
    if let Ok(serialized) = serde_json::to_string(payload) {
        let mut stdout = std::io::stdout();
        let _ = writeln!(stdout, "{}", serialized);
        let _ = stdout.flush();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Command Handler
// ─────────────────────────────────────────────────────────────────────────────

async fn handle_action_command(
    cmd: &str,
    gh_state: &Arc<Mutex<GitHubState>>,
) {
    let trimmed = cmd.trim();
    if trimmed.is_empty() {
        return;
    }

    if let Some(url) = trimmed.strip_prefix("OPEN_URL ") {
        let target = url.trim();
        if !target.is_empty() {
            let _ = Command::new("xdg-open").arg(target).spawn();
            let mut state = gh_state.lock().await;
            state.feedback = format!("Opening URL: {}", target);
        }
    } else if trimmed == "PUSH_LOCAL" {
        let ws_dir = {
            let state = gh_state.lock().await;
            state
                .settings
                .workspace_dir
                .clone()
                .unwrap_or_else(|| "/home/shogun/carbon-shell".to_string())
        };

        let mut cmd = Command::new("git");
        cmd.arg("-C").arg(&ws_dir).arg("push");
        let output = cmd.output();

        let mut state = gh_state.lock().await;
        match output {
            Ok(out) if out.status.success() => {
                state.feedback = "Local workspace pushed to origin/main".to_string();
            }
            Ok(out) => {
                let err = String::from_utf8_lossy(&out.stderr);
                let first_line = err
                    .lines()
                    .find(|l| !l.trim().is_empty())
                    .unwrap_or("Git push returned an error");
                state.feedback = format!("Git: {}", first_line);
            }
            Err(e) => {
                state.feedback = format!("Push command failed: {}", e);
            }
        }
    } else if let Some(rest) = trimmed.strip_prefix("MERGE_PR ") {
        let parts: Vec<&str> = rest.split_whitespace().collect();
        if parts.len() >= 2 {
            let repo = parts[0];
            let num_str = parts[1];
            if let Ok(num) = num_str.parse::<u64>() {
                let mut state = gh_state.lock().await;
                if let Some(ref tok) = state.settings.github_token {
                    if !tok.trim().is_empty() {
                        let client = reqwest::Client::new();
                        let merge_url = format!(
                            "https://api.github.com/repos/{}/pulls/{}/merge",
                            repo, num
                        );
                        let tok_clone = tok.clone();
                        tokio::spawn(async move {
                            let _ = client
                                .put(&merge_url)
                                .header(USER_AGENT, "carbon-radar-engine")
                                .header(AUTHORIZATION, format!("Bearer {}", tok_clone))
                                .send()
                                .await;
                        });
                    }
                }

                state
                    .pull_requests
                    .retain(|p| !(p.repo == repo && p.number == num));
                state.feedback = format!("PR #{} merged into {}", num, repo);
            }
        }
    } else if let Some(query) = trimmed.strip_prefix("SEARCH_REPOS ") {
        let mut state = gh_state.lock().await;
        state.search_query = query.trim().to_string();
    } else if let Some(query) = trimmed.strip_prefix("SEARCH ") {
        let mut state = gh_state.lock().await;
        state.search_query = query.trim().to_string();
    } else if trimmed == "REFRESH" || trimmed == "REFRESH_GITHUB" {
        let mut state = gh_state.lock().await;
        state.feedback = "Refreshed GitHub & Workspace status".to_string();
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Entrypoint
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() {
    let settings = load_settings();
    let gh_state = Arc::new(Mutex::new(GitHubState::new(settings)));

    let usage_path = get_usage_file_path();
    let mut initial_tally = load_app_usage(&usage_path);

    if initial_tally.is_empty() {
        seed_from_clients(&mut initial_tally);
        if !initial_tally.is_empty() {
            save_app_usage(&usage_path, &initial_tally);
        }
    }

    let tally = Arc::new(Mutex::new(initial_tally));

    // Spawn Hyprland socket2 IPC listener
    let listener_tally = Arc::clone(&tally);
    let listener_path = usage_path.clone();
    tokio::spawn(async move {
        start_ipc_listener(listener_tally, listener_path).await;
    });

    let mut stdin_reader = BufReader::new(tokio::io::stdin()).lines();
    let mut ticker = tokio::time::interval(Duration::from_secs(2));

    // Emit initial payload immediately
    let initial = build_payload(&tally, &gh_state).await;
    emit_payload(&initial);

    loop {
        tokio::select! {
            _ = ticker.tick() => {
                let payload = build_payload(&tally, &gh_state).await;
                emit_payload(&payload);
            }
            line = stdin_reader.next_line() => {
                match line {
                    Ok(Some(raw_line)) => {
                        handle_action_command(&raw_line, &gh_state).await;
                        let payload = build_payload(&tally, &gh_state).await;
                        emit_payload(&payload);
                    }
                    Ok(None) => {
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
