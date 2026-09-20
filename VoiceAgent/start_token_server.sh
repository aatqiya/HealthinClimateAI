#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created VoiceAgent/.env. Paste these four values, save the file, then run this script again:"
  echo "  LIVEKIT_URL          (wss://....livekit.cloud from LiveKit Cloud)"
  echo "  LIVEKIT_API_KEY"
  echo "  LIVEKIT_API_SECRET"
  echo "  GROQ_API_KEY         (free: https://console.groq.com/keys)"
  exit 1
fi

if ! command -v python3 >/dev/null; then
  echo "Install Python 3.10+ from python.org, then retry."
  exit 1
fi

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate
python -m pip install -q --upgrade pip
python -m pip install -q -r requirements.txt

python - <<'PY'
from dotenv import load_dotenv
import os
load_dotenv(".env")
needed = ["LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET"]
missing = [name for name in needed if not os.getenv(name) or "your-project" in (os.getenv(name) or "")]
if not os.getenv("GROQ_API_KEY") and not os.getenv("OPENAI_API_KEY"):
    missing.append("GROQ_API_KEY")
if missing:
    raise SystemExit("Still empty in VoiceAgent/.env: " + ", ".join(missing))
print("Voice environment looks complete.")
PY

python agent.py download-files || true
echo
echo "Token server: http://127.0.0.1:8787/token"
echo "In another terminal:  ./start_agent.sh"
echo
exec python token_server.py
