# Carbon Shell ⚛️

> **A cutting-edge, ultra-fluid, and responsive desktop shell for Hyprland built on Quickshell and GTK4/Libadwaita.**
> *Created by Kazu — Special thanks to reduct.sh*

---

## ✨ Features

- ⚛️ **Static & Animated Bohr Atomic Model**: Central "C" nucleus with dual concentric electron orbits (K-shell & L-shell) featured across the bar launcher, lock screen, config app, and Fastfetch.
- 🏝️ **3 Flexible Desktop Bar Layouts**:
  - **Notch Mode**: Elegant screen-attached curved notch bars with integrated workspaces, clock, vinyl music, and status indicators.
  - **Pill Mode**: Floating continuous capsule bar spanning the display edge.
  - **Minimal Mode (Dynamic Island)**: Compact, ultra-lightweight dynamic island capsule with lyrics-on-hover and audio waveform.
- 🪟 **macOS Mission Control / Windows Task View Overview (`Super + Tab` / 3-finger swipe)**:
  - Horizontal workspace carousel with interactive application cards.
  - Drag-and-drop windows between workspaces.
  - **Dynamic Frosted-Glass Blur**: Automatically engages 2-pass 5-strength hardware blur while open, and disables blur when dismissed for near-zero GPU overhead.
- 🎨 **Dynamic Material You Theming**:
  - Powered by Matugen & PIL color extraction from any wallpaper.
  - Instant live palette synchronization across Hyprland active borders, Quickshell, GTK4 apps, and Fastfetch terminal logo.
- 🎵 **Interactive Media Player & Draggable Waveform**:
  - Interactive seeking progress bar in the quick-settings panel.
  - Real-time synchronized lyrics support.
  - Smooth audio visualizer with Cava integration.
- ⚙️ **Native GTK4/Libadwaita Settings App (`Super + C`)**:
  - Instant layout switcher (Pill / Notch / Minimal).
  - Live Wi-Fi scanning & secure network connection dialog.
  - Live Bluetooth device scanning & pairing.
  - Clock style switcher, gestures configuration, keybinds listener, and lockscreen customizer.
  - Opens instantly in its true floating dimensions with zero resize flash.

---

## 🚀 Installation & Setup

Clone the repository and run the interactive installer:

```bash
git clone https://github.com/<YOUR_USERNAME>/carbon-shell.git
cd carbon-shell
chmod +x install.sh
./install.sh
```

### Installation Options
The installer interactively guides you through:
- **Keybinding Selection**:
  - `[1] Carbon Keybindings`: Full desktop setup (Super+Return terminal, Super+Tab overview, Super+Space launcher, Super+1..0 workspaces).
  - `[2] Keep Existing Keybindings`: Retains all your custom hyprland keybindings untouched and only loads non-conflicting Carbon shell triggers.
- **Dependency Checks**: Automatic package manager detection (`pacman`, `dnf`, `apt`, `zypper`, `xbps`, `apk`).
- **Safe Non-Destructive Configs**: Deploys to `~/.config/carbon` with **zero symlinks** and preserves your existing `~/.config/hypr/hyprland.conf`.

---

## 🔄 Updating Carbon Shell

To update Carbon Shell to the latest version at any time, run from any terminal:

```bash
carbon-update
```

Or from the repository root:

```bash
./update.sh
```

To check for updates without applying:

```bash
carbon-update --check
```

---

## 📦 Dependencies

The installer will automatically prompt and install all required packages:

| Component | Packages |
|---|---|
| **Compositor & Shell** | `hyprland`, `quickshell` |
| **M3 Shapes (QML module)** | `qt6-m3shapes-git` (AUR — required by the shell UI) |
| **Video Wallpapers (optional)** | `qt6-multimedia` (QML module; animated `.mp4`/`.webm` wallpapers only) |
| **Theme & Color Engine** | `matugen`, `python-pillow` |
| **Config & UI** | `python-gobject`, `gtk4`, `libadwaita` |
| **Audio & Media** | `playerctl`, `pipewire`, `wireplumber`, `cava` |
| **Tools & Utilities** | `fastfetch`, `grim`, `slurp`, `socat`, `networkmanager`, `bluez` |
| **Fonts** | `Valley Sans`, `Caveat`, `JetBrainsMono Nerd Font` |

---

## ⌨️ Default Keybindings

- <kbd>Super</kbd> + <kbd>Tab</kbd> — Open Workspaces & Windows Overview
- <kbd>Super</kbd> + <kbd>C</kbd> — Open Carbon Settings
- <kbd>Super</kbd> + <kbd>R</kbd> — App Launcher / Spotlight Search
- <kbd>Super</kbd> + <kbd>N</kbd> — Wallpaper Picker
- <kbd>Super</kbd> + <kbd>B</kbd> — Control Center
- <kbd>Super</kbd> + <kbd>Space</kbd> — Toggle Floating (active window)
- <kbd>Super</kbd> + <kbd>Return</kbd> — Terminal
- <kbd>Super</kbd> + <kbd>L</kbd> — Lock Screen

---

## 📜 Credits

- **Made by Kazu**
- **Special thanks to reduct.sh**
- *All rights reserved ©*
