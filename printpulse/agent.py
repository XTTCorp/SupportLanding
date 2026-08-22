#!/usr/bin/env python3
"""
PrintPulse Relay Agent
Zero-Configuration, CGNAT-Bypassing Remote 3D Printer & Camera Gateway Daemon.
Auto-manages built-in encrypted TLS tunnels (Cloudflare Quick Tunnels / P2P) with zero firewall rules or port forwarding.
"""

import asyncio
import json
import os
import platform
import re
import secrets
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
from typing import Dict, List, Optional
import aiohttp
from aiohttp import web

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(BASE_DIR, "data", "agent_config.json")
BIN_DIR = os.path.join(BASE_DIR, "bin")
CLOUDFLARED_BIN = os.path.join(BIN_DIR, "cloudflared")
PORT = int(os.environ.get("PRINTPULSE_PORT", "8088"))

class TunnelManager:
    """Manages zero-config outbound encrypted tunnel for CGNAT / NAT bypass"""
    def __init__(self):
        self.public_url: Optional[str] = None
        self.process: Optional[subprocess.Popen] = None
        self.status: str = "starting"
        self.error: Optional[str] = None

    def ensure_binary(self) -> bool:
        if os.path.exists(CLOUDFLARED_BIN) and os.access(CLOUDFLARED_BIN, os.X_OK):
            return True
        system_bin = shutil.which("cloudflared")
        if system_bin:
            return True

        os.makedirs(BIN_DIR, exist_ok=True)
        arch = platform.machine().lower()
        if arch in ("x86_64", "amd64"):
            url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        elif arch in ("aarch64", "arm64"):
            url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        elif "arm" in arch:
            url = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm"
        else:
            self.error = f"Unsupported architecture: {arch}"
            return False

        try:
            print(f"📦 Downloading zero-config tunnel daemon for {arch}...")
            urllib.request.urlretrieve(url, CLOUDFLARED_BIN)
            os.chmod(CLOUDFLARED_BIN, 0o755)
            print("✅ Tunnel daemon installed successfully.")
            return True
        except Exception as e:
            self.error = f"Failed to download tunnel binary: {e}"
            print(f"❌ {self.error}")
            return False

    def start(self):
        def _run():
            if not self.ensure_binary():
                self.status = "failed"
                return

            bin_path = CLOUDFLARED_BIN if os.path.exists(CLOUDFLARED_BIN) else "cloudflared"
            cmd = [
                bin_path, "tunnel",
                "--url", f"http://127.0.0.1:{PORT}",
                "--no-autoupdate",
                "--metrics", "127.0.0.1:0"
            ]

            print("🌐 Starting secure outbound encrypted tunnel (NAT/CGNAT bypass)...")
            self.status = "connecting"
            try:
                self.process = subprocess.Popen(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )

                url_pattern = re.compile(r"https://[a-zA-Z0-9-]+\.trycloudflare\.com")
                for line in self.process.stdout:
                    match = url_pattern.search(line)
                    if match:
                        self.public_url = match.group(0)
                        self.status = "connected"
                        print("=" * 60)
                        print(f"🚀 GLOBAL REMOTE TUNNEL ACTIVE: {self.public_url}")
                        print("=" * 60)
                        break

                self.process.wait()
            except Exception as e:
                self.error = str(e)
                self.status = "error"
                print(f"❌ Tunnel error: {e}")

        t = threading.Thread(target=_run, daemon=True)
        t.start()

    def stop(self):
        if self.process:
            try:
                self.process.terminate()
            except Exception:
                pass

tunnel = TunnelManager()

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

def get_local_lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        lan_ip = s.getsockname()[0]
        s.close()
        return lan_ip
    except Exception:
        return "127.0.0.1"

# --- API Endpoints ---

async def handle_index(request):
    html_path = os.path.join(BASE_DIR, "web", "index.html")
    if os.path.exists(html_path):
        return web.FileResponse(html_path)
    return web.Response(text="PrintPulse Agent is running.", content_type="text/plain")

async def handle_agent_info(request):
    local_ip = get_local_lan_ip()
    return web.json_response({
        "agentId": state.agent_id,
        "agentName": state.agent_name,
        "pairingCode": state.pairing_code,
        "localIp": local_ip,
        "port": PORT,
        "remoteTunnelUrl": tunnel.public_url,
        "tunnelStatus": tunnel.status,
        "tunnelError": tunnel.error,
        "printerCount": len(state.printers),
        "version": "2.0.0"
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
                "remoteTunnelUrl": tunnel.public_url,
                "printers": state.printers
            })
        return web.json_response({"success": False, "error": "Invalid pairing code"}, status=401)
    except Exception as e:
        return web.json_response({"success": False, "error": str(e)}, status=400)

def verify_token(request) -> bool:
    token = request.query.get("token") or request.headers.get("X-PrintPulse-Token") or request.headers.get("Authorization", "").replace("Bearer ", "")
    return token == state.auth_token

async def handle_get_printers(request):
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
                "Access-Control-Allow-Origin": "*",
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
    app.router.add_get("/", handle_index)
    app.router.add_get("/api/agent/info", handle_agent_info)
    app.router.add_post("/api/agent/pair", handle_pair)
    app.router.add_post("/api/agent/regenerate", handle_regenerate_code)
    app.router.add_get("/api/printers", handle_get_printers)
    app.router.add_post("/api/printers", handle_add_printer)
    app.router.add_delete("/api/printers/{id}", handle_delete_printer)
    app.router.add_get("/api/printers/{id}/video", handle_video_proxy)
    app.router.add_get("/api/printers/{id}/ws", handle_websocket_proxy)

    web_dir = os.path.join(BASE_DIR, "web")
    if os.path.exists(web_dir):
        app.router.add_static("/static/", path=web_dir, name="static")

    return app

if __name__ == "__main__":
    # Start auto-managed encrypted zero-config tunnel
    tunnel.start()

    app = create_app()
    lan_ip = get_local_lan_ip()
    print("=" * 60)
    print("🚀 PrintPulse Relay Agent Running!")
    print(f"🏠 Local LAN:        http://{lan_ip}:{PORT}")
    print(f"🔑 Pairing Code:     {state.pairing_code}")
    print("=" * 60)
    web.run_app(app, host="0.0.0.0", port=PORT)
