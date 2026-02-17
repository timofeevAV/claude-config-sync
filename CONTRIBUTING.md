# Contributing

## Requirements

- Bash 4+
- [ShellCheck](https://www.shellcheck.net/) — shell script linter
- Git

## Project structure

```
scripts/auto-sync.sh   — main sync script
install.sh             — one-line installer
Makefile               — user-facing commands (sync, status, log, ...)
launchd/               — macOS LaunchAgent (plist template)
systemd/               — Linux systemd units (service, timer, path)
settings.json          — default Claude Code config
.github/workflows/     — CI (ShellCheck) and Release (on v* tag)
```

## Workflow

1. Fork the repo, create a branch from `main`
2. Make your changes
3. Run ShellCheck locally:
   ```bash
   shellcheck scripts/auto-sync.sh install.sh
   ```
4. Open a PR to `main`

CI runs ShellCheck automatically. PRs won't merge until CI passes.

## Code guidelines

- All scripts must start with `#!/usr/bin/env bash` and `set -euo pipefail`
- ShellCheck must pass with no errors or warnings
- Avoid bashisms that break POSIX compatibility unless explicitly needed
- New scripts must be added to CI (`ci.yml`)

## Commits

Format: [Conventional Commits](https://www.conventionalcommits.org/)

```
fix: bug description
feat: feature description
docs: what changed in documentation
```

## Ideas for contribution

- Support for new OSes / init systems
- Conflict resolution improvements
- New Makefile commands
- Tests (bats / shunit2)
- Documentation

## Releases

Releases are created automatically on `v*` tag push. Changelog is generated from commits.

## License

Contributions are accepted under the [MIT License](LICENSE).
