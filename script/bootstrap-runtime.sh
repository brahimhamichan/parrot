#!/bin/sh
# Called by the app, with an isolated Python install and virtual environment.
set -eu
UV=$1
SUPPORT=$2
VENV=$3
LOCK=$4

export UV_NO_CONFIG=1 UV_NO_PROGRESS=1 UV_HTTP_TIMEOUT=30
export UV_PYTHON_INSTALL_DIR="$SUPPORT/python"
export UV_DEFAULT_INDEX=https://pypi.org/simple
"$UV" venv --managed-python --relocatable --python 3.12.16 "$VENV"
"$UV" pip install --no-cache --only-binary :all: --require-hashes --python "$VENV/bin/python" -r "$LOCK"
"$VENV/bin/python" -I -c 'import kokoro_onnx, sounddevice'
