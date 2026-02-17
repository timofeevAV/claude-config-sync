# Claude Config Sync

Bidirectional sync for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configuration (`~/.claude`) across multiple machines.

## What it does

Keeps your Claude Code settings, skills, agents, commands, and hooks in sync via a git repo. When you change something on one machine, all others pick up the changes automatically.

**Algorithm:** commit local changes → fetch remote → detect state → fast-forward / rebase / push.

**Features:**

- Cross-platform: macOS (launchd) + Linux (systemd)
- Atomic locking (prevents concurrent runs)
- Auto-recovery from interrupted rebase/merge
- Submodule support with upstream auto-update
- 5-second debounce to coalesce rapid edits
- Log rotation (500 lines max)
- Graceful offline mode — local commits preserved until next successful fetch
- Native OS notifications on conflicts and errors (macOS: Notification Center, Linux: notify-send)

## Quick start

### 1. Create your config repo

Create an empty git repo (GitHub, GitLab, etc.) and initialize `~/.claude`:

```bash
cd ~/.claude
git init
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
```

### 2. Copy sync files into your repo

```bash
# From this template:
cp -r scripts/ launchd/ systemd/ Makefile .gitignore ~/. claude/
chmod +x ~/.claude/scripts/auto-sync.sh
```

### 3. Initial commit and push

```bash
cd ~/.claude
git add -A
git commit -m "initial config"
git push -u origin main
```

### 4. Enable auto-sync

```bash
cd ~/.claude && make install-autosync
```

### Installing on another machine

Option A — use the install script:

```bash
CLAUDE_CONFIG_REPO=https://github.com/YOUR_USER/YOUR_REPO.git \
  bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/install.sh)
```

Option B — manual clone:

```bash
git clone --recurse-submodules https://github.com/YOUR_USER/YOUR_REPO.git ~/.claude
cd ~/.claude && make install-autosync
```

## Makefile

All operations are available via `make` from `~/.claude`:

| Command | Description |
|---------|-------------|
| `make sync` | Run bidirectional sync now (skip debounce) |
| `make status` | Show sync status and local changes |
| `make log` | Show recent sync log (last 20 entries) |
| `make log-full` | Show full sync log |
| `make diff` | Show uncommitted changes |
| `make update-submodules` | Pull latest submodule versions from upstream |
| `make install-autosync` | Set up auto-sync daemon for current OS |
| `make uninstall-autosync` | Remove auto-sync daemon |

## How auto-sync works

The sync script runs automatically when config files change (via filesystem watcher) and periodically as a safety net (every 4 hours).

**States and actions:**

| Local vs Remote | Action |
|----------------|--------|
| Equal | Nothing to do |
| Ahead | `git push` |
| Behind | `git merge --ff-only` |
| Diverged | `git rebase` + `git push` |
| Conflict | Abort rebase, notify user, log resolution command |

**Notifications:**

On macOS, you'll get a Notification Center alert when something goes wrong (conflict, push failure). On Linux, `notify-send` is used if available. Errors are always logged to `~/.claude/scripts/sync.log`.

<details>
<summary>macOS (LaunchAgent) — manual setup</summary>

```bash
mkdir -p ~/Library/LaunchAgents
sed "s|__HOME__|$HOME|g" ~/.claude/launchd/com.claude.config-sync.plist \
  > ~/Library/LaunchAgents/com.claude.config-sync.plist
launchctl load ~/Library/LaunchAgents/com.claude.config-sync.plist
```

</details>

<details>
<summary>Linux (systemd) — manual setup</summary>

```bash
mkdir -p ~/.config/systemd/user
cp ~/.claude/systemd/claude-config-sync.{service,timer,path} ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now claude-config-sync.path
systemctl --user enable --now claude-config-sync.timer
```

</details>

<details>
<summary>Other / cron</summary>

```bash
# One-time sync
~/.claude/scripts/auto-sync.sh --now

# Cron (every 30 min)
(crontab -l 2>/dev/null; echo "*/30 * * * * \$HOME/.claude/scripts/auto-sync.sh") | crontab -
```

</details>

## What to put in .gitignore

The included `.gitignore` excludes all ephemeral Claude Code data (history, caches, telemetry, session state). Only your settings, skills, agents, commands, and hooks are tracked.

## File structure

```
~/.claude/
├── settings.json              # Claude Code settings
├── skills/                    # Custom skills
├── agents/                    # Agent definitions
├── commands/                  # Slash commands
├── hooks/                     # Session hooks
├── scripts/
│   └── auto-sync.sh           # Sync script
├── launchd/
│   └── com.claude.config-sync.plist  # macOS template
├── systemd/
│   ├── claude-config-sync.service    # Linux service
│   ├── claude-config-sync.timer      # Linux timer
│   └── claude-config-sync.path       # Linux path watcher
├── Makefile                   # Convenience commands
├── install.sh                 # One-line installer
└── .gitignore                 # Excludes ephemeral data
```

## License

MIT
