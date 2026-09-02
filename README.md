# Homelab AI Stack — Eric Harvey's Workstation

This repository provisions a private, local AI setup on **Eric Harvey's
Workstation**. Everything runs on the machine itself; no prompts or data are
sent to an outside service.

## What it installs

| Component | Purpose | Port |
|-----------|---------|------|
| [Ollama](https://ollama.com) | Runs language models locally and serves them over an HTTP API | 11434 |
| `qwen3:8b` | A capable general-purpose model, downloaded so there is something to talk to right away | — |
| Python 3.12 (or 3.11 via pyenv) | Isolated interpreter for Open WebUI | — |
| [Open WebUI](https://github.com/open-webui/open-webui) | Browser chat interface that talks to Ollama | 8080 |

## Running it

> **Run this only on Eric Harvey's Workstation — not on a shared VM.**
> The script opens with a confirmation prompt for exactly this reason.

```bash
chmod +x setup.sh
./setup.sh
```

The script narrates each step with colour-coded logging and "Homelab note"
asides, so the run doubles as a walkthrough of how the pieces fit together.
It is safe to re-run: existing installs and downloads are detected and skipped.

## Starting Open WebUI later

```bash
source ~/openwebui-env/bin/activate
open-webui serve
```

Then open <http://localhost:8080>. On first launch, create a local account
(stored only on this machine), pick `qwen3:8b` from the model menu, and start
chatting.

## How the pieces connect

```
Browser  ──►  Open WebUI (:8080)  ──►  Ollama (:11434)  ──►  qwen3:8b
```

Open WebUI never runs a model itself — it forwards messages to Ollama and
displays the replies.

## Hardware report

The script's final section prints a report of the detected hardware:

- **GPU (NVIDIA)** — Name, VRAM Total, Compute Cap, Driver, CUDA (from
  `nvidia-smi`). If no NVIDIA GPU is present it says so and notes that
  `qwen3:8b` will run on the CPU instead.
- **CPU / Memory** — CPU model, cores / threads, total RAM.

It closes with a rule of thumb for reading those numbers: a 4-bit-quantized
model needs roughly its parameter count in billions × 0.6–0.75 GiB of VRAM to
run entirely on the GPU; with less, Ollama splits it between GPU and system RAM
and runs slower.
