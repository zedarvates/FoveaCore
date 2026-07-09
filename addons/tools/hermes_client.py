#!/usr/bin/env python3
"""Fovea Hermes Bridge — Minimal Python client (item 282)
Connects to FoveaEngine's WebSocket server and sends commands.

Usage:
    ./hermes_client.py ping
    ./hermes_client.py get_scene_info
    ./hermes_client.py get_stats
"""

import json
import sys
import asyncio
import websockets

HOST = "localhost"
PORT = 8765

async def send_request(op: str, args: dict = None) -> dict:
    async with websockets.connect(f"ws://{HOST}:{PORT}") as ws:
        req = {"op": op, "args": args or {}, "id": 1}
        await ws.send(json.dumps(req))
        resp = json.loads(await ws.recv())
        return resp

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: hermes_client.py <op> [args_json]")
        sys.exit(1)
    
    op = sys.argv[1]
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    
    result = asyncio.run(send_request(op, args))
    print(json.dumps(result, indent=2))
