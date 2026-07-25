#!/usr/bin/env python3
"""Capture and control a Proxmox QEMU VNC console with short-lived API tickets."""

from __future__ import annotations

import argparse
import ssl
import struct
import sys
import time
import urllib.parse
from pathlib import Path

try:
    import websocket
    from Crypto.Cipher import DES
    from PIL import Image
except ImportError as exc:
    raise SystemExit(
        "Missing console dependencies: install websocket-client, pycryptodome, and pillow"
    ) from exc

from proxmox_iso_storage import load_config, proxmox_request


KEYSYMS = {
    "Backspace": 0xFF08,
    "Tab": 0xFF09,
    "Enter": 0xFF0D,
    "Escape": 0xFF1B,
    "Home": 0xFF50,
    "Left": 0xFF51,
    "Up": 0xFF52,
    "Right": 0xFF53,
    "Down": 0xFF54,
    "PageUp": 0xFF55,
    "PageDown": 0xFF56,
    "End": 0xFF57,
    "Insert": 0xFF63,
    "Delete": 0xFFFF,
    "Space": 0x20,
    "Shift": 0xFFE1,
    "Control": 0xFFE3,
    "Alt": 0xFFE9,
    "Meta": 0xFFEB,
}
for number in range(1, 13):
    KEYSYMS[f"F{number}"] = 0xFFBD + number

SHIFTED_CHARACTERS = {
    "!": "1",
    "@": "2",
    "#": "3",
    "$": "4",
    "%": "5",
    "^": "6",
    "&": "7",
    "*": "8",
    "(": "9",
    ")": "0",
    "_": "-",
    "+": "=",
    "{": "[",
    "}": "]",
    "|": "\\",
    ":": ";",
    "\"": "'",
    "<": ",",
    ">": ".",
    "?": "/",
    "~": "`",
}


def reverse_bits(value: int) -> int:
    return int(f"{value:08b}"[::-1], 2)


def vnc_response(challenge: bytes, password: str) -> bytes:
    raw_key = password.encode("utf-8")[:8].ljust(8, b"\x00")
    key = bytes(reverse_bits(value) for value in raw_key)
    return DES.new(key, DES.MODE_ECB).encrypt(challenge)


class RfbClient:
    def __init__(
        self,
        api_url: str,
        token_id: str,
        token_secret: str,
        node: str,
        vmid: int,
    ) -> None:
        self.api_url = api_url
        self.token_id = token_id
        self.token_secret = token_secret
        self.node = node
        self.vmid = vmid
        self.ws = None
        self.buffer = bytearray()
        self.width = 0
        self.height = 0
        self.framebuffer = None

    def connect(self) -> None:
        data = proxmox_request(
            self.api_url,
            self.token_id,
            self.token_secret,
            "POST",
            f"/nodes/{urllib.parse.quote(self.node)}/qemu/{self.vmid}/vncproxy",
        )["data"]
        ticket = data["ticket"]
        query = urllib.parse.urlencode({"port": data["port"], "vncticket": ticket})
        parsed = urllib.parse.urlparse(self.api_url)
        scheme = "wss" if parsed.scheme == "https" else "ws"
        ws_url = (
            f"{scheme}://{parsed.netloc}{parsed.path}/nodes/"
            f"{urllib.parse.quote(self.node)}/qemu/{self.vmid}/vncwebsocket?{query}"
        )
        self.ws = websocket.create_connection(
            ws_url,
            timeout=30,
            sslopt={"cert_reqs": ssl.CERT_NONE, "check_hostname": False},
            header=[
                f"Authorization: PVEAPIToken={self.token_id}={self.token_secret}"
            ],
            subprotocols=["binary"],
            suppress_origin=True,
        )
        self._handshake(ticket)

    def close(self) -> None:
        if self.ws is not None:
            self.ws.close()
            self.ws = None

    def _recv_exact(self, length: int) -> bytes:
        while len(self.buffer) < length:
            payload = self.ws.recv()
            if isinstance(payload, str):
                payload = payload.encode("latin-1")
            if not payload:
                raise RuntimeError("VNC console closed unexpectedly")
            self.buffer.extend(payload)
        result = bytes(self.buffer[:length])
        del self.buffer[:length]
        return result

    def _send(self, payload: bytes) -> None:
        self.ws.send_binary(payload)

    def _handshake(self, ticket: str) -> None:
        version = self._recv_exact(12)
        if not version.startswith(b"RFB "):
            raise RuntimeError(f"Unexpected VNC greeting: {version!r}")
        self._send(b"RFB 003.008\n")

        security_count = self._recv_exact(1)[0]
        if security_count == 0:
            reason_length = struct.unpack("!I", self._recv_exact(4))[0]
            reason = self._recv_exact(reason_length).decode("utf-8", errors="replace")
            raise RuntimeError(f"VNC rejected connection: {reason}")
        security_types = self._recv_exact(security_count)
        if 2 not in security_types:
            raise RuntimeError(f"VNC authentication type unavailable: {list(security_types)}")
        self._send(b"\x02")
        challenge = self._recv_exact(16)
        self._send(vnc_response(challenge, ticket))

        result = struct.unpack("!I", self._recv_exact(4))[0]
        if result != 0:
            reason_length = struct.unpack("!I", self._recv_exact(4))[0]
            reason = self._recv_exact(reason_length).decode("utf-8", errors="replace")
            raise RuntimeError(f"VNC authentication failed: {reason}")

        self._send(b"\x01")
        self.width, self.height = struct.unpack("!HH", self._recv_exact(4))
        self._recv_exact(16)
        name_length = struct.unpack("!I", self._recv_exact(4))[0]
        self._recv_exact(name_length)

        pixel_format = struct.pack(
            "!BBBBHHHBBBxxx",
            32,
            24,
            0,
            1,
            255,
            255,
            255,
            16,
            8,
            0,
        )
        self._send(b"\x00\x00\x00\x00" + pixel_format)
        self._send(struct.pack("!BBHi", 2, 0, 1, 0))
        self.framebuffer = Image.new("RGB", (self.width, self.height), "black")

    def keysym(self, key: str) -> int:
        keysym = KEYSYMS.get(key)
        if keysym is None:
            if len(key) != 1 or ord(key) > 0x7F:
                raise ValueError(f"Unsupported key: {key}")
            keysym = ord(key)
        return keysym

    def send_keysym(self, keysym: int, pressed: bool) -> None:
        self._send(struct.pack("!BBHI", 4, int(pressed), 0, keysym))
        time.sleep(0.02)

    def send_key(self, key: str) -> None:
        keysym = self.keysym(key)
        for pressed in (1, 0):
            self.send_keysym(keysym, bool(pressed))

    def send_chord(self, keys: list[str]) -> None:
        keysyms = [self.keysym(key) for key in keys]
        for keysym in keysyms:
            self.send_keysym(keysym, True)
        for keysym in reversed(keysyms):
            self.send_keysym(keysym, False)

    def type_text(self, value: str) -> None:
        for character in value:
            base_key = SHIFTED_CHARACTERS.get(character)
            if base_key is None:
                self.send_key(character)
            else:
                self.send_chord(["Shift", base_key])

    def capture(self, timeout: float = 20) -> Image.Image:
        self._send(
            struct.pack(
                "!BBHHHH",
                3,
                0,
                0,
                0,
                self.width,
                self.height,
            )
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message_type = self._recv_exact(1)[0]
            if message_type == 0:
                self._recv_exact(1)
                rectangle_count = struct.unpack("!H", self._recv_exact(2))[0]
                if self._read_rectangles(rectangle_count):
                    return self.framebuffer.copy()
            elif message_type == 1:
                self._recv_exact(1)
                _, colors = struct.unpack("!HH", self._recv_exact(4))
                self._recv_exact(colors * 6)
            elif message_type == 2:
                continue
            elif message_type == 3:
                self._recv_exact(3)
                length = struct.unpack("!I", self._recv_exact(4))[0]
                self._recv_exact(length)
            else:
                raise RuntimeError(f"Unsupported VNC server message: {message_type}")
        raise TimeoutError("Timed out waiting for a VNC framebuffer update")

    def _read_rectangles(self, rectangle_count: int) -> bool:
        updated = False
        for _ in range(rectangle_count):
            x, y, width, height, encoding = struct.unpack(
                "!HHHHi", self._recv_exact(12)
            )
            if encoding != 0:
                raise RuntimeError(f"Unsupported VNC encoding: {encoding}")
            raw = self._recv_exact(width * height * 4)
            rectangle = Image.frombytes(
                "RGB",
                (width, height),
                raw,
                "raw",
                "BGRX",
            )
            self.framebuffer.paste(rectangle, (x, y))
            updated = True
        return updated


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfvars", type=Path, default=Path("terraform/terraform.tfvars"))
    parser.add_argument("--node", default="pve01")
    parser.add_argument("--vmid", type=int, required=True)
    parser.add_argument("--pause", type=float, default=1.0)
    parser.add_argument("--output", type=Path)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("screenshot")

    key_parser = subparsers.add_parser("key")
    key_parser.add_argument("keys", nargs="+")

    chord_parser = subparsers.add_parser("chord")
    chord_parser.add_argument("keys", nargs="+")

    type_parser = subparsers.add_parser("type")
    type_parser.add_argument("text")

    type_file_parser = subparsers.add_parser("type-file")
    type_file_parser.add_argument("path", type=Path)

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    api_url, token_id, token_secret = load_config(args.tfvars)
    client = RfbClient(api_url, token_id, token_secret, args.node, args.vmid)
    try:
        client.connect()
        if args.command == "key":
            for key in args.keys:
                client.send_key(key)
        elif args.command == "chord":
            client.send_chord(args.keys)
        elif args.command == "type":
            client.type_text(args.text)
        elif args.command == "type-file":
            client.type_text(args.path.read_text(encoding="utf-8").strip())

        if args.command != "screenshot":
            time.sleep(args.pause)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            client.capture().save(args.output)
            print(args.output)
        elif args.command == "screenshot":
            raise SystemExit("--output is required for screenshot")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
