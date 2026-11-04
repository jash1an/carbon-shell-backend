#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CARBON_CONFIG_DIR:-$HOME/.config/carbon}"
QUICKSHELL_DIR="$HOME/.local/share/quickshell/carbon"
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
REPO_PATH_FILE="$CONFIG_DIR/repo_path"

FORCE=0
AUTO_YES=0
NO_RELOAD=0
CHECK_ONLY=0
ROLLBACK=0
BRANCH=""

if [[ -t 1 ]]; then
    C_BLUE="\033[1;34m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"
    C_RED="\033[1;31m"; C_BOLD="\033[1m"; C_RESET="\033[0m"
else
    C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_RESET=""
fi

msg()    { printf "${C_BLUE}::${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
info()   { printf " ${C_GREEN}->${C_RESET} %s\n" "$*"; }
warn()   { printf " ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
err()    { printf " ${C_RED}error:${C_RESET} %s\n" "$*" >&2; }
ok()     { printf "   ${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
die()    { err "$@"; exit 1; }

prompt_confirm() {
    local prompt_msg="$1"
    local default_val="${2:-Y}"
    local choice=""

    if [[ "$AUTO_YES" -eq 1 || ! -t 0 ]]; then
        [[ "$default_val" =~ ^[Yy]$ ]] && return 0 || return 1
    fi

    printf "%s" "$prompt_msg" >&2
    read -r choice
    choice="${choice:-$default_val}"
    [[ "$choice" =~ ^[Yy]$ ]] && return 0 || return 1
}

usage() {
    cat << EOF
Usage: ./update.sh [OPTIONS]
   or: carbon-update [OPTIONS]

Options:
  -c, --check       Check for available upstream updates without applying
  -y, --yes         Non-interactive mode
  -f, --force       Force update even if working tree has changes
  -b, --branch <b>  Pull from specified branch
  -r, --rollback    Restore previous safety backup
      --no-reload   Skip reloading services after update
  -h, --help        Show this message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -c|--check) CHECK_ONLY=1; shift ;;
        -r|--rollback|--restore) ROLLBACK=1; shift ;;
        -y|--yes) AUTO_YES=1; shift ;;
        -f|--force) FORCE=1; shift ;;
        -b|--branch) [[ -n "${2:-}" ]] || die "Option requires branch name"; BRANCH="$2"; shift 2 ;;
        --no-reload) NO_RELOAD=1; shift ;;
        *) die "Unknown option: $1" ;;
    esac
done

if [[ "$ROLLBACK" -eq 1 ]]; then
    BACKUP_DIR="$CONFIG_DIR/backups"
    LATEST="$(ls -1t "$BACKUP_DIR"/carbon-backup-*.tar.gz 2>/dev/null | head -n 1 || true)"
    [[ -z "$LATEST" || ! -f "$LATEST" ]] && die "No backup archive found in $BACKUP_DIR"
    msg "Restoring backup: $(basename "$LATEST")..."
    tar -xzf "$LATEST" -C "$HOME"
    ok "Rollback complete"
    if [[ "$NO_RELOAD" -eq 0 ]]; then
        systemctl --user restart carbon-quickshell.service 2>/dev/null || true
        systemctl --user restart carbon-hub.service 2>/dev/null || true
        command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
    fi
    exit 0
fi

create_safety_backup() {
    local bdir="$CONFIG_DIR/backups"
    local bfile="$bdir/carbon-backup-$(date +'%Y%m%d_%H%M%S').tar.gz"
    mkdir -p "$bdir"
    tar --exclude=".config/carbon/backups" -czf "$bfile" -C "$HOME" ".local/share/quickshell/carbon" ".config/carbon" 2>/dev/null || true
    if [[ -f "$bfile" ]]; then
        ok "Safety backup created: $(basename "$bfile")"
        ls -1t "$bdir"/carbon-backup-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
    fi
}

printf "\n"
msg "Carbon Shell Updater"

REPO_DIR=""
if [[ -n "${CARBON_REPO_DIR:-}" && -d "$CARBON_REPO_DIR/.git" ]]; then
    REPO_DIR="$CARBON_REPO_DIR"
elif [[ -f "$REPO_PATH_FILE" ]]; then
    SAVED="$(head -n 1 "$REPO_PATH_FILE" 2>/dev/null || true)"
    [[ -n "$SAVED" && -d "$SAVED/.git" ]] && REPO_DIR="$SAVED"
fi

if [[ -z "$REPO_DIR" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "$SCRIPT_DIR/.git" && -f "$SCRIPT_DIR/quickshell/carbon/shell.qml" ]]; then
        REPO_DIR="$SCRIPT_DIR"
    elif [[ -d "$PWD/.git" && -f "$PWD/quickshell/carbon/shell.qml" ]]; then
        REPO_DIR="$PWD"
    fi
fi

if [[ -z "$REPO_DIR" ]]; then
    DEFAULT_CLONE="$HOME/.local/share/carbon-shell"
    if [[ -d "$DEFAULT_CLONE/.git" ]]; then
        REPO_DIR="$DEFAULT_CLONE"
    else
        if prompt_confirm "Clone repository to $DEFAULT_CLONE? [Y/n]: " "Y"; then
            mkdir -p "$(dirname "$DEFAULT_CLONE")"
            git clone "${CARBON_REMOTE_URL:-https://github.com/xzshogun/carbon-shell.git}" "$DEFAULT_CLONE"
            REPO_DIR="$DEFAULT_CLONE"
        else
            die "Cannot update without local repository."
        fi
    fi
    mkdir -p "$CONFIG_DIR"
    echo "$REPO_DIR" > "$REPO_PATH_FILE"
fi

info "Repository: $REPO_DIR"
cd "$REPO_DIR"

if [[ -n "$BRANCH" ]]; then
    git checkout "$BRANCH" 2>/dev/null || die "Could not checkout $BRANCH"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"

# ── Upstream Remote Enforcement ──────────────────────────────────────────────
# Ensure updates always check and pull from the official upstream repository
UPSTREAM_URL="${CARBON_REMOTE_URL:-https://github.com/xzshogun/carbon-shell.git}"
UPSTREAM="origin"

if git remote get-url origin >/dev/null 2>&1; then
    CURRENT_ORIGIN="$(git remote get-url origin)"
    if [[ "$CURRENT_ORIGIN" != *"xzshogun/carbon-shell"* ]]; then
        # Origin is pointing to a fork; move fork to 'myfork' and set 'origin' to upstream
        if ! git remote get-url myfork >/dev/null 2>&1; then
            git remote rename origin myfork 2>/dev/null || true
            git remote add origin "$UPSTREAM_URL" 2>/dev/null || true
        else
            git remote set-url origin "$UPSTREAM_URL"
        fi
    fi
else
    git remote add origin "$UPSTREAM_URL" 2>/dev/null || true
fi

# Ensure branch tracking points to origin
git config "branch.${CURRENT_BRANCH}.remote" "origin" 2>/dev/null || true
git config "branch.${CURRENT_BRANCH}.merge" "refs/heads/${CURRENT_BRANCH}" 2>/dev/null || true

REMOTE_TARGET="${BRANCH:-main}"
info "Checking upstream ($UPSTREAM_URL : $REMOTE_TARGET)..."
git fetch "$UPSTREAM" "$REMOTE_TARGET" --quiet 2>/dev/null || warn "Could not reach remote repository ($UPSTREAM_URL)."

LOCAL_HASH="$(git rev-parse HEAD 2>/dev/null || echo "")"
REMOTE_HASH="$(git rev-parse --verify "$UPSTREAM/$REMOTE_TARGET^{commit}" 2>/dev/null || echo "$LOCAL_HASH")"
COMMITS_AHEAD="$(git rev-list --count HEAD.."$UPSTREAM/$REMOTE_TARGET" 2>/dev/null || echo 0)"

if [[ "$COMMITS_AHEAD" -eq 0 ]]; then
    if [[ "$CHECK_ONLY" -eq 1 ]]; then
        ok "Carbon Shell is up to date (${LOCAL_HASH:0:8})"
        exit 0
    fi
    if [[ "$FORCE" -eq 0 ]]; then
        ok "Carbon Shell is already up to date (${LOCAL_HASH:0:8})"
        if ! prompt_confirm "Re-synchronize assets and restart services anyway? [y/N]: " "N"; then
            exit 0
        fi
    fi
else
    msg "Updates available ($COMMITS_AHEAD new commits from upstream):"
    printf "   Current: %s\n   Latest : %s\n\n" "${LOCAL_HASH:0:8}" "${REMOTE_HASH:0:8}"
    git log --oneline --no-merges -n 5 "HEAD..$UPSTREAM/$REMOTE_TARGET" 2>/dev/null | sed 's/^/   * /' || true
    printf "\n"
    [[ "$CHECK_ONLY" -eq 1 ]] && exit 0
    prompt_confirm "Apply updates now? [Y/n]: " "Y" || exit 0
fi

if [[ "$COMMITS_AHEAD" -gt 0 || "$FORCE" -eq 1 ]]; then
    create_safety_backup

    STASH_SAVED=0
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        info "Stashing working tree changes..."
        if git stash push -u -m "carbon-update-stash-$(date +'%Y%m%d_%H%M%S')" --quiet; then
            STASH_SAVED=1
        fi
    fi

    if [[ "$FORCE" -eq 1 ]]; then
        git reset --hard "$UPSTREAM/$REMOTE_TARGET" --quiet
    else
        if git merge-base --is-ancestor HEAD "$REMOTE_HASH" 2>/dev/null; then
            git merge --ff-only "$REMOTE_HASH" --quiet 2>/dev/null || git reset --hard "$REMOTE_HASH"
        else
            # Local branch contains commits not in upstream: rebase on top of upstream
            git rebase "$UPSTREAM/$REMOTE_TARGET" --quiet 2>/dev/null || {
                git rebase --abort 2>/dev/null || true
                git merge --no-edit "$REMOTE_HASH" --quiet 2>/dev/null || {
                    git merge --abort 2>/dev/null || true
                    die "Merge conflict detected with upstream. Run with -f/--force to reset cleanly."
                }
            }
        fi
    fi

    if [[ "$STASH_SAVED" -eq 1 ]]; then
        git stash pop --quiet 2>/dev/null || warn "Working tree had stashed changes; inspect with 'git stash list'."
    fi
    ok "Working tree updated to $(git rev-parse --short HEAD)"
else
    create_safety_backup
fi

# ── Synchronize Quickshell Components ─────────────────────────────────────────
msg "Updating Quickshell components..."
mkdir -p "$QUICKSHELL_DIR"
cp -rf "$REPO_DIR/quickshell/carbon/"* "$QUICKSHELL_DIR/"
chmod +x "$QUICKSHELL_DIR/scripts/"* 2>/dev/null || true
ok "Quickshell updated"

# Synchronize shell assets
if [[ -d "$REPO_DIR/assets" ]]; then
    mkdir -p "$CONFIG_DIR/assets"
    cp -rf "$REPO_DIR/assets/"* "$CONFIG_DIR/assets/" 2>/dev/null || true
    ok "Assets updated"
fi

# ── Synchronize Runtime Scripts & Configs ─────────────────────────────────────
msg "Updating configurations and scripts..."
mkdir -p "$CONFIG_DIR/scripts" "$CONFIG_DIR/configs" "$HOME/.config/hypr/scripts" "$HOME/.config/hypr/configs"
echo "$REPO_DIR" > "$REPO_PATH_FILE"

# Sync scripts to BOTH ~/.config/carbon/scripts/ AND ~/.config/hypr/scripts/
cp -rf "$REPO_DIR/hypr/scripts/"* "$CONFIG_DIR/scripts/"
chmod +x "$CONFIG_DIR/scripts/"* 2>/dev/null || true

cp -rf "$REPO_DIR/hypr/scripts/"* "$HOME/.config/hypr/scripts/"
chmod +x "$HOME/.config/hypr/scripts/"* 2>/dev/null || true
ok "Runtime scripts synchronized"

# Sync configs to BOTH ~/.config/carbon/configs/ and ~/.config/hypr/configs/
for src in "$REPO_DIR/hypr/configs/"*; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src")"
    cp -f "$src" "$CONFIG_DIR/configs/$name"
    cp -f "$src" "$HOME/.config/hypr/configs/$name"
done

# Sync mode keybind configs to root config dir for dispatcher compatibility
for m in minimal notch pill vanish; do
    [[ -f "$REPO_DIR/hypr/configs/keybinds-${m}.conf" ]] && cp -f "$REPO_DIR/hypr/configs/keybinds-${m}.conf" "$CONFIG_DIR/"
done

# Root Hyprland config files
for conf in windowrules.conf looknfeel.conf keybinds.conf keybinds-shell-only.conf vanish-keybinds.conf blur-exceptions.conf; do
    src="$REPO_DIR/hypr/$conf"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$CONFIG_DIR/$conf"
        dst="$HOME/.config/hypr/$conf"
        if [[ -f "$dst" ]]; then
            cp -f "$src" "$dst.dist" 2>/dev/null || true
        else
            cp -f "$src" "$dst" 2>/dev/null || true
        fi
    fi
done

for j in "$REPO_DIR/hypr/"*.json; do
    [[ -f "$j" ]] || continue
    cp -f "$j" "$CONFIG_DIR/$(basename "$j")"
    [[ ! -f "$HOME/.config/hypr/$(basename "$j")" ]] && cp -f "$j" "$HOME/.config/hypr/$(basename "$j")" 2>/dev/null || true
done

# ── Deploy Desktop Entries ───────────────────────────────────────────────────
msg "Updating application launcher shortcuts..."
mkdir -p "$HOME/.local/share/applications"
[[ -f "$REPO_DIR/assets/carbon-settings.desktop" ]] && cp -f "$REPO_DIR/assets/carbon-settings.desktop" "$HOME/.local/share/applications/carbon-settings.desktop"
[[ -f "$REPO_DIR/assets/carbon-config-editor.desktop" ]] && cp -f "$REPO_DIR/assets/carbon-config-editor.desktop" "$HOME/.local/share/applications/carbon-config-editor.desktop"
[[ -f "$REPO_DIR/assets/carbon-drop.desktop" ]] && cp -f "$REPO_DIR/assets/carbon-drop.desktop" "$HOME/.local/share/applications/carbon-drop.desktop"
rm -f "$HOME/.local/share/applications/carbon-settings-hub.desktop" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
ok "Desktop entries updated"

# ── Build & Deploy Rust Components ───────────────────────────────────────────
mkdir -p "$BIN_DIR"
if command -v cargo >/dev/null 2>&1; then
    # 1. Carbon Settings Hub daemon
    if [[ -d "$REPO_DIR/backend/carbon-hub-daemon" ]]; then
        msg "Building carbon-hub-daemon (Rust)..."
        (cd "$REPO_DIR/backend/carbon-hub-daemon" && cargo build --release --quiet) 2>/dev/null || warn "Failed to build carbon-hub-daemon"
        if [[ -f "$REPO_DIR/backend/carbon-hub-daemon/target/release/carbon-hub-daemon" ]]; then
            cp -f "$REPO_DIR/backend/carbon-hub-daemon/target/release/carbon-hub-daemon" "$BIN_DIR/carbon-hub-daemon"
            chmod +x "$BIN_DIR/carbon-hub-daemon"
            ok "carbon-hub-daemon built and deployed"
        fi
    fi

    # 2. Carbon Drop streaming engine
    if [[ -d "$REPO_DIR/apps/carbon-drop" ]]; then
        msg "Building carbon-drop-engine (Rust)..."
        (cd "$REPO_DIR/apps/carbon-drop" && cargo build --release --quiet) 2>/dev/null || warn "Failed to build carbon-drop-engine"
        if [[ -f "$REPO_DIR/apps/carbon-drop/target/release/carbon-drop-engine" ]]; then
            cp -f "$REPO_DIR/apps/carbon-drop/target/release/carbon-drop-engine" "$BIN_DIR/carbon-drop-engine"
            chmod +x "$BIN_DIR/carbon-drop-engine"
            ok "carbon-drop-engine built and deployed"
        fi
    fi
else
    warn "Cargo not found; skipping Rust compilation."
fi

# Ensure carbon-drop executable launcher exists in $BIN_DIR
cat << 'EOF' > "$BIN_DIR/carbon-drop"
#!/usr/bin/env bash
QML_PATH="$HOME/.local/share/quickshell/carbon/modules/CarbonDrop.qml"
if [ ! -f "$QML_PATH" ]; then
    QML_PATH="$HOME/.config/carbon/modules/CarbonDrop.qml"
fi
exec quickshell -d -p "$QML_PATH" "$@"
EOF
chmod +x "$BIN_DIR/carbon-drop"

# Deploy systemd user service for carbon-hub
if [[ -f "$REPO_DIR/systemd/carbon-hub.service" ]]; then
    mkdir -p "$SYSTEMD_USER_DIR"
    cp -f "$REPO_DIR/systemd/carbon-hub.service" "$SYSTEMD_USER_DIR/"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        systemctl --user enable carbon-hub.service >/dev/null 2>&1 || true
    fi
fi

# Deploy systemd user service for carbon-quickshell
if [[ -f "$REPO_DIR/systemd/carbon-quickshell.service" ]]; then
    mkdir -p "$SYSTEMD_USER_DIR"
    cp -f "$REPO_DIR/systemd/carbon-quickshell.service" "$SYSTEMD_USER_DIR/"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        systemctl --user enable carbon-quickshell.service >/dev/null 2>&1 || true
    fi
fi

# ── Synchronize User Binaries ─────────────────────────────────────────────────
[[ -f "$REPO_DIR/update.sh" ]] && cp -f "$REPO_DIR/update.sh" "$BIN_DIR/carbon-update"
[[ -f "$CONFIG_DIR/scripts/carbon-config-editor" ]] && cp -f "$CONFIG_DIR/scripts/carbon-config-editor" "$BIN_DIR/carbon-config-editor"
[[ -f "$CONFIG_DIR/scripts/carbon-pomodoro" ]] && cp -f "$CONFIG_DIR/scripts/carbon-pomodoro" "$BIN_DIR/carbon-pomodoro"
[[ -f "$CONFIG_DIR/scripts/carbon-settings-hub" ]] && cp -f "$CONFIG_DIR/scripts/carbon-settings-hub" "$BIN_DIR/carbon-settings-hub"

for s in "$CONFIG_DIR/scripts/carbon-screenshot-"*.sh; do
    if [[ -f "$s" ]]; then
        base="$(basename "$s" .sh)"
        cp -f "$s" "$BIN_DIR/$base"
        cp -f "$s" "$BIN_DIR/$base.sh"
    fi
done
chmod +x "$BIN_DIR/carbon-"* 2>/dev/null || true
ok "User binaries installed to ~/.local/bin"

# ── Refresh Fonts ─────────────────────────────────────────────────────────────
if [[ -d "$REPO_DIR/fonts" ]]; then
    mkdir -p "$HOME/.local/share/fonts"
    cp -f "$REPO_DIR/fonts/"*.ttf "$HOME/.local/share/fonts/" 2>/dev/null || true
    command -v fc-cache >/dev/null 2>&1 && fc-cache -f >/dev/null 2>&1 || true
fi

# ── Refresh Mode Keybinds ─────────────────────────────────────────────────────
if [[ -f "$CONFIG_DIR/scripts/carbon-mode-keybinds.sh" ]]; then
    bash "$CONFIG_DIR/scripts/carbon-mode-keybinds.sh" >/dev/null 2>&1 || true
fi

# Build & deploy Rust apps
if command -v cargo >/dev/null 2>&1 && [[ -d "$REPO_DIR/apps" ]]; then
    msg "Compiling Carbon backend apps..."
    for app_dir in "$REPO_DIR/apps/"*; do
        if [[ -d "$app_dir" && -f "$app_dir/Cargo.toml" ]]; then
            (cd "$app_dir" && cargo build --release 2>/dev/null && cp -f target/release/carbon-* "$BIN_DIR/" 2>/dev/null) || true
        fi
    done
fi

# ── Reload Services ───────────────────────────────────────────────────────────
if [[ "$NO_RELOAD" -eq 0 ]]; then
    if prompt_confirm "Restart Carbon Quickshell, Hub Daemon, and reload Hyprland now? [Y/n]: " "Y"; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user restart carbon-hub.service 2>/dev/null || true
            if systemctl --user is-enabled carbon-quickshell.service >/dev/null 2>&1; then
                systemctl --user restart carbon-quickshell.service >/dev/null 2>&1 || true
            else
                pkill -x quickshell 2>/dev/null || true
                sleep 0.5
                nohup quickshell --config "$QUICKSHELL_DIR" >/dev/null 2>&1 &
            fi
        else
            pkill -x carbon-hub-daemon 2>/dev/null || true
            nohup "$BIN_DIR/carbon-hub-daemon" >/dev/null 2>&1 &
            pkill -x quickshell 2>/dev/null || true
            sleep 0.5
            nohup quickshell --config "$QUICKSHELL_DIR" >/dev/null 2>&1 &
        fi
        command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
        ok "Services and Hyprland reloaded"
    fi
fi

printf "\n"
msg "Carbon Shell update complete!"
