#!/usr/bin/env python3
"""
PrintPulse Relay Agent
Lightweight companion daemon for remote 3D printer monitoring and camera streaming.
Supports ZeroTier, Tailscale, LAN, and public reverse relays.
"""

import asyncio
import json
import os
import secrets
import socket
import sys
import uuid
from typing import Dict, List, Optional
import aiohttp
from aiohttp import web

CONFIG_FILE = os.path.join(os.path.dirname(__file__), "data", "agent_config.json")
PORT = int(os.environ.get("PRINTPULSE_PORT", "8088"))

class AgentState:
    def __init__(self):
        self.agent_id: str = ""
        self.agent_name: str = "Home PrintPulse Agent"
        self.pairing_code: str = ""
        self.auth_token: str = ""
        self.printers: List[Dict] = []
        self.load_or_init()

    def load_or_init(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r") as f:
                    data = json.load(f)
                    self.agent_id = data.get("agent_id", str(uuid.uuid4()))
                    self.agent_name = data.get("agent_name", "Home PrintPulse Agent")
                    self.pairing_code = data.get("pairing_code", self._generate_pairing_code())
                    self.auth_token = data.get("auth_token", secrets.token_hex(16))
                    self.printers = data.get("printers", [])
                    return
            except Exception as e:
                print(f"Error loading config: {e}")

        # Initial creation
        self.agent_id = str(uuid.uuid4())
        self.pairing_code = self._generate_pairing_code()
        self.auth_token = secrets.token_hex(16)
        self.printers = [
            {
                "id": str(uuid.uuid4()),
                "name": "Elegoo Centauri Carbon",
                "ipAddress": "192.168.1.100",
                "printerType": "ELEGOO_CENTAURI_CARBON",
                "wsPort": 3030,
                "cameraPort": 3031,
                "cameraPath": "/video"
            }
        ]
        self.save()

    def _generate_pairing_code(self) -> str:
        # Generates a clean 6-digit numeric pairing code (e.g. 749201)
        return f"{secrets.randbelow(900000) + 100000}"

    def save(self):
        os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump({
                "agent_id": self.agent_id,
                "agent_name": self.agent_name,
                "pairing_code": self.pairing_code,
                "auth_token": self.auth_token,
                "printers": self.printers
            }, f, indent=2)

state = AgentState()

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

# --- API Endpoints ---

async def handle_index(request):
    html_path = os.path.join(os.path.dirname(__file__), "web", "index.html")
    if os.path.exists(html_path):
        return web.FileResponse(html_path)
    return web.Response(text="PrintPulse Agent is running.", content_type="text/plain")

async def handle_agent_info(request):
    return web.json_response({
        "agentId": state.agent_id,
        "agentName": state.agent_name,
        "pairingCode": state.pairing_code,
        "localIp": get_local_ip(),
        "port": PORT,
        "printerCount": len(state.printers),
        "version": "1.0.0"
    })

async def handle_pair(request):
    try:
        data = await request.json()
        code = str(data.get("pairingCode", "")).strip().replace("-", "")
        if code == state.pairing_code:
            return web.json_response({
                "success": True,
                "agentId": state.agent_id,
                "agentName": state.agent_name,
                "token": state.auth_token,
                "printers": state.printers
            })
        return web.json_response({"success": False, "error": "Invalid pairing code"}, status=401)
    except Exception as e:
        return web.json_response({"success": False, "error": str(e)}, status=400)

def verify_token(request) -> bool:
    token = request.query.get("token") or request.headers.get("X-PrintPulse-Token") or request.headers.get("Authorization", "").replace("Bearer ", "")
    return token == state.auth_token

async def handle_get_printers(request):
    if not verify_token(request) and request.headers.get("Sec-Fetch-Mode") != "cors":
        pass # Allow local web UI or token auth
    return web.json_response(state.printers)

async def handle_add_printer(request):
    data = await request.json()
    printer_id = data.get("id") or str(uuid.uuid4())
    printer = {
        "id": printer_id,
        "name": data.get("name", "3D Printer"),
        "ipAddress": data.get("ipAddress", "").strip(),
        "printerType": data.get("printerType", "ELEGOO_CENTAURI_CARBON"),
        "wsPort": int(data.get("wsPort", 3030)),
        "cameraPort": int(data.get("cameraPort", 3031)),
        "cameraPath": data.get("cameraPath", "/video")
    }
    # Update or add
    existing = [p for p in state.printers if p["id"] == printer_id]
    if existing:
        state.printers = [printer if p["id"] == printer_id else p for p in state.printers]
    else:
        state.printers.append(printer)
    state.save()
    return web.json_response({"success": True, "printer": printer})

async def handle_delete_printer(request):
    printer_id = request.match_info.get("id")
    state.printers = [p for p in state.printers if p["id"] != printer_id]
    state.save()
    return web.json_response({"success": True})

async def handle_regenerate_code(request):
    state.pairing_code = state._generate_pairing_code()
    state.auth_token = secrets.token_hex(16)
    state.save()
    return web.json_response({
        "pairingCode": state.pairing_code,
        "token": state.auth_token
    })

# --- Stream & WebSocket Proxies ---

async def handle_video_proxy(request):
    printer_id = request.match_info.get("id")
    printer = next((p for p in state.printers if p["id"] == printer_id), None)
    if not printer:
        return web.Response(text="Printer not found", status=404)

    target_url = f"http://{printer['ipAddress']}:{printer['cameraPort']}{printer['cameraPath']}"

    try:
        client_session = aiohttp.ClientSession()
        resp = await client_session.get(target_url, timeout=aiohttp.ClientTimeout(total=None, connect=5))

        response = web.StreamResponse(
            status=resp.status,
            reason=resp.reason,
            headers={
                "Content-Type": resp.headers.get("Content-Type", "multipart/x-mixed-replace; boundary=frame"),
                "Cache-Control": "no-cache, no-store, must-revalidate",
                "Connection": "close"
            }
        )
        await response.prepare(request)

        async for chunk in resp.content.iter_chunked(4096):
            await response.write(chunk)

        await client_session.close()
        return response
    except Exception as e:
        return web.Response(text=f"Camera proxy error: {e}", status=502)

async def handle_websocket_proxy(request):
    printer_id = request.match_info.get("id")
    printer = next((p for p in state.printers if p["id"] == printer_id), None)
    if not printer:
        return web.Response(text="Printer not found", status=404)

    client_ws = web.WebSocketResponse()
    await client_ws.prepare(request)

    target_ws_url = f"ws://{printer['ipAddress']}:{printer['wsPort']}/websocket"

    session = aiohttp.ClientSession()
    try:
        async with session.ws_connect(target_ws_url, timeout=5) as printer_ws:
            async def forward_to_client():
                async for msg in printer_ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await client_ws.send_str(msg.data)
                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        await client_ws.send_bytes(msg.data)
                    elif msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
                        break

            async def forward_to_printer():
                async for msg in client_ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        await printer_ws.send_str(msg.data)
                    elif msg.type == aiohttp.WSMsgType.BINARY:
                        await printer_ws.send_bytes(msg.data)
                    elif msg.type in (aiohttp.WSMsgType.CLOSED, aiohttp.WSMsgType.ERROR):
                        break

            await asyncio.gather(forward_to_client(), forward_to_printer())
    except Exception as e:
        print(f"WS Proxy error: {e}")
    finally:
        await session.close()
        await client_ws.close()

    return client_ws

# --- App Setup ---

def create_app():
    app = web.Application()
    # CORS setup for web requests
    app.router.add_get("/", handle_index)
    app.router.add_get("/api/agent/info", handle_agent_info)
    app.router.add_post("/api/agent/pair", handle_pair)
    app.router.add_post("/api/agent/regenerate", handle_regenerate_code)
    app.router.add_get("/api/printers", handle_get_printers)
    app.router.add_post("/api/printers", handle_add_printer)
    app.router.add_delete("/api/printers/{id}", handle_delete_printer)
    app.router.add_get("/api/printers/{id}/video", handle_video_proxy)
    app.router.add_get("/api/printers/{id}/ws", handle_websocket_proxy)

    # Static assets if present
    web_dir = os.path.join(os.path.dirname(__file__), "web")
    if os.path.exists(web_dir):
        app.router.add_static("/static/", path=web_dir, name="static")

    return app

if __name__ == "__main__":
    app = create_app()
    local_ip = get_local_ip()
    print("=" * 60)
    print("🚀 PrintPulse Relay Agent Starting...")
    print(f"📍 Local Web UI: http://{local_ip}:{PORT} or http://localhost:{PORT}")
    print(f"🔑 Pairing Code: {state.pairing_code}")
    print(f"🛡️ Agent ID:     {state.agent_id}")
    print("=" * 60)
    web.run_app(app, host="0.0.0.0", port=PORT)
