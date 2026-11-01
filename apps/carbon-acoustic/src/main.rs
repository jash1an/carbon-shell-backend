const CLAP_THRESHOLD: f32 = 0.8; // User will lower this based on debug output
const DEBUG_THRESHOLD: f32 = 0.1; // Print any sound louder than this

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::env;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use sysinfo::{ProcessExt, System, SystemExt};
use tokio::io::{AsyncBufReadExt, BufReader};

pub fn handle_double_clap() {
    let mut sys = System::new_all();
    sys.refresh_processes();

    let mut is_secure_lock_active = false;

    // Check if hyprlock is currently running
    for (_pid, process) in sys.processes() {
        if process.name().to_lowercase().contains("hyprlock") {
            is_secure_lock_active = true;
            break;
        }
    }

    if is_secure_lock_active {
        // SECURE MODE: Do NOT bypass the password. Just wake the display.
        println!("Double-clap detected, but hyprlock is active. Waking monitors only.");
        std::process::Command::new("sh")
            .arg("-c")
            .arg("hyprctl dispatch dpms on")
            .spawn()
            .ok();
    } else {
        // CAIRO IDLE MODE: Safe to wake and fully dismiss screensaver.
        println!("Double-clap detected. Waking system and dismissing Cairo.");
        std::process::Command::new("sh")
            .arg("-c")
            .arg("hyprctl dispatch dpms on && (sh $HOME/.config/hypr/scripts/carbon-ipc.sh unlock || killall cairo-idle 2>/dev/null)")
            .spawn()
            .ok();
    }
}

struct ClapDetector {
    last_clap: Option<Instant>,
    cooldown_until: Instant,
}

impl ClapDetector {
    fn new() -> Self {
        Self {
            last_clap: None,
            cooldown_until: Instant::now(),
        }
    }

    fn record_clap(&mut self) -> bool {
        let now = Instant::now();
        if now < self.cooldown_until {
            return false;
        }

        if let Some(first_clap) = self.last_clap {
            let elapsed = now.duration_since(first_clap);
            if elapsed >= Duration::from_millis(150) && elapsed <= Duration::from_millis(750) {
                // Double clap detected!
                self.last_clap = None;
                self.cooldown_until = now + Duration::from_millis(1000);
                return true;
            } else if elapsed > Duration::from_millis(750) {
                // Reset to this new clap as first clap
                self.last_clap = Some(now);
            }
        } else {
            self.last_clap = Some(now);
        }
        false
    }
}

fn start_audio_capture(
    running: Arc<AtomicBool>,
    detector: Arc<Mutex<ClapDetector>>,
) -> Result<cpal::Stream, String> {
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .expect("FATAL: No default input device found by cpal.");
    println!(
        "SUCCESS: Listening to microphone: {}",
        device.name().unwrap_or_else(|_| "Unknown".to_string())
    );

    let config = device
        .default_input_config()
        .map_err(|e| format!("Failed to get default input config: {e}"))?;

    let err_fn = |err| eprintln!("Audio stream error: {err}");

    let detector_clone = Arc::clone(&detector);
    let running_clone = Arc::clone(&running);

    let stream = match config.sample_format() {
        cpal::SampleFormat::F32 => device
            .build_input_stream(
                &config.into(),
                move |data: &[f32], _: &_| {
                    if !running_clone.load(Ordering::Relaxed) {
                        return;
                    }
                    let peak = data.iter().map(|&s| s.abs()).fold(0.0f32, f32::max);
                    if peak > DEBUG_THRESHOLD {
                        println!("Noise detected! Peak amplitude: {:.4}", peak);
                    }
                    if peak > CLAP_THRESHOLD {
                        let mut det = detector_clone.lock().unwrap();
                        if det.record_clap() {
                            drop(det);
                            handle_double_clap();
                        }
                    }
                },
                err_fn,
                None,
            )
            .map_err(|e| format!("Failed to build input stream: {e}"))?,
        cpal::SampleFormat::I16 => device
            .build_input_stream(
                &config.into(),
                move |data: &[i16], _: &_| {
                    if !running_clone.load(Ordering::Relaxed) {
                        return;
                    }
                    let peak = data
                        .iter()
                        .map(|&s| (s as f32 / i16::MAX as f32).abs())
                        .fold(0.0f32, f32::max);
                    if peak > DEBUG_THRESHOLD {
                        println!("Noise detected! Peak amplitude: {:.4}", peak);
                    }
                    if peak > CLAP_THRESHOLD {
                        let mut det = detector_clone.lock().unwrap();
                        if det.record_clap() {
                            drop(det);
                            handle_double_clap();
                        }
                    }
                },
                err_fn,
                None,
            )
            .map_err(|e| format!("Failed to build input stream: {e}"))?,
        cpal::SampleFormat::U16 => device
            .build_input_stream(
                &config.into(),
                move |data: &[u16], _: &_| {
                    if !running_clone.load(Ordering::Relaxed) {
                        return;
                    }
                    let peak = data
                        .iter()
                        .map(|&s| {
                            ((s as f32 - u16::MAX as f32 / 2.0) / (u16::MAX as f32 / 2.0)).abs()
                        })
                        .fold(0.0f32, f32::max);
                    if peak > DEBUG_THRESHOLD {
                        println!("Noise detected! Peak amplitude: {:.4}", peak);
                    }
                    if peak > CLAP_THRESHOLD {
                        let mut det = detector_clone.lock().unwrap();
                        if det.record_clap() {
                            drop(det);
                            handle_double_clap();
                        }
                    }
                },
                err_fn,
                None,
            )
            .map_err(|e| format!("Failed to build input stream: {e}"))?,
        _ => return Err("Unsupported sample format".to_string()),
    };

    stream
        .play()
        .map_err(|e| format!("Failed to play stream: {e}"))?;
    Ok(stream)
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    // Check for direct trigger flag
    if args.iter().any(|arg| arg == "--trigger-double-clap" || arg == "-t") {
        println!("[carbon-acoustic] Direct double-clap trigger requested via CLI.");
        handle_double_clap();
        return;
    }

    println!("[carbon-acoustic] Starting Carbon Acoustic Engine...");

    let running = Arc::new(AtomicBool::new(true));
    let detector = Arc::new(Mutex::new(ClapDetector::new()));

    let _stream = match start_audio_capture(Arc::clone(&running), Arc::clone(&detector)) {
        Ok(s) => {
            println!("[carbon-acoustic] Audio input stream active and listening for double-clap.");
            Some(s)
        }
        Err(e) => {
            eprintln!("[carbon-acoustic] Warning: {e}. Running in interactive/IPC mode.");
            None
        }
    };

    // Stdin command loop
    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin).lines();

    while let Ok(Some(line)) = reader.next_line().await {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        match trimmed {
            "clap" | "double-clap" | "trigger" => {
                println!("[carbon-acoustic] Received trigger command.");
                handle_double_clap();
            }
            "status" => {
                let mut sys = System::new_all();
                sys.refresh_processes();
                let hyprlock_active = sys
                    .processes()
                    .values()
                    .any(|p| p.name().to_lowercase().contains("hyprlock"));
                println!(
                    "[carbon-acoustic] Status: running, hyprlock_active={}, CLAP_THRESHOLD={}, DEBUG_THRESHOLD={}",
                    hyprlock_active, CLAP_THRESHOLD, DEBUG_THRESHOLD
                );
            }
            "quit" | "exit" => {
                println!("[carbon-acoustic] Exiting.");
                break;
            }
            _ => {
                println!("[carbon-acoustic] Unknown command: {}", trimmed);
            }
        }
    }

    running.store(false, Ordering::Relaxed);
}
