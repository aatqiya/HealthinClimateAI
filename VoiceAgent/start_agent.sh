#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -f .env ]]; then
  echo "Run ./start_token_server.sh first and fill VoiceAgent/.env."
  exit 1
fi
if [[ ! -d .venv ]]; then
  echo "Run ./start_token_server.sh once so the Python environment is created."
  exit 1
fi
# shellcheck disable=SC1091
source .venv/bin/activate
exec python agent.py dev
