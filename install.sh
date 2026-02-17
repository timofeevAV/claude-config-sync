#!/usr/bin/env bash
set -euo pipefail

[ -n "${HOME:-}" ] || { echo "[x] \$HOME is not set"; exit 1; }

# ---- CONFIGURE THIS ----
REPO="${CLAUDE_CONFIG_REPO:-}"
# -------------------------

TARGET="$HOME/.claude"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[x]${NC} %s\n" "$1"; exit 1; }

command -v git >/dev/null 2>&1 || error "git is not installed"

if [ -z "$REPO" ]; then
    if [ -t 0 ]; then
        printf "Enter your git repo URL (e.g. https://github.com/user/claude-config.git): "
        read -r REPO
        [ -n "$REPO" ] || error "Repository URL is required"
    else
        error "Set CLAUDE_CONFIG_REPO env var or run interactively"
    fi
fi

# Handle existing ~/.claude
if [ -d "$TARGET" ]; then
    if [ -d "$TARGET/.git" ]; then
        info "$HOME/.claude is already a git repo — pulling latest changes"
        cd "$TARGET"
        git -c commit.gpgSign=false pull --recurse-submodules
        git submodule update --init --recursive
        info "Config is up to date."
    else
        BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
        warn "$HOME/.claude exists but is not a repo"
        warn "Backing up to $BACKUP"
        mv "$TARGET" "$BACKUP"
        chmod 700 "$BACKUP"
        info "Cloning config to ~/.claude"
        git clone --recurse-submodules "$REPO" "$TARGET"
    fi
else
    info "Cloning config to ~/.claude"
    git clone --recurse-submodules "$REPO" "$TARGET"
fi

if [ ! -f "$TARGET/settings.json" ]; then
    error "Installation failed — settings.json not found"
fi

chmod +x "$TARGET/scripts/"*.sh 2>/dev/null || true

info "Config installed successfully"

# --- Auto-sync setup ---

setup_autosync() {
    local os
    os="$(uname -s)"

    case "$os" in
        Darwin)
            info "Setting up auto-sync (macOS LaunchAgent)..."
            mkdir -p "$HOME/Library/LaunchAgents"
            sed "s|__HOME__|$HOME|g" "$TARGET/launchd/com.claude.config-sync.plist" \
                > "$HOME/Library/LaunchAgents/com.claude.config-sync.plist"
            launchctl unload "$HOME/Library/LaunchAgents/com.claude.config-sync.plist" 2>/dev/null || true
            if launchctl load "$HOME/Library/LaunchAgents/com.claude.config-sync.plist"; then
                info "LaunchAgent loaded."
            else
                warn "Failed to load LaunchAgent. Load it manually:"
                warn "  launchctl load ~/Library/LaunchAgents/com.claude.config-sync.plist"
                return 1
            fi
            ;;
        Linux)
            if command -v systemctl >/dev/null 2>&1; then
                info "Setting up auto-sync (systemd user units)..."
                local unit_dir="$HOME/.config/systemd/user"
                mkdir -p "$unit_dir"
                cp "$TARGET/systemd/claude-config-sync.service" "$unit_dir/"
                cp "$TARGET/systemd/claude-config-sync.timer"   "$unit_dir/"
                cp "$TARGET/systemd/claude-config-sync.path"    "$unit_dir/"
                systemctl --user daemon-reload
                systemctl --user enable --now claude-config-sync.path 2>/dev/null || warn "Failed to enable path watcher."
                systemctl --user enable --now claude-config-sync.timer 2>/dev/null || warn "Failed to enable timer."
                info "systemd units enabled."
            else
                warn "systemd not found. Auto-sync not configured."
                warn "Run ~/.claude/scripts/auto-sync.sh manually or via cron."
            fi
            ;;
        *)
            warn "Unsupported OS ($os). Auto-sync not configured."
            warn "Run ~/.claude/scripts/auto-sync.sh manually or via cron."
            ;;
    esac
}

echo ""
if [ -t 0 ]; then
    read -rp "Enable auto-sync (bidirectional config sync)? [Y/n] " answer
else
    warn "Non-interactive mode. Skipping auto-sync setup."
    answer="n"
fi
case "${answer:-y}" in
    [yY]|[yY][eE][sS]|"")
        setup_autosync || true
        ;;
    *)
        info "Skipped auto-sync. Set it up later: cd ~/.claude && make install-autosync"
        ;;
esac

echo ""
info "Installation complete. Restart Claude Code to apply."
