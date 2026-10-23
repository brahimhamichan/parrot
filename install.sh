#!/bin/sh
# One-command install: Python env with Kokoro, the app in ~/Applications, Login Item, and Tinycast commands if present.
set -e
cd "$(dirname "$0")"
VENV="$HOME/Library/Application Support/Parrot/venv"

[ "$(uname -s)" = Darwin ] || { echo "Parrot needs macOS."; exit 1; }
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Xcode Command Line Tools (needed to compile the app). Re-run ./install.sh when it finishes."
  xcode-select --install; exit 1
fi
# Guard against a partial clone missing the model files.
if [ "$(wc -c < models/kokoro-v1.0.int8.onnx)" -lt 1000000 ]; then
  echo "models/ looks incomplete; re-clone the repo (model files are missing)."; exit 1
fi

# uv provides a known-good Python without touching the system one.
if ! command -v uv >/dev/null 2>&1; then
  [ -x "$HOME/.local/bin/uv" ] || curl -LsSf https://astral.sh/uv/install.sh | sh
  PATH="$HOME/.local/bin:$PATH"
fi
echo "Setting up Python environment…"
uv venv --quiet --allow-existing --python 3.12 "$VENV"
uv pip install --quiet --python "$VENV/bin/python" -r requirements.txt

echo "Building Parrot.app…"
./build.sh
[ -d /Applications/Tinycast.app ] && python3 tinycast-commands.py && echo "Added Parrot commands to Tinycast."

open "$HOME/Applications/Parrot.app"
cat <<MSG

Parrot is installed and running (menu-bar waveform icon).
One manual step: allow it in System Settings → Privacy & Security → Accessibility.
Then select text anywhere and press ⌥Esc.
MSG
