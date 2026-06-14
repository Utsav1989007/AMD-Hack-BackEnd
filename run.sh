#!/usr/bin/env bash
set -euo pipefail

# ATLAS backend launcher
# 1. Ensure Ollama is running and models are pulled:
#       ollama serve &
#       ollama pull llama3.1
#       ollama pull nomic-embed-text
# 2. Then:  ./run.sh

if [ ! -f .env ]; then
  echo "No .env found — copying .env.example -> .env"
  cp .env.example .env
fi

python -m venv .venv 2>/dev/null || true
# shellcheck disable=SC1091
source .venv/bin/activate 2>/dev/null || true

pip install -q -r requirements.txt

exec uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
