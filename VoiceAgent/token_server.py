#!/usr/bin/env python3
"""Mint short-lived LiveKit room tokens. Do not put these secrets in the iOS app."""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from dotenv import load_dotenv
from livekit import api

load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

REQUIRED = ("LIVEKIT_URL", "LIVEKIT_API_KEY", "LIVEKIT_API_SECRET")
missing = [name for name in REQUIRED if not os.getenv(name) or "your-project" in os.getenv(name, "")]
if missing:
    raise SystemExit("Fill these in VoiceAgent/.env first: " + ", ".join(missing))

LIVEKIT_URL = os.environ["LIVEKIT_URL"]
API_KEY = os.environ["LIVEKIT_API_KEY"]
API_SECRET = os.environ["LIVEKIT_API_SECRET"]
HOST = os.environ.get("VOICE_TOKEN_HOST", "127.0.0.1")
PORT = int(os.environ.get("VOICE_TOKEN_PORT", "8787"))


class TokenHandler(BaseHTTPRequestHandler):
    def _json(self, code: int, body: dict) -> None:
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(payload)

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/health":
            self._json(200, {"ok": True, "url": LIVEKIT_URL})
            return
        self.send_error(404)

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/token":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self._json(400, {"error": "Request body must be JSON."})
            return
        identity = str(body.get("identity") or "resilio-ios")
        room = str(body.get("room") or "resilio-plan")
        token = (
            api.AccessToken(API_KEY, API_SECRET)
            .with_identity(identity)
            .with_name("Resilio")
            .with_grants(api.VideoGrants(room_join=True, room=room, can_publish=True, can_subscribe=True, can_publish_data=True))
            .with_room_config(api.RoomConfiguration(agents=[api.RoomAgentDispatch(agent_name="resilio-planner")]))
            .to_jwt()
        )
        self._json(200, {"url": LIVEKIT_URL, "token": token, "room": room})

    def log_message(self, format: str, *args) -> None:
        print("%s - %s" % (self.address_string(), format % args))


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), TokenHandler)
    print(f"Resilio voice token server on http://{HOST}:{PORT}/token")
    server.serve_forever()
