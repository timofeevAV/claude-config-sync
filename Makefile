.DEFAULT_GOAL := help
SHELL := /bin/bash
REPO := $(HOME)/.claude

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

sync: ## Run bidirectional sync now (skip debounce)
	@$(REPO)/scripts/auto-sync.sh --now

status: ## Show sync status and local changes
	@echo "Branch:"
	@cd $(REPO) && git branch -v
	@echo ""
	@echo "Remote:"
	@cd $(REPO) && git remote -v
	@echo ""
	@echo "Changes:"
	@cd $(REPO) && git status --short || true
	@echo ""
	@echo "Submodules:"
	@cd $(REPO) && git submodule status 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "Last sync:"
	@tail -1 $(REPO)/scripts/sync.log 2>/dev/null || echo "  (no log yet)"

log: ## Show recent sync log (last 20 entries)
	@tail -20 $(REPO)/scripts/sync.log 2>/dev/null || echo "No sync log found."

log-full: ## Show full sync log
	@cat $(REPO)/scripts/sync.log 2>/dev/null || echo "No sync log found."

diff: ## Show uncommitted changes
	@cd $(REPO) && git diff
	@cd $(REPO) && git diff --cached
	@cd $(REPO) && git ls-files --others --exclude-standard

update-submodules: ## Pull latest submodule versions from upstream
	@cd $(REPO) && git submodule update --remote --init --recursive
	@echo "Done. Run 'make sync' to commit and push."

install-autosync: ## Set up auto-sync daemon for current OS
	@OS=$$(uname -s); \
	case "$$OS" in \
		Darwin) \
			echo "Setting up macOS LaunchAgent..."; \
			mkdir -p $(HOME)/Library/LaunchAgents; \
			sed "s|__HOME__|$(HOME)|g" $(REPO)/launchd/com.claude.config-sync.plist \
				> $(HOME)/Library/LaunchAgents/com.claude.config-sync.plist; \
			launchctl unload $(HOME)/Library/LaunchAgents/com.claude.config-sync.plist 2>/dev/null || true; \
			launchctl load $(HOME)/Library/LaunchAgents/com.claude.config-sync.plist; \
			echo "Done. LaunchAgent loaded."; \
			;; \
		Linux) \
			echo "Setting up systemd user units..."; \
			mkdir -p $(HOME)/.config/systemd/user; \
			cp $(REPO)/systemd/claude-config-sync.service $(HOME)/.config/systemd/user/; \
			cp $(REPO)/systemd/claude-config-sync.timer   $(HOME)/.config/systemd/user/; \
			cp $(REPO)/systemd/claude-config-sync.path    $(HOME)/.config/systemd/user/; \
			systemctl --user daemon-reload; \
			systemctl --user enable --now claude-config-sync.path; \
			systemctl --user enable --now claude-config-sync.timer; \
			echo "Done. systemd units enabled."; \
			;; \
		*) \
			echo "Unsupported OS ($$OS). Run scripts/auto-sync.sh manually."; \
			;; \
	esac

uninstall-autosync: ## Remove auto-sync daemon
	@OS=$$(uname -s); \
	case "$$OS" in \
		Darwin) \
			launchctl unload $(HOME)/Library/LaunchAgents/com.claude.config-sync.plist 2>/dev/null || true; \
			rm -f $(HOME)/Library/LaunchAgents/com.claude.config-sync.plist; \
			echo "LaunchAgent removed."; \
			;; \
		Linux) \
			systemctl --user disable --now claude-config-sync.path 2>/dev/null || true; \
			systemctl --user disable --now claude-config-sync.timer 2>/dev/null || true; \
			rm -f $(HOME)/.config/systemd/user/claude-config-sync.{service,timer,path}; \
			systemctl --user daemon-reload; \
			echo "systemd units removed."; \
			;; \
		*) \
			echo "Nothing to uninstall."; \
			;; \
	esac

.PHONY: help sync status log log-full diff update-submodules install-autosync uninstall-autosync
