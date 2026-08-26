#!/bin/bash
#
# setup-openwebui.sh
# Sets up Open WebUI in a clean virtual environment on MX Linux (Debian-based).
# Tries Python 3.12 first (usually already in the repos), falls back to
# installing Python 3.11 via pyenv if 3.12 isn't available.
#
# Usage:
#   chmod +x setup-openwebui.sh
#   ./setup-openwebui.sh

set -e  # stop immediately if any command fails

ENV_DIR="$HOME/openwebui-env"

echo "=== Open WebUI Setup Script ==="
echo

# --- Step 1: Remove any old/broken environment ---
if [ -d "$ENV_DIR" ]; then
    echo "Found an existing environment at $ENV_DIR — removing it to start clean..."
    rm -rf "$ENV_DIR"
fi

# --- Step 2: Try Python 3.12 first ---
echo "Checking for Python 3.12..."
sudo apt update -qq

if sudo apt install -y python3.12 python3.12-venv 2>/dev/null; then
    PYTHON_BIN="python3.12"
    echo "Python 3.12 installed successfully."
else
    echo "Python 3.12 not available in the repos."p
    echo "Falling back to installing Python 3.11 via pyenv..."
    echo

    # --- Step 3: Install pyenv build dependencies ---
    sudo apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils \
        tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

    # --- Step 4: Install pyenv if not already present ---
    if [ ! -d "$HOME/.pyenv" ]; then
        curl https://pyenv.run | bash
    fi

    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"

    # Add pyenv to .bashrc permanently if not already there
    if ! grep -q 'PYENV_ROOT' "$HOME/.bashrc"; then
        {
            echo 'export PYENV_ROOT="$HOME/.pyenv"'
            echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
            echo 'eval "$(pyenv init -)"'
        } >> "$HOME/.bashrc"
    fi

    # --- Step 5: Install Python 3.11 via pyenv (only if not already installed) ---
    if ! pyenv versions --bare | grep -q "^3.11"; then
        echo "Compiling Python 3.11.9 — this can take 5-10 minutes..."
        pyenv install 3.11.9
    fi

    PYTHON_BIN="$HOME/.pyenv/versions/3.11.9/bin/python3"
fi

# --- Step 6: Create the virtual environment ---
echo
echo "Creating virtual environment at $ENV_DIR using $PYTHON_BIN..."
"$PYTHON_BIN" -m venv "$ENV_DIR"

# --- Step 7: Activate it and install Open WebUI ---
source "$ENV_DIR/bin/activate"

echo "Using Python version:"
python3 --version

echo
echo "Installing Open WebUI (this may take a few minutes)..."
pip install --upgrade pip
pip install open-webui

echo
echo "=== Setup complete! ==="
echo "To start Open WebUI in the future, run:"
echo "  source $ENV_DIR/bin/activate"
echo "  open-webui serve"
echo
echo "Then open http://localhost:8080 in your browser."
