# Changelog

All notable changes to this homelab setup.

## 2026-09-02

### Added
- `setup.sh` now installs **Ollama** via the official installer, before the
  Open WebUI setup, with an idempotency guard so re-runs skip it.
- Automatic download of the **`qwen3:8b`** model so the stack is usable on the
  first run.
- Explicit `systemctl enable --now ollama` plus a readiness poll against
  `http://localhost:11434` before the model is pulled.
- **True-colour (24-bit ANSI) logging** with six helpers — `step`, `info`,
  `ok`, `warn`, `err`, `teach` — and a `COLORTERM`/TTY check that falls back to
  plain text when true colour is unavailable.
- `teach` "Homelab note" asides throughout the script, explaining Ollama, the
  background service, ports and `localhost`, models, virtual environments, and
  how Open WebUI connects to Ollama.
- Target-machine banner and a `yes` confirmation prompt so the script cannot be
  run on the wrong host by accident.
- `README.md` orientation doc.

### Changed
- All previous `echo` status lines converted to the new logging helpers.

### Fixed
- Removed a stray `p` after the "Python 3.12 not available in the repos."
  message.
- Header comment now documents the whole script (Ollama + model + Python +
  Open WebUI) instead of only Open WebUI.
