#!/usr/bin/env python3
"""Loopback contract test for the Godot ComfyUI-to-splat bridge."""

from __future__ import annotations

import argparse
import json
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


PROMPT_ID = "fovea-mock-prompt"
ARTIFACT = bytes(32)


class _State:
    def __init__(self) -> None:
        self.requests: list[str] = []
        self.upload_has_png = False
        self.prompt_has_uploaded_image = False


class _Handler(BaseHTTPRequestHandler):
    state: _State

    def log_message(self, format: str, *args: object) -> None:
        del format, args

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler contract
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        if self.path == "/upload/image":
            self.state.requests.append("upload")
            self.state.upload_has_png = b"Content-Type: image/png" in body and b"PNG" in body
            self._json_response({"name": "uploaded.png", "subfolder": "", "type": "input"})
            return
        if self.path == "/prompt":
            self.state.requests.append("prompt")
            try:
                payload = json.loads(body.decode("utf-8"))
                inputs = payload["prompt"]["11"]["inputs"]
                self.state.prompt_has_uploaded_image = (
                    inputs.get("image") == "uploaded.png" and inputs.get("upload") == "image"
                )
            except (KeyError, TypeError, ValueError, UnicodeDecodeError):
                self.state.prompt_has_uploaded_image = False
            self._json_response({"prompt_id": PROMPT_ID})
            return
        self.send_error(404)

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler contract
        parsed = urlparse(self.path)
        if parsed.path == f"/history/{PROMPT_ID}":
            self.state.requests.append("history")
            self._json_response(
                {
                    PROMPT_ID: {
                        "outputs": {
                            "20": {
                                "files": [
                                    {
                                        "filename": "generated.splat",
                                        "subfolder": "fovea",
                                        "type": "output",
                                    }
                                ]
                            }
                        }
                    }
                }
            )
            return
        if parsed.path == "/view":
            query = parse_qs(parsed.query)
            valid_query = (
                query.get("filename") == ["generated.splat"]
                and query.get("subfolder") == ["fovea"]
                and query.get("type") == ["output"]
            )
            if not valid_query:
                self.send_error(400)
                return
            self.state.requests.append("view")
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(ARTIFACT)))
            self.end_headers()
            self.wfile.write(ARTIFACT)
            return
        self.send_error(404)

    def _json_response(self, payload: object) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True, help="Path to the Godot console executable")
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    project_root = Path(__file__).resolve().parents[1]
    godot = Path(args.godot).expanduser().resolve()
    if not godot.is_file():
        raise SystemExit(f"Godot executable not found: {godot}")

    state = _State()
    _Handler.state = state
    server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    server_url = f"http://127.0.0.1:{server.server_address[1]}"
    try:
        completed = subprocess.run(
            [
                str(godot),
                "--headless",
                "--path",
                str(project_root),
                "-s",
                "res://addons/foveacore/test/comfyui_splat_http_client.gd",
                "--",
                f"--url={server_url}",
            ],
            cwd=project_root,
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    finally:
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=5)

    output = completed.stdout + completed.stderr
    print(output, end="")
    expected_sequence = ["upload", "prompt", "history", "view"]
    failures: list[str] = []
    if completed.returncode != 0:
        failures.append(f"Godot exited with {completed.returncode}")
    if "ComfyUI HTTP bridge: 5 passed, 0 failed" not in output:
        failures.append("Godot success marker is missing")
    if any(marker in output for marker in ("SCRIPT ERROR", "Parse Error", "Failed to load script")):
        failures.append("Godot emitted a script compilation/load error")
    if state.requests != expected_sequence:
        failures.append(f"unexpected HTTP sequence: {state.requests!r}")
    if not state.upload_has_png:
        failures.append("upload request did not contain an encoded PNG")
    if not state.prompt_has_uploaded_image:
        failures.append("prompt payload did not contain the uploaded image")
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    print("PASS: ComfyUI loopback contract upload -> prompt -> history -> view")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
