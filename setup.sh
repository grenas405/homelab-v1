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
#   ./setup.sh              # real install (asks for confirmation first)
#   ./setup.sh --dry-run    # print every step and all logging, change nothing
#

set -e  # stop immediately if any command fails

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ENV_DIR="$HOME/openwebui-env"
OLLAMA_MODEL="qwen3:8b"
TARGET_MACHINE="Eric Harvey's Workstation"

# ---------------------------------------------------------------------------
# Command-line options
#
#   --dry-run / -n : walk through every step and print all logging, the
#                    banner, and the real hardware report, but do not install
#                    anything, touch systemd, or modify any files. Useful for
#                    previewing the output on a machine that is NOT the target.
# ---------------------------------------------------------------------------
DRY_RUN=0
for _arg in "$@"; do
    case "$_arg" in
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help)
            printf 'Usage: %s [--dry-run|-n] [--help|-h]\n\n' "${0##*/}"
            printf '  --dry-run  Show every step and all logging without installing\n'
            printf '             anything or changing the system.\n'
            exit 0 ;;
        *)
            printf 'Unknown option: %s\n' "$_arg" >&2
            printf 'Usage: %s [--dry-run|-n] [--help|-h]\n' "${0##*/}" >&2
            exit 1 ;;
    esac
done

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
would() { printf '%s   ~ would run: %s%s\n' "$(_col '150;170;190')" "$*" "$(_reset)"; }

# ---------------------------------------------------------------------------
# Boxed-table renderer
#
#   render_table "Title" "H1|H2|..." "L|R|..." "r1c1|r1c2|..." "r2c1|..."
#     arg 1  : title line printed above the table ("" for none)
#     arg 2  : pipe-separated header cells
#     arg 3  : pipe-separated alignment flags (L or R), one per column
#     arg 4+ : pipe-separated data rows
#
# Column widths are measured from the widest cell. Box-drawing glyphs are used
# on colour-capable terminals and plain ASCII (+ - |) everywhere else, so the
# report stays readable when piped to a file.
# ---------------------------------------------------------------------------
if [[ $USE_COLOR -eq 1 ]]; then
    BX_TL='┌'; BX_TR='┐'; BX_BL='└'; BX_BR='┘'; BX_H='─'; BX_V='│'
    BX_TT='┬'; BX_BT='┴'; BX_LT='├'; BX_RT='┤'; BX_X='┼'
else
    BX_TL='+'; BX_TR='+'; BX_BL='+'; BX_BR='+'; BX_H='-'; BX_V='|'
    BX_TT='+'; BX_BT='+'; BX_LT='+'; BX_RT='+'; BX_X='+'
fi

_repeat() {  # _repeat <count> <string>
    local n=$1 s=$2 out=''
    while (( n > 0 )); do out+="$s"; n=$((n - 1)); done
    printf '%s' "$out"
}

render_table() {
    local title="$1"; shift
    local header="$1"; shift
    local aligns="$1"; shift
    local rows=( "$@" )

    local IFS='|'
    local -a H A
    read -r -a H <<< "$header"
    read -r -a A <<< "$aligns"
    local ncol=${#H[@]}

    local -a W
    local i row
    local -a C
    for (( i = 0; i < ncol; i++ )); do W[i]=${#H[i]}; done
    for row in "${rows[@]}"; do
        read -r -a C <<< "$row"
        for (( i = 0; i < ncol; i++ )); do
            if (( ${#C[i]} > W[i] )); then W[i]=${#C[i]}; fi
        done
    done

    _rule() {  # _rule <left-glyph> <mid-glyph> <right-glyph>
        local out="$1" k
        for (( k = 0; k < ncol; k++ )); do
            out+="$(_repeat $(( W[k] + 2 )) "$BX_H")"
            if (( k < ncol - 1 )); then out+="$2"; else out+="$3"; fi
        done
        printf '%s%s%s\n' "$(_col '90;110;130')" "$out" "$(_reset)"
    }

    _line() {  # _line <cell> <cell> ...
        local -a cells=( "$@" )
        local out='' k pad
        for (( k = 0; k < ncol; k++ )); do
            if [[ "${A[k]:-L}" == "R" ]]; then
                printf -v pad '%*s'  "${W[k]}" "${cells[k]}"
            else
                printf -v pad '%-*s' "${W[k]}" "${cells[k]}"
            fi
            out+="${BX_V} ${pad} "
        done
        printf '%s%s\n' "$out" "${BX_V}"
    }

    if [[ -n "$title" ]]; then
        printf '%s%s%s\n' "$(_col '120;200;255')" "$title" "$(_reset)"
    fi
    _rule "$BX_TL" "$BX_TT" "$BX_TR"
    _line "${H[@]}"
    _rule "$BX_LT" "$BX_X" "$BX_RT"
    for row in "${rows[@]}"; do
        read -r -a C <<< "$row"
        _line "${C[@]}"
    done
    _rule "$BX_BL" "$BX_BT" "$BX_BR"
}

# ---------------------------------------------------------------------------
# Target-machine guard
# ---------------------------------------------------------------------------
printf '%s════════════════════════════════════════════════════════════%s\n' "$(_col '120;200;255')" "$(_reset)"
printf '%s  Homelab AI stack installer%s\n'  "$(_col '120;200;255')" "$(_reset)"
printf '%s  Intended for: %s%s\n'            "$(_col '120;200;255')" "$TARGET_MACHINE" "$(_reset)"
printf '%s════════════════════════════════════════════════════════════%s\n' "$(_col '120;200;255')" "$(_reset)"
echo
if [[ $DRY_RUN -eq 1 ]]; then
    warn "DRY RUN — no packages, services, or files will be changed."
    warn "Each step below shows what it *would* do; the hardware report is real."
    echo
    ok "Dry run: skipping the confirmation prompt."
else
    warn "This installs Ollama, a language model, and Open WebUI on THIS machine."
    warn "It is meant only for $TARGET_MACHINE — not a shared VM."
    echo
    read -r -p "Type 'yes' to confirm you are on $TARGET_MACHINE: " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then
        err "Not confirmed. Nothing has been changed. Exiting."
        exit 1
    fi
    ok "Confirmed. Starting setup."
fi

# ---------------------------------------------------------------------------
step "Step 1 — Install Ollama"
# ---------------------------------------------------------------------------
teach "Ollama is a small server that runs large language models on your own"
teach "hardware. Anything you type stays on this machine. Other programs talk"
teach "to it over HTTP on port 11434."

if [[ $DRY_RUN -eq 1 ]]; then
    if command -v ollama >/dev/null 2>&1; then
        ok "Ollama is already installed (v$(ollama --version 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)+" | head -n1))."
    else
        would "curl -fsSL https://ollama.com/install.sh | sh"
    fi
    would "sudo systemctl enable --now ollama"
    would "poll http://localhost:11434/api/tags until the API answers"
else
    if command -v ollama >/dev/null 2>&1; then
        ok "Ollama is already installed (v$(ollama --version 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)+" | head -n1)). Skipping install."
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
fi

teach "A 'service' is a program the system keeps running in the background"
teach "for you, restarting it after a reboot without anyone logging in."
teach "'localhost' means this computer talking to itself. Port 11434 is the"
teach "door number the Ollama API listens on."

# ---------------------------------------------------------------------------
step "Step 2 — Download the $OLLAMA_MODEL language model"
# ---------------------------------------------------------------------------
teach "A 'model' is the trained network that actually generates text. Bigger"
teach "models are more capable but use more disk and memory. qwen3:8b is a"
teach "strong general-purpose model that still runs comfortably on a workstation."

if [[ $DRY_RUN -eq 1 ]]; then
    would "ollama pull $OLLAMA_MODEL   (multi-gigabyte download)"
elif ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$OLLAMA_MODEL"; then
    ok "Model $OLLAMA_MODEL is already downloaded."
else
    info "Pulling $OLLAMA_MODEL — this is a multi-gigabyte download and can take a while..."
    ollama pull "$OLLAMA_MODEL"
    ok "Model $OLLAMA_MODEL is ready."
fi

# ---------------------------------------------------------------------------
step "Step 3 — Prepare a clean Python environment for Open WebUI"
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
    if [ -d "$ENV_DIR" ]; then
        would "rm -rf $ENV_DIR   (remove the existing environment)"
    else
        info "No existing environment at $ENV_DIR — nothing to remove."
    fi
elif [ -d "$ENV_DIR" ]; then
    info "Found an existing environment at $ENV_DIR — removing it to start clean..."
    rm -rf "$ENV_DIR"
    ok "Old environment removed."
fi
teach "Open WebUI is a Python program. We give it its own private 'virtual"
teach "environment' so its libraries never collide with the system's Python."

# ---------------------------------------------------------------------------
step "Step 4 — Make sure a suitable Python is available"
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
    would "sudo apt update"
    would "sudo apt install -y python3.12 python3.12-venv"
    info "If Python 3.12 is unavailable, the real run instead:"
    would "  sudo apt install -y build-essential libssl-dev ... (pyenv build deps)"
    would "  curl https://pyenv.run | bash"
    would "  append pyenv init lines to ~/.bashrc"
    would "  pyenv install 3.11.9"
    PYTHON_BIN="python3.12"
    teach "pyenv builds a private copy of Python from source, kept under"
    teach "~/.pyenv, without touching the Python the system itself relies on."
else
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
fi     # end: Python 3.12 vs 3.11 fallback
fi     # end: dry-run vs real

# ---------------------------------------------------------------------------
step "Step 5 — Create the virtual environment and install Open WebUI"
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
    would "$PYTHON_BIN -m venv $ENV_DIR"
    would "source $ENV_DIR/bin/activate"
    would "pip install --upgrade pip"
    would "pip install open-webui"
else
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
fi

teach "Open WebUI is the chat website you open in a browser. It does not run"
teach "any models itself — it forwards your messages to Ollama on port 11434"
teach "and shows you the replies. Two programs, one job each."

# ---------------------------------------------------------------------------
step "Setup complete"
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 1 ]]; then
    ok "Dry run finished — nothing was installed or changed."
else
    ok "Ollama is running with the $OLLAMA_MODEL model."
    ok "Open WebUI is installed in $ENV_DIR."
fi
echo
info "To start Open WebUI now, or again after a reboot, run:"
info "    source $ENV_DIR/bin/activate"
info "    open-webui serve"
echo
info "Then open http://localhost:8080 in your browser."
teach "On first launch Open WebUI asks you to create a local account. That"
teach "account lives only on this machine. Pick $OLLAMA_MODEL in the model"
teach "menu at the top and start chatting."

# ---------------------------------------------------------------------------
step "Your workstation's hardware"
# ---------------------------------------------------------------------------
teach "This is what Ollama has to work with. On the GPU, VRAM total is the"
teach "number that decides which models fit."

# --- GPU (NVIDIA) ---
gpu_rows=()
no_gpu=0
if command -v nvidia-smi >/dev/null 2>&1; then
    cuda_ver=$(nvidia-smi 2>/dev/null | sed -n 's/.*CUDA Version: *\([0-9.]\{1,\}\).*/\1/p' | head -n1)
    [[ -n "$cuda_ver" ]] || cuda_ver="-"

    mapfile -t _gpu_base < <(nvidia-smi --query-gpu=name,memory.total,driver_version \
        --format=csv,noheader,nounits 2>/dev/null)
    mapfile -t _gpu_cc < <(nvidia-smi --query-gpu=compute_cap \
        --format=csv,noheader,nounits 2>/dev/null)

    gi=0
    for _l in "${_gpu_base[@]}"; do
        IFS=',' read -r _name _mem _drv <<< "$_l"
        _name=$(printf '%s' "$_name" | sed 's/^ *//; s/ *$//')
        _mem=$(printf '%s' "$_mem" | tr -d ' ')
        _drv=$(printf '%s' "$_drv" | tr -d ' ')
        _gib=$(awk -v m="$_mem" 'BEGIN { if (m ~ /^[0-9.]+$/) printf "%.1f GiB", m / 1024; else printf "-" }')
        _cc=$(printf '%s' "${_gpu_cc[gi]:-}" | tr -d ' ')
        [[ -n "$_cc" && "$_cc" != "[NotSupported]" ]] || _cc="-"
        gpu_rows+=( "${_name}|${_gib}|${_cc}|${_drv}|${cuda_ver}" )
        gi=$((gi + 1))
    done
fi

if [[ ${#gpu_rows[@]} -eq 0 ]]; then
    no_gpu=1
    gpu_rows=( "No NVIDIA GPU detected|-|-|-|-" )
fi

render_table "GPU (NVIDIA)" \
    "Name|VRAM Total|Compute Cap|Driver|CUDA" \
    "L|R|R|R|R" \
    "${gpu_rows[@]}"

echo

# --- CPU / Memory ---
cpu_model=$(sed -n 's/^model name[[:space:]]*:[[:space:]]*//p' /proc/cpuinfo 2>/dev/null | head -n1)
[[ -n "$cpu_model" ]] || cpu_model=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -n1)
[[ -n "$cpu_model" ]] || cpu_model="-"

threads=$(nproc 2>/dev/null || echo "")
[[ -n "$threads" ]] || threads="-"
phys_cores=$(lscpu 2>/dev/null | awk -F': +' '
    /^Core\(s\) per socket/ { c = $2 }
    /^Socket\(s\)/          { s = $2 }
    END { if (c != "" && s != "") print c * s }')
[[ -n "$phys_cores" ]] || phys_cores="-"

ram_total=$(awk '/^MemTotal:/ { printf "%.1f GiB", $2 / 1048576 }' /proc/meminfo 2>/dev/null)
[[ -n "$ram_total" ]] || ram_total="-"

render_table "CPU / Memory" \
    "Field|Value" \
    "L|L" \
    "CPU|${cpu_model}" \
    "Cores / Threads|${phys_cores} / ${threads}" \
    "Total RAM|${ram_total}"

echo
teach "Rule of thumb: a 4-bit-quantized model needs roughly its parameter"
teach "count in billions times 0.6–0.75 GiB of VRAM to run entirely on the"
teach "GPU. With less, Ollama splits it between GPU and system RAM and runs"
teach "slower. $OLLAMA_MODEL at Q4 needs about 5–6 GiB of VRAM."
if [[ $no_gpu -eq 1 ]]; then
    teach "No NVIDIA GPU was found here, so $OLLAMA_MODEL runs on the CPU using"
    teach "system RAM. It still works — just expect slower replies."
fi
