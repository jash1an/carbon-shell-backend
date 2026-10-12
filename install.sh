#!/usr/bin/env bash
# ==============================================================================
# Carbon Shell — Interactive Installer
# ==============================================================================

set -euo pipefail

# Directory locations
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CARBON_CONFIG_DIR:-$HOME/.config/carbon}"
HYPR_CONFIG_DIR="$HOME/.config/hypr"
QUICKSHELL_DIR="$HOME/.local/share/quickshell/carbon"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
DEFAULT_WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${HOME}/.config/carbon_backup_${TIMESTAMP}"

# Flags
AUTO_YES=0
NO_DEPS=0
NO_RELOAD=0
KEYBIND_MODE="" # "carbon" or "keep"
CUSTOM_BACKUP=""

# Colors
if [[ -t 1 ]]; then
    C_BLUE="\033[1;34m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_RED="\033[1;31m"
    C_CYAN="\033[1;36m"
    C_BOLD="\033[1m"
    C_DIM="\033[2m"
    C_RESET="\033[0m"
else
    C_BLUE=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_CYAN=""
    C_BOLD=""
    C_DIM=""
    C_RESET=""
fi

msg()    { printf "${C_BLUE}::${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
info()   { printf " ${C_GREEN}->${C_RESET} %s\n" "$*"; }
warn()   { printf " ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
err()    { printf " ${C_RED}error:${C_RESET} %s\n" "$*" >&2; }
ok()     { printf "   ${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
fail()   { printf "   ${C_RED}[✗]${C_RESET} %s\n" "$*"; }
notice() { printf "   ${C_YELLOW}[!]${C_RESET} %s\n" "$*"; }
die()    { err "$@"; exit 1; }

prompt_confirm() {
    local prompt_msg="$1"
    local default_val="${2:-Y}" # Y or N
    local choice=""

    if [[ "$AUTO_YES" -eq 1 || ! -t 0 ]]; then
        [[ "$default_val" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    printf "${prompt_msg}" >&2
    read -r choice
    choice="${choice:-$default_val}"
    [[ "$choice" =~ ^[Yy]$ ]] && return 0 || return 1
}

prompt_choice() {
    local prompt_msg="$1"
    local default_val="$2"
    local choice=""

    if [[ "$AUTO_YES" -eq 1 || ! -t 0 ]]; then
        echo "$default_val"
        return
    fi

    printf "${prompt_msg}" >&2
    read -r choice
    echo "${choice:-$default_val}"
}

usage() {
    cat << EOF
Usage: ./install.sh [OPTIONS]

Interactive installer for Carbon Shell. Sets up the isolated Carbon runtime
environment, Quickshell components, scripts, and keybindings without overwriting
existing user configurations.

Options:
  -u, --update             Run updater (or ./update.sh)
  -y, --yes                Non-interactive mode (accept all defaults)
      --keybinds=<MODE>    Keybinding mode: 'carbon' (full) or 'keep' (shell-only)
      --no-deps            Skip package manager dependency checking and installation
      --no-reload          Do not restart Quickshell or reload Hyprland after install
      --backup-dir <DIR>   Specify custom backup directory
  -h, --help               Show this help message and exit

Examples:
  ./install.sh                      # Guided interactive installation
  ./install.sh -y --keybinds=keep   # Non-interactive install keeping current keybinds
  ./install.sh --update             # Update existing installation
EOF
    exit 0
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -u|--update)
            if [[ -x "$REPO_DIR/update.sh" ]]; then
                exec "$REPO_DIR/update.sh" "${@:2}"
            elif [[ -x "$REPO_DIR/carbon-update" ]]; then
                exec "$REPO_DIR/carbon-update" "${@:2}"
            elif command -v carbon-update >/dev/null 2>&1; then
                exec carbon-update "${@:2}"
            else
                die "Updater script not found."
            fi
            ;;
        -y|--yes)
            AUTO_YES=1
            shift
            ;;
        --keybinds=*)
            KEYBIND_MODE="${1#*=}"
            shift
            ;;
        --keybinds)
            [[ -n "${2:-}" ]] || die "Option --keybinds requires an argument ('carbon' or 'keep')"
            KEYBIND_MODE="$2"
            shift 2
            ;;
        --no-deps)
            NO_DEPS=1
            shift
            ;;
        --no-reload)
            NO_RELOAD=1
            shift
            ;;
        --backup-dir)
            [[ -n "${2:-}" ]] || die "Option --backup-dir requires a path argument"
            CUSTOM_BACKUP="$2"
            shift 2
            ;;
        *)
            die "Unknown option: $1 (run with --help for usage)"
            ;;
    esac
done

if [[ -n "$CUSTOM_BACKUP" ]]; then
    BACKUP_DIR="$CUSTOM_BACKUP"
fi

if [[ -n "$KEYBIND_MODE" && "$KEYBIND_MODE" != "carbon" && "$KEYBIND_MODE" != "keep" ]]; then
    die "Invalid keybinding mode: '$KEYBIND_MODE'. Must be 'carbon' or 'keep'."
fi

# ==============================================================================
# Header & Welcome
# ==============================================================================
printf "\n"
msg "Carbon Shell — Desktop Environment Setup"
printf "   ${C_DIM}Repository: %s${C_RESET}\n" "$REPO_DIR"
printf "   ${C_DIM}Target:     %s${C_RESET}\n\n" "$CONFIG_DIR"

# ------------------------------------------------------------------------------
# 1. Existing Installation Detection
# ------------------------------------------------------------------------------
if [[ -d "$CONFIG_DIR" && -z "$KEYBIND_MODE" && "$AUTO_YES" -eq 0 ]]; then
    warn "Existing Carbon Shell installation detected at $CONFIG_DIR"
    printf "\n  How would you like to proceed?\n"
    printf "    ${C_BOLD}[1] Update existing installation${C_RESET} (Preserves your custom configs & keybindings)\n"
    printf "    ${C_BOLD}[2] Reinstall / Fresh setup${C_RESET}      (Creates backup in ~/.config/carbon_backup_...)\n"
    printf "    ${C_BOLD}[3] Cancel${C_RESET}\n\n"

    EXISTING_CHOICE="$(prompt_choice "  Select option [1-3] (Default: 1): " "1")"
    case "$EXISTING_CHOICE" in
        1)
            info "Launching Carbon Shell updater..."
            if [[ -x "$REPO_DIR/update.sh" ]]; then
                exec "$REPO_DIR/update.sh"
            elif [[ -x "$REPO_DIR/carbon-update" ]]; then
                exec "$REPO_DIR/carbon-update"
            else
                die "Updater script not found."
            fi
            ;;
        2)
            info "Proceeding with fresh installation and configuration backup."
            ;;
        *)
            info "Installation cancelled."
            exit 0
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# 2. Distro Detection
# ------------------------------------------------------------------------------
msg "Detecting system distribution..."
DISTRO_ID="unknown"
DISTRO_LIKE=""
DISTRO_NAME="Linux"

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-$NAME}"
fi

info "Detected distribution: $DISTRO_NAME ($DISTRO_ID)"

# ------------------------------------------------------------------------------
# 3. Interactive Dependency Check & Package Installation
# ------------------------------------------------------------------------------
if [[ "$NO_DEPS" -eq 0 ]]; then
    msg "Checking dependencies..."

    CORE_DEPS=(
        "hyprland"
        "quickshell"
        "python3"
        "playerctl"
        "brightnessctl"
        "grim"
        "slurp"
        "socat"
        "jq"
        "fastfetch"
    )

    MISSING_CORE=()
    for cmd in "${CORE_DEPS[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            MISSING_CORE+=("$cmd")
            fail "$cmd"
        else
            ok "$cmd"
        fi
    done

    # Python module check
    PYTHON_MODULES=("PIL" "gi")
    MISSING_PY_MODS=()
    for mod in "${PYTHON_MODULES[@]}"; do
        if ! python3 -c "import $mod" >/dev/null 2>&1; then
            MISSING_PY_MODS+=("$mod")
            notice "python module: $mod (missing)"
        else
            ok "python module: $mod"
        fi
    done

    # M3Shapes QML module (required by the lock screen, bars and overview)
    M3SHAPES_FOUND=0
    for qmlroot in "/usr/lib/qt6/qml" "/usr/lib64/qt6/qml" \
                   "$HOME/.local/lib/qt6/qml" "$HOME/.config/quickshell"; do
        if [[ -f "$qmlroot/M3Shapes/qmldir" ]]; then
            M3SHAPES_FOUND=1
            break
        fi
    done
    if [[ "$M3SHAPES_FOUND" -eq 1 ]]; then
        ok "M3Shapes QML module"
    else
        notice "M3Shapes QML module (missing)"
    fi

    # QtMultimedia QML module (optional: only used for video wallpapers).
    # The shell degrades gracefully without it, so it is not treated as a
    # hard requirement.
    QTMULTIMEDIA_FOUND=0
    for qmlroot in "/usr/lib/qt6/qml" "/usr/lib64/qt6/qml" \
                   "$HOME/.local/lib/qt6/qml" "$HOME/.config/quickshell"; do
        if [[ -d "$qmlroot/QtMultimedia" ]]; then
            QTMULTIMEDIA_FOUND=1
            break
        fi
    done
    if [[ "$QTMULTIMEDIA_FOUND" -eq 1 ]]; then
        ok "QtMultimedia QML module"
    else
        notice "QtMultimedia QML module (optional, video wallpapers only)"
    fi

    if [[ ${#MISSING_CORE[@]} -gt 0 || ${#MISSING_PY_MODS[@]} -gt 0 || "$M3SHAPES_FOUND" -eq 0 ]]; then
        warn "Some required or recommended dependencies are missing."
        printf "\n"
        if prompt_confirm "  Would you like to install missing dependencies via system package manager? [Y/n]: " "Y"; then
            case "$DISTRO_ID" in
                arch|cachyos|endeavouros|manjaro|artix)
                    info "Installing packages for Arch Linux..."
                    AUR_HELPER=""
                    if command -v yay >/dev/null 2>&1; then AUR_HELPER="yay";
                    elif command -v paru >/dev/null 2>&1; then AUR_HELPER="paru"; fi

                    ARCH_PKGS=(
                        hyprland quickshell python python-pillow python-gobject
                        gtk4 libadwaita cava playerctl brightnessctl grim slurp
                        socat jq fastfetch pipewire wireplumber
                        ttf-jetbrains-mono-nerd ttf-material-symbols-variable
                        qt6-multimedia
                    )

                    if [[ -n "$AUR_HELPER" ]]; then
                        "$AUR_HELPER" -S --needed --noconfirm "${ARCH_PKGS[@]}" || true
                    else
                        sudo pacman -S --needed --noconfirm "${ARCH_PKGS[@]}" || true
                    fi

                    if [[ "$M3SHAPES_FOUND" -eq 0 ]]; then
                        if [[ -n "$AUR_HELPER" ]]; then
                            info "Installing required M3Shapes QML module..."
                            "$AUR_HELPER" -S --needed --noconfirm qt6-m3shapes-git || true
                        else
                            warn "M3Shapes is required by the Carbon shell but is not in the official repos."
                            info "Install the AUR package: yay -S qt6-m3shapes-git"
                        fi
                    fi
                    ;;
                fedora|nobara|centos|rhel)
                    info "Installing packages via dnf..."
                    FEDORA_PKGS=(
                        hyprland python3 python3-pillow python3-gobject
                        gtk4 libadwaita cava playerctl brightnessctl grim slurp
                        socat jq fastfetch pipewire wireplumber
                    )
                    sudo dnf install -y "${FEDORA_PKGS[@]}" || true
                    if ! command -v quickshell >/dev/null 2>&1; then
                        warn "Quickshell is not available in official Fedora repos."
                        info "Please install Quickshell via COPR or build from source:"
                        info "https://git.outfoxxed.me/outfoxxed/quickshell"
                    fi
                    ;;
                ubuntu|debian|pop|linuxmint|elementary)
                    info "Installing packages via apt..."
                    DEBIAN_PKGS=(
                        python3 python3-pil python3-gi gir1.2-gtk-4.0 gir1.2-adw-1
                        cava playerctl brightnessctl grim slurp socat jq fastfetch
                        pipewire wireplumber
                    )
                    sudo apt-get update -qq || true
                    sudo apt-get install -y "${DEBIAN_PKGS[@]}" || true
                    if ! command -v quickshell >/dev/null 2>&1; then
                        warn "Quickshell must be installed or built manually on Debian/Ubuntu:"
                        info "https://git.outfoxxed.me/outfoxxed/quickshell"
                    fi
                    ;;
                opensuse*|suse)
                    info "Installing packages via zypper..."
                    SUSE_PKGS=(
                        hyprland python3 python3-Pillow python3-gobject
                        gtk4 libadwaita playerctl brightnessctl grim slurp socat jq
                    )
                    sudo zypper --non-interactive install "${SUSE_PKGS[@]}" || true
                    ;;
                void)
                    info "Installing packages via xbps-install..."
                    VOID_PKGS=(
                        hyprland python3 python3-Pillow python3-gobject
                        gtk4 libadwaita playerctl brightnessctl grim slurp socat jq
                    )
                    sudo xbps-install -Syu -y "${VOID_PKGS[@]}" || true
                    ;;
                alpine)
                    info "Installing packages via apk..."
                    APK_PKGS=(
                        hyprland python3 py3-pillow py3-gobject3
                        gtk4 libadwaita playerctl brightnessctl grim slurp socat jq
                    )
                    sudo apk add "${APK_PKGS[@]}" || true
                    ;;
                nixos)
                    info "NixOS detected. Ensure quickshell, hyprland, and python packages are enabled in configuration.nix or home-manager."
                    ;;
                *)
                    warn "Unrecognized distribution. Please install required dependencies manually."
                    ;;
            esac

            if [[ "$M3SHAPES_FOUND" -eq 0 ]] \
               && [[ "$DISTRO_ID" != "arch" && "$DISTRO_ID" != "cachyos" && "$DISTRO_ID" != "endeavouros" && "$DISTRO_ID" != "manjaro" && "$DISTRO_ID" != "artix" ]]; then
                warn "The Carbon shell needs the 'M3Shapes' QML module, which is not packaged on your distro."
                info "Build and install it from https://github.com/soramanew/m3shapes"
            fi
            if [[ "$QTMULTIMEDIA_FOUND" -eq 0 ]]; then
                info "Optional: install Qt6 Multimedia (e.g. qt6-qtmultimedia / qml6-module-qtmultimedia) to enable video wallpapers."
            fi
        else
            info "Skipping automatic package installation as requested."
        fi
    else
        ok "All primary dependencies are present."
    fi
else
    info "Skipping dependency checks (--no-deps specified)."
fi

# ------------------------------------------------------------------------------
# 4. Safe Non-Destructive Backup
# ------------------------------------------------------------------------------
if [[ -d "$CONFIG_DIR" || -d "$QUICKSHELL_DIR" ]]; then
    msg "Creating safety backup of existing configurations..."
    mkdir -p "$BACKUP_DIR"
    if [[ -d "$CONFIG_DIR" ]]; then
        cp -rf "$CONFIG_DIR" "$BACKUP_DIR/carbon_config"
        ok "Backed up $CONFIG_DIR to $BACKUP_DIR/carbon_config"
    fi
    if [[ -d "$QUICKSHELL_DIR" ]]; then
        cp -rf "$QUICKSHELL_DIR" "$BACKUP_DIR/quickshell_carbon"
        ok "Backed up $QUICKSHELL_DIR to $BACKUP_DIR/quickshell_carbon"
    fi
fi

# ------------------------------------------------------------------------------
# 5. Interactive Keybinding Selection
# ------------------------------------------------------------------------------
msg "Keybinding configuration"

if [[ -z "$KEYBIND_MODE" ]]; then
    printf "\n  Select your preferred keybinding profile:\n\n"
    printf "    ${C_BOLD}[1] Full Carbon Keybindings${C_RESET} (Recommended)\n"
    printf "        Complete desktop experience with dedicated shortcuts:\n"
    printf "        - Super + Return  : Terminal (kitty)\n"
    printf "        - Super + Tab     : Workspace & Window Overview\n"
    printf "        - Super + Space   : Application Launcher\n"
    printf "        - Super + C       : Carbon Settings GUI\n"
    printf "        - Super + 1..0    : Workspace switching & window movement\n"
    printf "        - Super + L       : Lock screen with atomic visualizer\n\n"
    printf "    ${C_BOLD}[2] Keep Existing Keybindings${C_RESET}\n"
    printf "        Keeps all your current window & app shortcuts untouched.\n"
    printf "        Only registers non-conflicting Carbon shell triggers:\n"
    printf "        - Super + C       : Carbon Settings GUI\n"
    printf "        - Super + Tab     : Workspace & Window Overview\n"
    printf "        - Super + Space   : Application Launcher\n"
    printf "        - Super + N       : Wallpaper Picker\n"
    printf "        - Super + T       : Pomodoro Timer\n"
    printf "        - Super + L       : Lock screen\n\n"
    printf "  ${C_DIM}(You can switch between profiles anytime in Carbon Settings: Super + C)${C_RESET}\n\n"

    KB_SELECTION="$(prompt_choice "  Select profile [1/2] (Default: 1): " "1")"
    case "$KB_SELECTION" in
        2|keep|minimal)
            KEYBIND_MODE="keep"
            ;;
        *)
            KEYBIND_MODE="carbon"
            ;;
    esac
fi

info "Selected profile: $KEYBIND_MODE"

# ------------------------------------------------------------------------------
# 6. Deploy Isolated Configuration (~/.config/carbon) — Zero Symlinks
# ------------------------------------------------------------------------------
msg "Deploying isolated configuration to $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR/scripts"

# Save repository path for carbon-update
echo "$REPO_DIR" > "$CONFIG_DIR/repo_path"

# Copy runtime scripts (Direct copy, NO symlinks)
cp -rf "$REPO_DIR/hypr/scripts/"* "$CONFIG_DIR/scripts/"
chmod +x "$CONFIG_DIR/scripts/"* 2>/dev/null || true
mkdir -p "$HYPR_CONFIG_DIR/scripts"
cp -rf "$REPO_DIR/hypr/scripts/"* "$HYPR_CONFIG_DIR/scripts/"
chmod +x "$HYPR_CONFIG_DIR/scripts/"* 2>/dev/null || true
ok "Copied runtime scripts to $CONFIG_DIR/scripts and $HYPR_CONFIG_DIR/scripts"

# Deploy default bar mode configuration if not present
if [[ ! -f "$CONFIG_DIR/carbon-bar-mode.json" ]]; then
    cat << 'EOF' > "$CONFIG_DIR/carbon-bar-mode.json"
{
  "mode": "notch",
  "islandStyle": "notch",
  "islandPersistent": true,
  "wallpaperAnimation": "cinematic",
  "wallpaperDuration": 800,
  "nucleus": {
    "transition": true,
    "transitionWord": "Wooshh!!"
  }
}
EOF
    ok "Created default $CONFIG_DIR/carbon-bar-mode.json"
fi
cp -f "$CONFIG_DIR/carbon-bar-mode.json" "$HYPR_CONFIG_DIR/carbon-bar-mode.json" 2>/dev/null || true

# Deploy windowrules and looknfeel
cp -f "$REPO_DIR/hypr/windowrules.conf" "$CONFIG_DIR/windowrules.conf"
if [[ -f "$REPO_DIR/hypr/looknfeel.conf" ]]; then
    cp -f "$REPO_DIR/hypr/looknfeel.conf" "$CONFIG_DIR/looknfeel.conf"
fi

# Deploy keybinding templates
# Always provide both so the Settings app can switch between them anytime
cp -f "$REPO_DIR/hypr/keybinds.conf" "$CONFIG_DIR/keybinds.conf"
cp -f "$REPO_DIR/hypr/keybinds-shell-only.conf" "$CONFIG_DIR/keybinds-shell-only.conf"

# Deploy default Vanish/nucleus-mode keybindings. These are self-gated at
# runtime (the dispatcher exits unless the bar is in nucleus mode), so they
# are always safe to source alongside the regular keybindings.
if [[ -f "$REPO_DIR/hypr/configs/vanish-keybinds.conf" && ! -f "$CONFIG_DIR/vanish-keybinds.conf" ]]; then
    cp -f "$REPO_DIR/hypr/configs/vanish-keybinds.conf" "$CONFIG_DIR/vanish-keybinds.conf"
fi

# Deploy colors template if not already present
if [[ ! -f "$CONFIG_DIR/colors.conf" && -f "$REPO_DIR/hypr/colors.conf" ]]; then
    cp -f "$REPO_DIR/hypr/colors.conf" "$CONFIG_DIR/colors.conf"
fi

# Generate carbon.conf with the chosen keybinding source
cat << EOF > "$CONFIG_DIR/carbon.conf"
# ==============================================================================
# Carbon Shell — Hyprland Environment Integration
# Automatically loaded by ~/.config/hypr/hyprland.conf
# ==============================================================================

# Isolated Config Environment
env = CARBON_CONFIG_DIR,\$HOME/.config/carbon

# Include user-local binaries (kitty, yazi, wl-copy, cliphist, ...)
env = PATH, \$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl

# Dynamic Material You Theme Colors
source = ~/.config/carbon/colors.conf

# Window & Layer Rules (Blur for QuickSettings, Overview, Island)
source = ~/.config/carbon/windowrules.conf

# Keybindings:
# Managed live from Carbon Settings App (Super + C) or by editing this line:
# - Full Carbon keybindings: source = ~/.config/carbon/keybinds.conf
# - Keep your own keybindings: source = ~/.config/carbon/keybinds-shell-only.conf
EOF

if [[ "$KEYBIND_MODE" == "keep" ]]; then
    echo "source = ~/.config/carbon/keybinds-shell-only.conf" >> "$CONFIG_DIR/carbon.conf"
else
    echo "source = ~/.config/carbon/keybinds.conf" >> "$CONFIG_DIR/carbon.conf"
fi

# Vanish-mode dedicated shortcuts (nucleus mode), self-gated at runtime
echo "source = ~/.config/carbon/vanish-keybinds.conf" >> "$CONFIG_DIR/carbon.conf"

cat << EOF >> "$CONFIG_DIR/carbon.conf"

# Autostart Carbon Quickshell Service
exec-once = systemctl --user start carbon-quickshell.service

# Clipboard history daemon (Cliphist)
exec-once = bash -c 'wl-paste --watch cliphist store'
exec-once = bash -c 'wl-paste --type image --watch cliphist store'
EOF

ok "Generated $CONFIG_DIR/carbon.conf"

# ------------------------------------------------------------------------------
# 7. Non-Destructive Hyprland Integration
# ------------------------------------------------------------------------------
msg "Integrating with Hyprland..."
mkdir -p "$HYPR_CONFIG_DIR"

HYPR_MAIN_CONF="$HYPR_CONFIG_DIR/hyprland.conf"
CARBON_SOURCE_LINE="source = ~/.config/carbon/carbon.conf"

if [[ -f "$HYPR_MAIN_CONF" ]]; then
    if grep -Fq "$CARBON_SOURCE_LINE" "$HYPR_MAIN_CONF"; then
        ok "Carbon Shell is already sourced in $HYPR_MAIN_CONF"
    else
        printf "\n# Carbon Shell Integration\n%s\n" "$CARBON_SOURCE_LINE" >> "$HYPR_MAIN_CONF"
        ok "Safely appended source entry to $HYPR_MAIN_CONF"
    fi
else
    cat << EOF > "$HYPR_MAIN_CONF"
# ==============================================================================
# Hyprland Main Configuration
# Autogenerated by Carbon Shell Installer
# ==============================================================================

source = ~/.config/carbon/carbon.conf
EOF
    ok "Created starter $HYPR_MAIN_CONF"
fi

# ------------------------------------------------------------------------------
# 8. Deploy Quickshell Components (Zero Symlinks)
# ------------------------------------------------------------------------------
msg "Deploying Quickshell components..."
mkdir -p "$QUICKSHELL_DIR"
cp -rf "$REPO_DIR/quickshell/carbon/"* "$QUICKSHELL_DIR/"
ok "Quickshell assets deployed to $QUICKSHELL_DIR"

# ------------------------------------------------------------------------------
# 9. Wallpapers & Initial Color Scheme (Zero Symlinks)
# ------------------------------------------------------------------------------
msg "Configuring wallpaper and theme..."
mkdir -p "$DEFAULT_WALLPAPER_DIR"

DEFAULT_WP_SRC="$REPO_DIR/assets/wallpapers/default.png"
DEFAULT_WP_DEST="$DEFAULT_WALLPAPER_DIR/wallhaven-6ly7yw.png"

SET_DEFAULT_WP=1
if [[ -f "$CONFIG_DIR/current_wallpaper" && "$AUTO_YES" -eq 0 ]]; then
    if ! prompt_confirm "  Configure Carbon default wallpaper? [Y/n]: " "Y"; then
        SET_DEFAULT_WP=0
    fi
fi

if [[ "$SET_DEFAULT_WP" -eq 1 ]]; then
    if [[ -f "$DEFAULT_WP_SRC" && ! -f "$DEFAULT_WP_DEST" ]]; then
        cp -f "$DEFAULT_WP_SRC" "$DEFAULT_WP_DEST"
    fi

    if [[ -f "$DEFAULT_WP_DEST" ]]; then
        ln -sfn "$DEFAULT_WP_DEST" "$CONFIG_DIR/current_wallpaper"
        echo "$DEFAULT_WP_DEST" > "$CONFIG_DIR/current_wallpaper_path"
        ln -sfn "$DEFAULT_WP_DEST" "$HYPR_CONFIG_DIR/current_wallpaper"
        echo "$DEFAULT_WP_DEST" > "$HYPR_CONFIG_DIR/current_wallpaper_path"
        ok "Configured default wallpaper: $DEFAULT_WP_DEST"
    elif [[ -f "$DEFAULT_WP_SRC" ]]; then
        ln -sfn "$DEFAULT_WP_SRC" "$CONFIG_DIR/current_wallpaper"
        echo "$DEFAULT_WP_SRC" > "$CONFIG_DIR/current_wallpaper_path"
        ln -sfn "$DEFAULT_WP_SRC" "$HYPR_CONFIG_DIR/current_wallpaper"
        echo "$DEFAULT_WP_SRC" > "$HYPR_CONFIG_DIR/current_wallpaper_path"
        ok "Configured default wallpaper from repository assets"
    fi

    # Run theme generator
    if [[ -f "$CONFIG_DIR/scripts/theme-mk.py" ]]; then
        info "Generating initial theme colors..."
        python3 "$CONFIG_DIR/scripts/theme-mk.py" >/dev/null 2>&1 || true
    fi
fi

# ------------------------------------------------------------------------------
# 10. Install Fonts
# ------------------------------------------------------------------------------
if [[ -d "$REPO_DIR/fonts" ]]; then
    msg "Installing custom fonts..."
    USER_FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$USER_FONT_DIR"
    cp -f "$REPO_DIR/fonts/"*.ttf "$USER_FONT_DIR/" 2>/dev/null || true
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
    ok "Installed fonts to $USER_FONT_DIR"
fi

# ------------------------------------------------------------------------------
# 11. Deploy User Binaries (~/.local/bin)
# ------------------------------------------------------------------------------
msg "Deploying user binaries to $BIN_DIR..."
mkdir -p "$BIN_DIR"

# Install updater
if [[ -f "$REPO_DIR/update.sh" ]]; then
    cp -f "$REPO_DIR/update.sh" "$BIN_DIR/carbon-update"
    cp -f "$REPO_DIR/update.sh" "$BIN_DIR/carbon-shell-update"
elif [[ -f "$REPO_DIR/carbon-update" ]]; then
    cp -f "$REPO_DIR/carbon-update" "$BIN_DIR/carbon-update"
    cp -f "$REPO_DIR/carbon-update" "$BIN_DIR/carbon-shell-update"
fi
chmod +x "$BIN_DIR/carbon-update" "$BIN_DIR/carbon-shell-update" 2>/dev/null || true

# Install launchers
cp -f "$CONFIG_DIR/scripts/carbon-config-editor" "$BIN_DIR/carbon-config-editor"
cp -f "$CONFIG_DIR/scripts/carbon-pomodoro" "$BIN_DIR/carbon-pomodoro"

# Install screenshot tools
for s in "$CONFIG_DIR/scripts/carbon-screenshot-"*.sh; do
    if [[ -f "$s" ]]; then
        base="$(basename "$s" .sh)"
        cp -f "$s" "$BIN_DIR/$base"
        cp -f "$s" "$BIN_DIR/$base.sh"
    fi
done

chmod +x "$BIN_DIR/carbon-"* 2>/dev/null || true
ok "Installed binaries in $BIN_DIR"

# ------------------------------------------------------------------------------
# 12. Optional Configs (Fastfetch & Desktop Portals)
# ------------------------------------------------------------------------------
if [[ -d "$REPO_DIR/fastfetch" && ! -d "$HOME/.config/fastfetch" ]]; then
    mkdir -p "$HOME/.config/fastfetch"
    cp -rf "$REPO_DIR/fastfetch/"* "$HOME/.config/fastfetch/" 2>/dev/null || true
fi

if [[ -d "$REPO_DIR/xdg-desktop-portal" && ! -d "$HOME/.config/xdg-desktop-portal" ]]; then
    mkdir -p "$HOME/.config/xdg-desktop-portal"
    cp -rf "$REPO_DIR/xdg-desktop-portal/"* "$HOME/.config/xdg-desktop-portal/" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 13. Systemd User Service Configuration
# ------------------------------------------------------------------------------
msg "Configuring systemd user service..."
if [[ -f "$REPO_DIR/systemd/carbon-quickshell.service" ]]; then
    mkdir -p "$SYSTEMD_USER_DIR"
    cp -f "$REPO_DIR/systemd/carbon-quickshell.service" "$SYSTEMD_USER_DIR/"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        systemctl --user enable carbon-quickshell.service >/dev/null 2>&1 || true
        ok "Enabled carbon-quickshell.service"
    fi
fi

# ------------------------------------------------------------------------------
# 14. Audio Hardware Initialization
# ------------------------------------------------------------------------------
if [[ -f "$CONFIG_DIR/scripts/carbon-audio-init.sh" ]]; then
    bash "$CONFIG_DIR/scripts/carbon-audio-init.sh" >/dev/null 2>&1 || true
fi

# ------------------------------------------------------------------------------
# 15. Reload & Summary
# ------------------------------------------------------------------------------
printf "\n"
msg "Installation complete!"
printf "\n"
printf "   Configuration directory : %s\n" "$CONFIG_DIR"
printf "   Keybinding profile      : %s\n" "$KEYBIND_MODE"
printf "   Settings GUI            : Super + C (or 'carbon-config-editor')\n"
printf "   Single-command update   : 'carbon-update' (or './update.sh')\n"
printf "\n"

if [[ "$NO_RELOAD" -eq 0 ]]; then
    if prompt_confirm "Start Carbon Quickshell and reload Hyprland now? [Y/n]: " "Y"; then
        info "Starting Carbon services..."
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user restart carbon-quickshell.service >/dev/null 2>&1 || {
                pkill -x quickshell 2>/dev/null || true
                sleep 0.5
                nohup quickshell --config "$QUICKSHELL_DIR" >/dev/null 2>&1 &
            }
        else
            pkill -x quickshell 2>/dev/null || true
            sleep 0.5
            nohup quickshell --config "$QUICKSHELL_DIR" >/dev/null 2>&1 &
        fi

        if command -v hyprctl >/dev/null 2>&1; then
            if hyprctl instances >/dev/null 2>&1; then
                hyprctl reload >/dev/null 2>&1 || true
                ok "Hyprland reloaded"
            fi
        fi
        ok "Carbon Shell is now active"
    fi
fi

printf "\n"
