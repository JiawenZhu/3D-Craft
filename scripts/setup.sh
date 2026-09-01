#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Rodin 3D Studio — local inference setup.
#
#   ./scripts/setup.sh            base server (remote HF Space provider)
#   ./scripts/setup.sh --local    + torch and the native pipelines
#   ./scripts/setup.sh --weights  + download model weights (large)
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT/server/.venv"
PY_BIN="${PYTHON:-}"
WANT_LOCAL=0
WANT_WEIGHTS=0

for arg in "$@"; do
  case "$arg" in
    --local)   WANT_LOCAL=1 ;;
    --weights) WANT_LOCAL=1; WANT_WEIGHTS=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# --- pick an interpreter torch actually ships wheels for -------------------
if [ -z "$PY_BIN" ]; then
  for c in python3.12 python3.11 /opt/homebrew/opt/python@3.12/bin/python3.12 /opt/homebrew/opt/python@3.11/bin/python3.11 python3; do
    if command -v "$c" >/dev/null 2>&1; then
      v="$($c -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
      case "$v" in 3.10|3.11|3.12) PY_BIN="$c"; break ;; esac
    fi
  done
fi
[ -n "$PY_BIN" ] || { echo "need python 3.10-3.12 (torch has no wheels for 3.13+ yet)" >&2; exit 1; }
echo "▸ interpreter: $PY_BIN ($($PY_BIN -V 2>&1))"

# --- venv ------------------------------------------------------------------
if [ ! -d "$VENV" ]; then
  echo "▸ creating venv at server/.venv"
  if command -v uv >/dev/null 2>&1; then uv venv --python "$PY_BIN" "$VENV"; else "$PY_BIN" -m venv "$VENV"; fi
fi

PIP=(pip install --upgrade)
if command -v uv >/dev/null 2>&1; then PIP=(uv pip install --python "$VENV/bin/python"); else PIP=("$VENV/bin/pip" install --upgrade); fi

echo "▸ base requirements"
"${PIP[@]}" -r "$ROOT/server/requirements.txt"

# --- native inference stack -------------------------------------------------
if [ "$WANT_LOCAL" = 1 ]; then
  UNAME="$(uname -s)-$(uname -m)"
  if [ "$UNAME" = "Darwin-arm64" ]; then
    echo "▸ torch (Apple Silicon / MPS)"
    "${PIP[@]}" torch torchvision
  elif command -v nvidia-smi >/dev/null 2>&1; then
    echo "▸ torch (CUDA 12.4)"
    "${PIP[@]}" torch torchvision --index-url https://download.pytorch.org/whl/cu124
  else
    echo "▸ torch (CPU)"
    "${PIP[@]}" torch torchvision --index-url https://download.pytorch.org/whl/cpu
  fi
  echo "▸ local requirements"
  "${PIP[@]}" -r "$ROOT/server/requirements-local.txt"
fi

# --- weights ---------------------------------------------------------------
if [ "$WANT_WEIGHTS" = 1 ]; then
  echo "▸ downloading weights into server/weights (this is many GB)"
  "$VENV/bin/python" "$ROOT/scripts/fetch_weights.py"
fi

echo
echo "✓ done. Start the server with:  npm run server"
"$VENV/bin/python" "$ROOT/scripts/doctor.py" || true
