#!/bin/bash
#
# setup.sh
#
# Provisions the local AI stack on Eric Harvey's Workstation:
#
#   1. Ollama       - runs large language models locally and serves them over
#                     an HTTP API on port 11434. Nothing leaves the machine.
#   2. qwen3:8b     - a capable general-purpose model, pulled so there is
#                     something to talk to on the very first run.
#   3. Python 3.12  - an isolated interpreter for Open WebUI. Python 3.11 is
#      (or 3.11)      built from source with pyenv only if 3.12 is unavailable.
#   4. Open WebUI   - a browser chat interface (port 8080) that uses Ollama as
#                     its backend.
#
# The script narrates every step with colour-coded logging and "Homelab note"
# asides, so a run doubles as a guided tour of the stack.
#
# Target machine : Eric Harvey's Workstation  (NOT a shared VM)
# Base OS        : MX Linux / Debian-based
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#

set -e  # stop immediately if any command fails

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ENV_DIR="$HOME/openwebui-env"
OLLAMA_MODEL="qwen3:8b"
TARGET_MACHINE="Eric Harvey's Workstation"

# ---------------------------------------------------------------------------
# True-colour logging helpers
#
# Terminals that support 24-bit colour advertise it via COLORTERM=truecolor
# (or 24bit). If that is missing, or output is not a terminal (for example
# when piped to a file), we fall back to plain text so the log stays readable
# everywhere.
# ---------------------------------------------------------------------------
if [[ -t 1 && ( "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ) ]]; then
    USE_COLOR=1
else
    USE_COLOR=0
fi

_col()   { [[ $USE_COLOR -eq 1 ]] && printf '\033[38;2;%sm' "$1" || true; }
_reset() { [[ $USE_COLOR -eq 1 ]] && printf '\033[0m' || true; }

step()  { printf '\n%s▶ %s%s\n'   "$(_col '80;250;250')"  "$*" "$(_reset)"; }
info()  { printf '%s   %s%s\n'    "$(_col '150;150;150')" "$*" "$(_reset)"; }
ok()    { printf '%s   ✔ %s%s\n'  "$(_col '120;220;120')" "$*" "$(_reset)"; }
warn()  { printf '%s   ⚠ %s%s\n'  "$(_col '240;190;90')"  "$*" "$(_reset)"; }
err()   { printf '%s   ✗ %s%s\n'  "$(_col '240;100;100')" "$*" "$(_reset)" >&2; }
teach() { printf '%s   🎓 %s%s\n' "$(_col '180;140;250')" "$*" "$(_reset)"; }

# ---------------------------------------------------------------------------
# Target-machine guard
# ---------------------------------------------------------------------------
printf '%s════════════════════════════════════════════════════════════%s\n' "$(_col '120;200;255')" "$(_reset)"
printf '%s  Homelab AI stack installer%s\n'  "$(_col '120;200;255')" "$(_reset)"
printf '%s  Intended for: %s%s\n'            "$(_col '120;200;255')" "$TARGET_MACHINE" "$(_reset)"
printf '%s════════════════════════════════════════════════════════════%s\n' "$(_col '120;200;255')" "$(_reset)"
echo
warn "This installs Ollama, a language model, and Open WebUI on THIS machine."
warn "It is meant only for $TARGET_MACHINE — not a shared VM."
echo
read -r -p "Type 'yes' to confirm you are on $TARGET_MACHINE: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    err "Not confirmed. Nothing has been changed. Exiting."
    exit 1
fi
ok "Confirmed. Starting setup."

# ---------------------------------------------------------------------------
step "Step 1 — Install Ollama"
# ---------------------------------------------------------------------------
teach "Ollama is a small server that runs large language models on your own"
teach "hardware. Anything you type stays on this machine. Other programs talk"
teach "to it over HTTP on port 11434."

if command -v ollama >/dev/null 2>&1; then
    ok "Ollama is already installed ($(ollama --version 2>/dev/null | head -n1)). Skipping install."
else
    info "Downloading and running the official installer from https://ollama.com ..."
    curl -fsSL https://ollama.com/install.sh | sh
    ok "Ollama installed."
fi

# Make sure the background service is running and will start on boot.
if command -v systemctl >/dev/null 2>&1; then
    info "Enabling the ollama system service so it starts automatically on boot..."
    sudo systemctl enable --now ollama 2>/dev/null \
        || warn "Could not manage the ollama service with systemctl (it may already be running)."
    teach "A 'service' is a program the system keeps running in the background"
    teach "for you, restarting it after a reboot without anyone logging in."
fi

# Wait for the API to answer before asking it to do anything.
info "Waiting for the Ollama API to respond on http://localhost:11434 ..."
READY=0
for _ in $(seq 1 30); do
    if curl -fsS http://localhost:11434/api/tags >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done
if [[ $READY -eq 1 ]]; then
    ok "Ollama API is up."
else
    err "Ollama API did not respond after 30 seconds. Check: systemctl status ollama"
    exit 1
fi
teach "'localhost' means this computer talking to itself. Port 11434 is the"
teach "door number the Ollama API listens on."

# ---------------------------------------------------------------------------
step "Step 2 — Download the $OLLAMA_MODEL language model"
# ---------------------------------------------------------------------------
teach "A 'model' is the trained network that actually generates text. Bigger"
teach "models are more capable but use more disk and memory. qwen3:8b is a"
teach "strong general-purpose model that still runs comfortably on a workstation."

if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$OLLAMA_MODEL"; then
    ok "Model $OLLAMA_MODEL is already downloaded."
else
    info "Pulling $OLLAMA_MODEL — this is a multi-gigabyte download and can take a while..."
    ollama pull "$OLLAMA_MODEL"
    ok "Model $OLLAMA_MODEL is ready."
fi

# ---------------------------------------------------------------------------
step "Step 3 — Prepare a clean Python environment for Open WebUI"
# ---------------------------------------------------------------------------
if [ -d "$ENV_DIR" ]; then
    info "Found an existing environment at $ENV_DIR — removing it to start clean..."
    rm -rf "$ENV_DIR"
    ok "Old environment removed."
fi
teach "Open WebUI is a Python program. We give it its own private 'virtual"
teach "environment' so its libraries never collide with the system's Python."

# ---------------------------------------------------------------------------
step "Step 4 — Make sure a suitable Python is available"
# ---------------------------------------------------------------------------
info "Checking for Python 3.12 in the system repositories..."
sudo apt update -qq

if sudo apt install -y python3.12 python3.12-venv 2>/dev/null; then
    PYTHON_BIN="python3.12"
    ok "Python 3.12 is installed."
else
    warn "Python 3.12 is not available in the repositories."
    info "Falling back to building Python 3.11 with pyenv..."

    info "Installing build dependencies for pyenv..."
    sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils \
        tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

    if [ ! -d "$HOME/.pyenv" ]; then
        info "Installing pyenv..."
        curl https://pyenv.run | bash
    fi

    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # Add pyenv to .bashrc permanently if not already there.
    if ! grep -q 'PYENV_ROOT' "$HOME/.bashrc"; then
        info "Adding pyenv to ~/.bashrc so it is available in future shells..."
        {
            echo 'export PYENV_ROOT="$HOME/.pyenv"'
            echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
            echo 'eval "$(pyenv init -)"'
        } >> "$HOME/.bashrc"
    fi

    if ! pyenv versions --bare | grep -q "^3.11"; then
        info "Compiling Python 3.11.9 — this can take 5-10 minutes..."
        pyenv install 3.11.9
    fi

    PYTHON_BIN="$HOME/.pyenv/versions/3.11.9/bin/python3"
    ok "Python 3.11.9 is ready."
    teach "pyenv builds a private copy of Python from source, kept under"
    teach "~/.pyenv, without touching the Python the system itself relies on."
fi

# ---------------------------------------------------------------------------
step "Step 5 — Create the virtual environment and install Open WebUI"
# ---------------------------------------------------------------------------
info "Creating the virtual environment at $ENV_DIR using $PYTHON_BIN..."
"$PYTHON_BIN" -m venv "$ENV_DIR"

# shellcheck disable=SC1091
source "$ENV_DIR/bin/activate"
info "Active Python version: $(python3 --version)"

info "Upgrading pip..."
pip install --upgrade pip

info "Installing Open WebUI — this may take a few minutes..."
pip install open-webui
ok "Open WebUI is installed."

teach "Open WebUI is the chat website you open in a browser. It does not run"
teach "any models itself — it forwards your messages to Ollama on port 11434"
teach "and shows you the replies. Two programs, one job each."

# ---------------------------------------------------------------------------
step "Setup complete"
# ---------------------------------------------------------------------------
ok "Ollama is running with the $OLLAMA_MODEL model."
ok "Open WebUI is installed in $ENV_DIR."
echo
info "To start Open WebUI now, or again after a reboot, run:"
info "    source $ENV_DIR/bin/activate"
info "    open-webui serve"
echo
info "Then open http://localhost:8080 in your browser."
teach "On first launch Open WebUI asks you to create a local account. That"
teach "account lives only on this machine. Pick $OLLAMA_MODEL in the model"
teach "menu at the top and start chatting."
