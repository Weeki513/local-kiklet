#!/usr/bin/env bash
set -euo pipefail

MODELS_DIR="${HOME}/Library/Application Support/LocalKiklet/models"
mkdir -p "$MODELS_DIR"

BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

FAST_MODEL="ggml-base.bin"
ACCURATE_MODEL="ggml-medium.bin"

if [[ ! -f "$MODELS_DIR/$FAST_MODEL" ]]; then
  echo "Downloading $FAST_MODEL"
  curl -L "$BASE_URL/$FAST_MODEL" -o "$MODELS_DIR/$FAST_MODEL"
fi

if [[ ! -f "$MODELS_DIR/$ACCURATE_MODEL" ]]; then
  echo "Downloading $ACCURATE_MODEL"
  curl -L "$BASE_URL/$ACCURATE_MODEL" -o "$MODELS_DIR/$ACCURATE_MODEL"
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "whisper-cli not found. Install it with: brew install whisper-cpp"
else
  echo "whisper-cli found: $(command -v whisper-cli)"
fi

echo "Models ready in: $MODELS_DIR"
