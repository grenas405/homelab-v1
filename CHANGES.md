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
- End-of-run **hardware report** as the final section:
  - Boxed **GPU (NVIDIA)** table — Name, VRAM Total, Compute Cap, Driver, CUDA —
    read from `nvidia-smi`; one row per GPU, or a "No NVIDIA GPU detected" row
    with a CPU-inference `teach` note when none is found.
  - Boxed **CPU / Memory** table — CPU model, cores / threads, total RAM — from
    `/proc/cpuinfo`, `lscpu`, `nproc`, and `/proc/meminfo`.
  - A `teach` note giving a VRAM-per-parameter rule of thumb for judging which
    models fit.
- Generic `render_table` helper: computed column widths, per-column
  left/right alignment, box-drawing glyphs that drop to ASCII (`+ - |`) when
  colour is unavailable.
- **`--dry-run` / `-n` option** (plus `--help` / `-h`): walks every step and
  prints the full banner, all logging, and the real hardware report, but
  installs nothing and changes no files. Each mutating command is shown as a
  `~ would run: …` line. The confirmation prompt is skipped in this mode.
  Intended for previewing the output on a machine that is *not* the target.
- `README.md` orientation doc.

### Changed
- All previous `echo` status lines converted to the new logging helpers.
- `ollama --version` output is now parsed for a bare semver, so the
  "already installed" line reads `(v0.12.6)` instead of echoing Ollama's
  "could not connect" warning.

### Fixed
- Removed a stray `p` after the "Python 3.12 not available in the repos."
  message.
- Header comment now documents the whole script (Ollama + model + Python +
  Open WebUI) instead of only Open WebUI.
