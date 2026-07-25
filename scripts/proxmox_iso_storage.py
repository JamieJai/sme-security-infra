#!/usr/bin/env python3
"""List and upload Proxmox ISO images using local Terraform credentials."""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path


DEFAULT_TFVARS = Path("terraform/terraform.tfvars")


def read_tfvars_value(path: Path, key: str) -> str | None:
    if not path.exists():
        return None
    pattern = re.compile(rf"^\s*{re.escape(key)}\s*=\s*\"([^\"]*)\"\s*(?:#.*)?$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    return None


def load_config(tfvars: Path) -> tuple[str, str, str]:
    api_url = os.environ.get("PROXMOX_URL") or read_tfvars_value(tfvars, "pm_api_url")
    token_id = os.environ.get("PROXMOX_TOKEN_ID") or read_tfvars_value(
        tfvars, "proxmox_api_token_id"
    )
    token_secret = os.environ.get("PROXMOX_TOKEN_SECRET") or read_tfvars_value(
        tfvars, "proxmox_api_token_secret"
    )

    missing = [
        name
        for name, value in (
            ("pm_api_url/PROXMOX_URL", api_url),
            ("proxmox_api_token_id/PROXMOX_TOKEN_ID", token_id),
            ("proxmox_api_token_secret/PROXMOX_TOKEN_SECRET", token_secret),
        )
        if not value
    ]
    if missing:
        raise SystemExit(f"Missing Proxmox config: {', '.join(missing)}")

    return api_url.rstrip("/"), token_id, token_secret


def proxmox_request(
    api_url: str,
    token_id: str,
    token_secret: str,
    method: str,
    path: str,
    *,
    body: bytes | None = None,
    headers: dict[str, str] | None = None,
) -> dict:
    request_headers = {
        "Authorization": f"PVEAPIToken={token_id}={token_secret}",
    }
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(
        f"{api_url}{path}",
        data=body,
        headers=request_headers,
        method=method,
    )
    context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(request, context=context, timeout=120) as response:
            payload = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise SystemExit(f"Proxmox API HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Proxmox API connection failed: {exc}") from exc
    return json.loads(payload.decode("utf-8"))


def wait_task(api_url: str, token_id: str, token_secret: str, node: str, upid: str) -> None:
    encoded = urllib.parse.quote(upid, safe="")
    for _ in range(180):
        data = proxmox_request(
            api_url,
            token_id,
            token_secret,
            "GET",
            f"/nodes/{urllib.parse.quote(node)}/tasks/{encoded}/status",
        )["data"]
        if data.get("status") == "stopped":
            if data.get("exitstatus") != "OK":
                raise SystemExit(f"Proxmox upload task failed: {data.get('exitstatus')}")
            return
        time.sleep(2)
    raise SystemExit("Timed out waiting for Proxmox upload task")


def list_isos(api_url: str, token_id: str, token_secret: str, node: str, storage: str) -> list[dict]:
    path = (
        f"/nodes/{urllib.parse.quote(node)}/storage/{urllib.parse.quote(storage)}/content"
        "?content=iso"
    )
    return proxmox_request(api_url, token_id, token_secret, "GET", path)["data"]


def proxmox_upload_request(
    api_url: str,
    token_id: str,
    token_secret: str,
    path: str,
    iso_path: Path,
    preamble: bytes,
    closing: bytes,
    headers: dict[str, str],
) -> dict:
    parsed = urllib.parse.urlparse(api_url)
    if parsed.scheme != "https":
        raise SystemExit("Only https Proxmox API URLs are supported for uploads")
    connection = http.client.HTTPSConnection(
        parsed.hostname,
        parsed.port or 443,
        context=ssl._create_unverified_context(),
        timeout=120,
    )
    try:
        request_path = f"{parsed.path}{path}" if parsed.path else path
        connection.putrequest("POST", request_path)
        request_headers = {
            "Authorization": f"PVEAPIToken={token_id}={token_secret}",
            **headers,
        }
        for key, value in request_headers.items():
            connection.putheader(key, value)
        connection.endheaders()
        connection.send(preamble)
        with iso_path.open("rb") as iso_file:
            while True:
                chunk = iso_file.read(1024 * 1024)
                if not chunk:
                    break
                connection.send(chunk)
        connection.send(closing)
        response = connection.getresponse()
        payload = response.read().decode("utf-8", errors="replace")
        if response.status >= 400:
            raise SystemExit(f"Proxmox API HTTP {response.status}: {payload}")
        return json.loads(payload)
    finally:
        connection.close()


def upload_iso(
    api_url: str,
    token_id: str,
    token_secret: str,
    node: str,
    storage: str,
    iso_path: Path,
) -> None:
    if not iso_path.is_file():
        raise SystemExit(f"ISO not found: {iso_path}")

    boundary = f"----codex-proxmox-{uuid.uuid4().hex}"
    file_name = iso_path.name
    preamble = b"".join(
        (
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="content"\r\n\r\n',
            b"iso\r\n",
            f"--{boundary}\r\n".encode(),
            (
                'Content-Disposition: form-data; name="filename"; '
                f'filename="{file_name}"\r\n'
            ).encode(),
            b"Content-Type: application/octet-stream\r\n\r\n",
        )
    )
    closing = b"\r\n" + f"--{boundary}--\r\n".encode()
    content_length = len(preamble) + iso_path.stat().st_size + len(closing)
    response = proxmox_upload_request(
        api_url,
        token_id,
        token_secret,
        f"/nodes/{urllib.parse.quote(node)}/storage/{urllib.parse.quote(storage)}/upload",
        iso_path,
        preamble,
        closing,
        {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(content_length),
        },
    )
    upid = response.get("data")
    if not upid:
        raise SystemExit(f"Upload did not return a task id: {response}")
    wait_task(api_url, token_id, token_secret, node, upid)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfvars", type=Path, default=DEFAULT_TFVARS)
    parser.add_argument("--node", default="pve01")
    parser.add_argument("--storage", default="local")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list", help="List ISO images in Proxmox storage")

    upload_parser = subparsers.add_parser("upload", help="Upload an ISO image")
    upload_parser.add_argument("iso", type=Path)

    args = parser.parse_args()
    api_url, token_id, token_secret = load_config(args.tfvars)

    if args.command == "list":
        for item in list_isos(api_url, token_id, token_secret, args.node, args.storage):
            print(item.get("volid", item.get("name", "<unknown>")))
        return 0

    if args.command == "upload":
        upload_iso(api_url, token_id, token_secret, args.node, args.storage, args.iso)
        target = f"{args.storage}:iso/{args.iso.name}"
        uploaded = list_isos(api_url, token_id, token_secret, args.node, args.storage)
        if not any(item.get("volid") == target for item in uploaded):
            raise SystemExit(f"Uploaded ISO was not found in storage listing: {target}")
        print(f"uploaded {target}")
        return 0

    raise SystemExit(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    sys.exit(main())
