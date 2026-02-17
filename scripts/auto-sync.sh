#!/usr/bin/env bash
# Bidirectional git sync for Claude Code config.
# Algorithm: commit local → fetch → detect state → merge/rebase → push.
# Cross-platform: macOS (launchd) + Linux (systemd).
set -euo pipefail

REPO="$HOME/.claude"
BRANCH="main"
REMOTE="origin"
LOCK_DIR="${TMPDIR:-/tmp}/claude-config-sync.lock"
LOG="$REPO/scripts/sync.log"
MAX_LOG_LINES=500
DEBOUNCE_SEC=5

if [[ "${1:-}" == "--now" ]]; then
    DEBOUNCE_SEC=0
fi

# --- Helpers ---

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

file_mtime() {
    case "$(uname -s)" in
        Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
        *)      stat -c %Y "$1" 2>/dev/null || echo 0 ;;
    esac
}

trim_log() {
    if [ -f "$LOG" ] && [ "$(wc -l < "$LOG")" -gt "$MAX_LOG_LINES" ]; then
        tail -n "$MAX_LOG_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}

cleanup() {
    rm -rf "$LOCK_DIR"
    trim_log
}

has_local_changes() {
    ! git diff --quiet 2>/dev/null ||
    ! git diff --cached --quiet 2>/dev/null ||
    [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]
}

build_commit_message() {
    local summary timestamp
    summary=$(git diff --cached --name-only 2>/dev/null | awk -F/ '{
        if ($1 == "skills")        { skills++ }
        else if ($1 == "agents")   { agents++ }
        else if ($1 == "commands") { commands++ }
        else if ($1 == "hooks")    { hooks++ }
        else if ($0 == "settings.json") { settings++ }
        else { other++ }
    } END {
        msg = ""
        if (settings)  msg = msg "settings "
        if (skills)    msg = msg "skills "
        if (agents)    msg = msg "agents "
        if (commands)  msg = msg "commands "
        if (hooks)     msg = msg "hooks "
        if (other)     msg = msg "config "
        gsub(/ $/, "", msg); gsub(/ /, ", ", msg); print msg
    }')
    timestamp=$(date "+%Y-%m-%d %H:%M")
    echo "auto-sync: ${summary:-config} (${timestamp})"
}

sync_submodules() {
    [ -f "$REPO/.gitmodules" ] || return 0
    git submodule update --init --recursive 2>/dev/null || true
}

update_submodules_from_upstream() {
    [ -f "$REPO/.gitmodules" ] || return 0
    git submodule update --remote 2>/dev/null || true
}

notify() {
    local title="Claude Config Sync"
    local msg="$1"
    local level="${2:-error}"

    case "$(uname -s)" in
        Darwin)
            local sound="Basso"
            [ "$level" = "info" ] && sound="default"
            if command -v terminal-notifier >/dev/null 2>&1; then
                terminal-notifier \
                    -title "$title" \
                    -message "$msg" \
                    -sound "$sound" \
                    -execute "open '$LOG'" \
                    -group "claude-config-sync" \
                    2>/dev/null &
            else
                osascript -e "display notification \"$msg\" with title \"$title\" sound name \"$sound\"" \
                    2>/dev/null &
            fi
            ;;
        *)
            if command -v notify-send >/dev/null 2>&1; then
                local urgency="critical"
                [ "$level" = "info" ] && urgency="normal"
                notify-send -u "$urgency" -a "$title" "$title" "$msg" 2>/dev/null &
            fi
            ;;
    esac
}

# --- Pre-flight checks ---

cd "$REPO"

git_dir=$(git rev-parse --git-dir 2>/dev/null) || exit 1

# Recover from interrupted rebase/merge
if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
    log "RECOVERY: aborting stale rebase from interrupted run."
    notify "Recovered from interrupted rebase." "info"
    git rebase --abort 2>/dev/null || true
fi
if [ -f "$git_dir/MERGE_HEAD" ]; then
    log "RECOVERY: aborting stale merge from interrupted run."
    notify "Recovered from interrupted merge." "info"
    git merge --abort 2>/dev/null || true
fi

# Ensure we are on the correct branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [ "$current_branch" != "$BRANCH" ]; then
    log "ERROR: on branch '$current_branch', expected '$BRANCH'. Aborting."
    exit 1
fi

# --- Lock (atomic via mkdir) ---

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    lock_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        exit 0
    fi
    lock_age=$(( $(date +%s) - $(file_mtime "$LOCK_DIR") ))
    if [ "$lock_age" -lt 120 ]; then
        exit 0
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
trap cleanup EXIT
echo $$ > "$LOCK_DIR/pid"

# --- Debounce ---

if [ "$DEBOUNCE_SEC" -gt 0 ]; then
    sleep "$DEBOUNCE_SEC"
fi

# --- Main ---

# Step 1: Check for submodule upstream updates
update_submodules_from_upstream

# Step 2: Commit local changes (if any)
if has_local_changes; then
    git add -A
    msg=$(build_commit_message)
    git commit -m "$msg" --no-gpg-sign 2>/dev/null || true
    log "COMMIT: $msg"
fi

# Step 3: Fetch remote
if ! git fetch "$REMOTE" "$BRANCH" 2>/dev/null; then
    log "FETCH: failed (offline?). Local commit preserved."
    exit 0
fi

# Step 4: Detect state
local_head=$(git rev-parse HEAD)
if ! remote_head=$(git rev-parse "$REMOTE/$BRANCH" 2>/dev/null); then
    if git push --set-upstream "$REMOTE" "$BRANCH" 2>/dev/null; then
        log "PUSH: initial push to $REMOTE/$BRANCH."
    else
        log "PUSH: initial push failed."
    fi
    exit 0
fi

if [ "$local_head" = "$remote_head" ]; then
    log "SYNC: already up to date."
    exit 0
fi

counts=$(git rev-list --count --left-right "$REMOTE/$BRANCH...HEAD" 2>/dev/null || echo "0 0")
behind=$(echo "$counts" | awk '{print $1}')
ahead=$(echo "$counts" | awk '{print $2}')

if [ "$behind" -eq 0 ] && [ "$ahead" -gt 0 ]; then
    if git push "$REMOTE" "$BRANCH" 2>/dev/null; then
        log "PUSH: $ahead commit(s) pushed."
    else
        log "PUSH: failed. Will retry next run."
        notify "Push failed. Will retry next run."
    fi

elif [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ]; then
    if git merge --ff-only "$REMOTE/$BRANCH" 2>/dev/null; then
        sync_submodules
        log "PULL: fast-forwarded $behind commit(s)."
    else
        log "PULL: fast-forward failed. Unexpected state."
        notify "Fast-forward failed. Check sync log."
    fi

elif [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
    if git -c commit.gpgSign=false rebase "$REMOTE/$BRANCH" 2>/dev/null; then
        sync_submodules
        log "REBASE: $ahead local commit(s) rebased on $behind remote commit(s)."
        if git push "$REMOTE" "$BRANCH" 2>/dev/null; then
            log "PUSH: rebased commits pushed."
        else
            log "PUSH: failed after rebase. Will retry next run."
            notify "Push failed after rebase. Will retry."
        fi
    else
        git rebase --abort 2>/dev/null || true
        log "CONFLICT: rebase aborted. Manual resolution required."
        log "CONFLICT: run 'cd ~/.claude && git fetch origin main && git rebase origin/main' to resolve."
        notify "Sync conflict. Manual resolution required."
    fi
fi
