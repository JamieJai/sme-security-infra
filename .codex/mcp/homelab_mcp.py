#!/usr/bin/env python3
"""Read-oriented MCP tools for the homelab-infra project."""

from __future__ import annotations

import base64
import datetime as dt
import json
import os
import shutil
import sqlite3
import ssl
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from fastmcp import FastMCP


ROOT = Path("/home/sysadmin/homelab-infra")
ANSIBLE_DIR = ROOT / "ansible"
TERRAFORM_DIR = ROOT / "terraform"
OPS_DB = ROOT / ".codex" / "mcp" / "homelab_ops.sqlite"

mcp = FastMCP("homelab")


def _run(argv: list[str], cwd: Path, timeout: int = 60) -> dict[str, Any]:
    proc = subprocess.run(
        argv,
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )
    return {
        "command": argv,
        "cwd": str(cwd),
        "returncode": proc.returncode,
        "stdout": proc.stdout[-20000:],
        "stderr": proc.stderr[-12000:],
    }


def _json_or_text(result: dict[str, Any]) -> Any:
    if result["returncode"] != 0:
        return result
    try:
        return json.loads(result["stdout"])
    except json.JSONDecodeError:
        return result


def _env_required(*names: str) -> str | None:
    missing = [name for name in names if not os.getenv(name)]
    if missing:
        return "missing environment variables: " + ", ".join(missing)
    return None


def _http_json(url: str, headers: dict[str, str] | None = None, timeout: int = 15) -> dict[str, Any]:
    request = urllib.request.Request(url, headers=headers or {})
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
            body = response.read(1024 * 1024).decode("utf-8", "replace")
            try:
                parsed: Any = json.loads(body)
            except json.JSONDecodeError:
                parsed = body[:4000]
            return {
                "url": url,
                "status": response.status,
                "content_type": response.headers.get("content-type"),
                "body": parsed,
            }
    except urllib.error.HTTPError as exc:
        body = exc.read(8192).decode("utf-8", "replace")
        return {"url": url, "status": exc.code, "error": str(exc), "body_preview": body[:2000]}
    except Exception as exc:
        return {"url": url, "error": repr(exc)}


def _basic_auth(user: str, password: str) -> str:
    raw = f"{user}:{password}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


def _safe_project_path(relative_path: str) -> Path:
    path = (ROOT / relative_path).resolve()
    if path != ROOT and ROOT not in path.parents:
        raise ValueError("path must stay inside homelab-infra")
    return path


def _redact(value: str) -> str:
    lowered = value.lower()
    if any(token in lowered for token in ("password", "secret", "token", "vault")):
        return "<redacted>"
    return value


def _db() -> sqlite3.Connection:
    OPS_DB.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(OPS_DB)
    conn.row_factory = sqlite3.Row
    conn.executescript(
        """
        create table if not exists verify_results (
          id integer primary key autoincrement,
          created_at text not null,
          scope text not null,
          status text not null,
          summary text not null,
          details_json text not null default '{}'
        );
        create table if not exists assets (
          id integer primary key autoincrement,
          name text not null unique,
          kind text not null,
          status text not null default 'unknown',
          owner text,
          metadata_json text not null default '{}',
          updated_at text not null
        );
        create table if not exists operations (
          id integer primary key autoincrement,
          created_at text not null,
          operation_type text not null,
          target text not null,
          status text not null,
          summary text not null,
          details_json text not null default '{}'
        );
        create table if not exists helpdesk_tickets (
          id integer primary key autoincrement,
          ticket_ref text not null unique,
          opened_at text not null,
          priority text not null,
          scenario text not null,
          requester text,
          target text not null,
          status text not null,
          first_response_at text,
          resolved_at text,
          recurrence_key text,
          summary text not null,
          resolution text,
          data_classification text not null default 'simulation',
          reopen_count integer not null default 0,
          updated_at text not null
        );
        create table if not exists helpdesk_events (
          id integer primary key autoincrement,
          ticket_ref text not null,
          event_type text not null,
          event_at text not null,
          actor text not null,
          note text not null,
          metadata_json text not null default '{}',
          foreign key(ticket_ref) references helpdesk_tickets(ticket_ref)
        );
        create index if not exists helpdesk_events_ticket_time
          on helpdesk_events(ticket_ref, event_at, id);
        create table if not exists asset_history (
          id integer primary key autoincrement,
          asset_name text not null,
          action text not null,
          from_status text not null,
          to_status text not null,
          previous_owner text,
          new_owner text,
          ticket_ref text not null,
          approved_by text not null,
          reason text not null,
          evidence_ref text,
          changed_at text not null,
          metadata_json text not null default '{}',
          foreign key(asset_name) references assets(name)
        );
        create index if not exists asset_history_asset_time
          on asset_history(asset_name, changed_at, id);
        """
    )
    return conn


def _github_repo() -> dict[str, str] | None:
    result = _run(["git", "remote", "get-url", "origin"], ROOT)
    if result["returncode"] != 0:
        return None
    remote = result["stdout"].strip()
    if remote.startswith("git@github.com:"):
        repo = remote.removeprefix("git@github.com:").removesuffix(".git")
    elif "github.com" in remote:
        parsed = urllib.parse.urlparse(remote)
        repo = parsed.path.strip("/").removesuffix(".git")
    else:
        return None
    if "/" not in repo:
        return None
    owner, name = repo.split("/", 1)
    return {"owner": owner, "repo": name, "remote": remote}


def _github_api(method: str, path: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    missing = _env_required("GITHUB_TOKEN")
    if missing:
        return {"error": missing}
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        "https://api.github.com" + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read(1024 * 1024).decode("utf-8", "replace")
            return {"status": response.status, "body": json.loads(body) if body else {}}
    except urllib.error.HTTPError as exc:
        body = exc.read(8192).decode("utf-8", "replace")
        return {"status": exc.code, "error": str(exc), "body_preview": body[:2000]}
    except Exception as exc:
        return {"error": repr(exc)}


def _post_json(url: str, payload: dict[str, Any], headers: dict[str, str] | None = None) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=20, context=context) as response:
            body = response.read(1024 * 1024).decode("utf-8", "replace")
            try:
                parsed: Any = json.loads(body) if body else {}
            except json.JSONDecodeError:
                parsed = body[:4000]
            return {"status": response.status, "body": parsed}
    except urllib.error.HTTPError as exc:
        body = exc.read(8192).decode("utf-8", "replace")
        return {"status": exc.code, "error": str(exc), "body_preview": body[:2000]}
    except Exception as exc:
        return {"error": repr(exc)}


@mcp.tool
def ansible_inventory() -> Any:
    """Return the Ansible inventory as JSON for the homelab project."""
    result = _run(
        ["ansible-inventory", "-i", "inventory/hosts", "--list"],
        ANSIBLE_DIR,
    )
    return _json_or_text(result)


@mcp.tool
def ansible_hosts() -> dict[str, Any]:
    """Return inventory groups and host connection names without vault data."""
    inventory = ansible_inventory()
    if not isinstance(inventory, dict):
        return {"error": "inventory command failed", "result": inventory}

    groups: dict[str, list[str]] = {}
    for name, value in inventory.items():
        if name.startswith("_") or not isinstance(value, dict):
            continue
        hosts = value.get("hosts", [])
        children = value.get("children", [])
        groups[name] = sorted([*hosts, *[f"{child}/*" for child in children]])

    hostvars = inventory.get("_meta", {}).get("hostvars", {})
    hosts = {
        host: {
            key: value
            for key, value in vars.items()
            if key in {"ansible_host", "ansible_user", "ansible_python_interpreter"}
        }
        for host, vars in hostvars.items()
    }
    return {"groups": groups, "hosts": hosts}


@mcp.tool
def ansible_playbook_syntax(playbook: str) -> dict[str, Any]:
    """Run ansible-playbook --syntax-check for a project playbook path."""
    playbook_path = Path(playbook)
    if playbook_path.is_absolute() or ".." in playbook_path.parts:
        return {"error": "playbook must be a relative path inside ansible/"}
    return _run(
        ["ansible-playbook", "-i", "inventory/hosts", "--syntax-check", str(playbook_path)],
        ANSIBLE_DIR,
        timeout=120,
    )


@mcp.tool
def terraform_state_list() -> dict[str, Any]:
    """Return terraform state addresses without rendering state values."""
    result = _run(["terraform", "state", "list"], TERRAFORM_DIR)
    if result["returncode"] != 0:
        return result
    addresses = [line for line in result["stdout"].splitlines() if line.strip()]
    by_prefix: dict[str, int] = {}
    for address in addresses:
        prefix = address.split(".", 1)[0]
        by_prefix[prefix] = by_prefix.get(prefix, 0) + 1
    return {"count": len(addresses), "by_prefix": by_prefix, "addresses": addresses}


@mcp.tool
def terraform_validate() -> dict[str, Any]:
    """Run terraform validate in the project terraform directory."""
    return _run(["terraform", "validate", "-no-color"], TERRAFORM_DIR, timeout=120)


@mcp.tool
def service_health(service: str) -> dict[str, Any]:
    """Check a basic HTTP endpoint for wazuh, nextcloud, keycloak, or proxmox."""
    defaults = {
        "wazuh": os.getenv("WAZUH_URL", "https://wazuh.toss.lan:55000"),
        "nextcloud": os.getenv("NEXTCLOUD_URL", "https://nextcloud.toss.lan"),
        "keycloak": os.getenv("KEYCLOAK_URL", "https://keycloak.toss.lan"),
        "proxmox": os.getenv("PROXMOX_URL", "https://192.168.0.200:8006"),
    }
    paths = {
        "wazuh": "/",
        "nextcloud": "/status.php",
        "keycloak": f"/realms/{os.getenv('KEYCLOAK_REALM', 'homelab')}/.well-known/openid-configuration",
        "proxmox": "/api2/json/version",
    }
    if service not in defaults:
        return {"error": f"unknown service: {service}", "known_services": sorted(defaults)}

    url = defaults[service].rstrip("/") + paths[service]
    request = urllib.request.Request(url, headers={"User-Agent": "homelab-mcp/1.0"})
    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, timeout=10, context=context) as response:
            body = response.read(4096).decode("utf-8", "replace")
            return {
                "service": service,
                "url": url,
                "status": response.status,
                "content_type": response.headers.get("content-type"),
                "body_preview": body[:1000],
            }
    except urllib.error.HTTPError as exc:
        return {"service": service, "url": url, "status": exc.code, "error": str(exc)}
    except Exception as exc:
        return {"service": service, "url": url, "error": repr(exc)}



@mcp.tool
def keycloak_openid_configuration() -> dict[str, Any]:
    """Read the Keycloak realm OpenID configuration without admin credentials."""
    base_url = os.getenv("KEYCLOAK_URL", "https://keycloak.toss.lan").rstrip("/")
    realm = os.getenv("KEYCLOAK_REALM", "homelab")
    return _http_json(f"{base_url}/realms/{realm}/.well-known/openid-configuration")


@mcp.tool
def nextcloud_capabilities() -> dict[str, Any]:
    """Read Nextcloud OCS capabilities using NEXTCLOUD_USER and NEXTCLOUD_APP_PASSWORD."""
    missing = _env_required("NEXTCLOUD_USER", "NEXTCLOUD_APP_PASSWORD")
    if missing:
        return {"error": missing}
    base_url = os.getenv("NEXTCLOUD_URL", "https://nextcloud.toss.lan").rstrip("/")
    headers = {
        "Authorization": _basic_auth(os.environ["NEXTCLOUD_USER"], os.environ["NEXTCLOUD_APP_PASSWORD"]),
        "OCS-APIRequest": "true",
        "Accept": "application/json",
    }
    return _http_json(f"{base_url}/ocs/v1.php/cloud/capabilities?format=json", headers=headers)


@mcp.tool
def wazuh_manager_info() -> dict[str, Any]:
    """Read Wazuh manager info using WAZUH_USER and WAZUH_PASSWORD."""
    missing = _env_required("WAZUH_USER", "WAZUH_PASSWORD")
    if missing:
        return {"error": missing}
    base_url = os.getenv("WAZUH_URL", "https://wazuh.toss.lan:55000").rstrip("/")
    auth_headers = {
        "Authorization": _basic_auth(os.environ["WAZUH_USER"], os.environ["WAZUH_PASSWORD"]),
        "Accept": "application/json",
    }
    auth = _http_json(f"{base_url}/security/user/authenticate", headers=auth_headers)
    token = None
    if isinstance(auth.get("body"), dict):
        token = auth["body"].get("data", {}).get("token")
    if not token:
        return {"error": "could not obtain Wazuh API token", "auth_result": auth}
    return _http_json(
        f"{base_url}/manager/info",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json"},
    )



@mcp.tool
def project_tree(relative_path: str = ".", max_depth: int = 2) -> dict[str, Any]:
    """List files below a project path with depth limiting and secret-name redaction."""
    try:
        base = _safe_project_path(relative_path)
    except ValueError as exc:
        return {"error": str(exc)}
    if not base.exists():
        return {"error": "path does not exist", "path": str(base)}
    base_depth = len(base.relative_to(ROOT).parts)
    entries: list[dict[str, Any]] = []
    for path in sorted(base.rglob("*")) if base.is_dir() else [base]:
        rel = path.relative_to(ROOT)
        depth = len(rel.parts) - base_depth
        if depth > max_depth or ".git" in rel.parts or "__pycache__" in rel.parts:
            continue
        entries.append({"path": _redact(str(rel)), "type": "dir" if path.is_dir() else "file"})
    return {"root": str(base.relative_to(ROOT)), "entries": entries[:500], "truncated": len(entries) > 500}


@mcp.tool
def read_project_file(relative_path: str, max_bytes: int = 50000) -> dict[str, Any]:
    """Read a UTF-8 text file inside the project with size limiting."""
    try:
        path = _safe_project_path(relative_path)
    except ValueError as exc:
        return {"error": str(exc)}
    if not path.is_file():
        return {"error": "not a file", "path": str(path)}
    if any(token in path.name.lower() for token in ("vault", "secret", "password", "tfstate")):
        return {"error": "refusing to read secret-like or state file by name", "path": str(path.relative_to(ROOT))}
    data = path.read_bytes()[:max_bytes]
    return {"path": str(path.relative_to(ROOT)), "content": data.decode("utf-8", "replace"), "truncated": path.stat().st_size > max_bytes}


@mcp.tool
def write_project_file(relative_path: str, content: str) -> dict[str, Any]:
    """Write a UTF-8 text file inside the project. Use only after reviewing the existing file."""
    try:
        path = _safe_project_path(relative_path)
    except ValueError as exc:
        return {"error": str(exc)}
    if any(token in path.name.lower() for token in ("vault", "secret", "password", "tfstate")):
        return {"error": "refusing to write secret-like or state file by name", "path": str(path.relative_to(ROOT))}
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return {"path": str(path.relative_to(ROOT)), "bytes": len(content.encode("utf-8"))}


@mcp.tool
def git_status() -> dict[str, Any]:
    """Return local git branch and porcelain status."""
    branch = _run(["git", "branch", "--show-current"], ROOT)
    status = _run(["git", "status", "--short"], ROOT)
    remote = _run(["git", "remote", "-v"], ROOT)
    return {
        "branch": branch["stdout"].strip(),
        "status": status["stdout"].splitlines(),
        "remote": remote["stdout"].splitlines(),
    }


@mcp.tool
def git_create_branch(branch_name: str, base: str = "HEAD") -> dict[str, Any]:
    """Create and check out a local Git branch for GitOps work."""
    if not branch_name or any(ch.isspace() for ch in branch_name):
        return {"error": "branch_name must be non-empty and contain no whitespace"}
    return _run(["git", "checkout", "-b", branch_name, base], ROOT)


@mcp.tool
def git_commit_all(message: str) -> dict[str, Any]:
    """Commit all current project changes with the provided message."""
    if not message.strip():
        return {"error": "commit message is required"}
    add = _run(["git", "add", "-A"], ROOT)
    if add["returncode"] != 0:
        return add
    return _run(["git", "commit", "-m", message], ROOT)


@mcp.tool
def github_create_issue(title: str, body: str = "", labels: list[str] | None = None) -> dict[str, Any]:
    """Create a GitHub issue using GITHUB_TOKEN and the origin remote."""
    repo = _github_repo()
    if not repo:
        return {"error": "origin remote is not a GitHub repository"}
    payload = {"title": title, "body": body}
    if labels:
        payload["labels"] = labels
    return _github_api("POST", f"/repos/{repo['owner']}/{repo['repo']}/issues", payload)


@mcp.tool
def github_create_pull_request(title: str, head: str, base: str = "main", body: str = "") -> dict[str, Any]:
    """Create a GitHub pull request using GITHUB_TOKEN and the origin remote."""
    repo = _github_repo()
    if not repo:
        return {"error": "origin remote is not a GitHub repository"}
    return _github_api(
        "POST",
        f"/repos/{repo['owner']}/{repo['repo']}/pulls",
        {"title": title, "head": head, "base": base, "body": body},
    )


@mcp.tool
def ops_db_record_verify_result(scope: str, status: str, summary: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    """Store a verification result in the local SQLite operations database."""
    now = dt.datetime.now(dt.UTC).isoformat()
    with _db() as conn:
        cur = conn.execute(
            "insert into verify_results(created_at, scope, status, summary, details_json) values (?, ?, ?, ?, ?)",
            (now, scope, status, summary, json.dumps(details or {}, sort_keys=True)),
        )
        return {"id": cur.lastrowid, "created_at": now}


@mcp.tool
def ops_db_recent_verify_results(limit: int = 20) -> list[dict[str, Any]]:
    """Read recent verification results from the local SQLite operations database."""
    limit = max(1, min(limit, 100))
    with _db() as conn:
        rows = conn.execute(
            "select id, created_at, scope, status, summary, details_json from verify_results order by id desc limit ?",
            (limit,),
        ).fetchall()
    return [dict(row) for row in rows]


@mcp.tool
def ops_db_upsert_asset(name: str, kind: str, status: str = "unknown", owner: str | None = None, metadata: dict[str, Any] | None = None) -> dict[str, Any]:
    """Upsert an IT asset record in the local SQLite operations database."""
    now = dt.datetime.now(dt.UTC).isoformat()
    with _db() as conn:
        existing = conn.execute(
            "select kind, status, owner from assets where name = ?", (name,)
        ).fetchone()
        if existing and (
            existing["kind"] == "endpoint" or kind == "endpoint"
        ) and tuple(existing) != (kind, status, owner):
            return {
                "error": (
                    "existing endpoint kind/status/owner changes must use "
                    "scripts/asset-lifecycle.py"
                )
            }
        conn.execute(
            """
            insert into assets(name, kind, status, owner, metadata_json, updated_at)
            values (?, ?, ?, ?, ?, ?)
            on conflict(name) do update set
              kind=excluded.kind,
              status=excluded.status,
              owner=excluded.owner,
              metadata_json=excluded.metadata_json,
              updated_at=excluded.updated_at
            """,
            (name, kind, status, owner, json.dumps(metadata or {}, sort_keys=True), now),
        )
        if existing is None and kind == "endpoint":
            conn.execute(
                """
                insert into asset_history(
                  asset_name, action, from_status, to_status, previous_owner,
                  new_owner, ticket_ref, approved_by, reason, changed_at,
                  metadata_json
                ) values (?, 'register', 'untracked', ?, null, ?,
                          'MCP-ASSET-REGISTER', 'workflow:homelab-mcp',
                          'Initial endpoint registration', ?, '{}')
                """,
                (name, status, owner, now),
            )
    return {"name": name, "updated_at": now}


@mcp.tool
def ops_db_assets(kind: str | None = None) -> list[dict[str, Any]]:
    """Read IT asset records from the local SQLite operations database."""
    with _db() as conn:
        if kind:
            rows = conn.execute("select * from assets where kind = ? order by name", (kind,)).fetchall()
        else:
            rows = conn.execute("select * from assets order by kind, name").fetchall()
    return [dict(row) for row in rows]


def _notion_headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {os.environ['NOTION_TOKEN']}",
        "Notion-Version": "2026-03-11",
        "Accept": "application/json",
    }


def _notion_text_blocks(content: str) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        block_type = "paragraph"
        text = line
        if line.startswith("# "):
            block_type = "heading_1"
            text = line.removeprefix("# ").strip()
        elif line.startswith("## "):
            block_type = "heading_2"
            text = line.removeprefix("## ").strip()
        elif line.startswith("### "):
            block_type = "heading_3"
            text = line.removeprefix("### ").strip()
        elif line.startswith("- "):
            block_type = "bulleted_list_item"
            text = line.removeprefix("- ").strip()
        if not text:
            continue
        for offset in range(0, len(text), 1800):
            chunk = text[offset : offset + 1800]
            blocks.append(
                {
                    "object": "block",
                    "type": block_type,
                    block_type: {"rich_text": [{"type": "text", "text": {"content": chunk}}]},
                }
            )
    return blocks[:90]


def _notion_create_page(parent_page_id: str, title: str, content: str) -> dict[str, Any]:
    payload = {
        "parent": {"page_id": parent_page_id},
        "properties": {"title": {"title": [{"text": {"content": title[:2000]}}]}},
        "children": _notion_text_blocks(content),
    }
    return _post_json("https://api.notion.com/v1/pages", payload, headers=_notion_headers())


@mcp.tool
def slack_notify(text: str, channel: str | None = None) -> dict[str, Any]:
    """Send an operations notification through SLACK_WEBHOOK_URL."""
    missing = _env_required("SLACK_WEBHOOK_URL")
    if missing:
        return {"error": missing}
    payload: dict[str, Any] = {"text": text}
    if channel:
        payload["channel"] = channel
    return _post_json(os.environ["SLACK_WEBHOOK_URL"], payload)


@mcp.tool
def notion_create_page(title: str, content: str, parent_page_id: str | None = None) -> dict[str, Any]:
    """Create a Notion page under NOTION_PARENT_PAGE_ID or the provided parent_page_id."""
    missing = _env_required("NOTION_TOKEN")
    if missing:
        return {"error": missing}
    parent = parent_page_id or os.getenv("NOTION_PARENT_PAGE_ID")
    if not parent:
        return {"error": "missing environment variable or argument: NOTION_PARENT_PAGE_ID"}
    return _notion_create_page(parent, title, content)


@mcp.tool
def notion_publish_project_file(relative_path: str, title: str | None = None, parent_page_id: str | None = None) -> dict[str, Any]:
    """Publish a project markdown/text file to Notion as an operations document."""
    missing = _env_required("NOTION_TOKEN")
    if missing:
        return {"error": missing}
    parent = parent_page_id or os.getenv("NOTION_PARENT_PAGE_ID")
    if not parent:
        return {"error": "missing environment variable or argument: NOTION_PARENT_PAGE_ID"}
    try:
        path = _safe_project_path(relative_path)
    except ValueError as exc:
        return {"error": str(exc)}
    if not path.is_file():
        return {"error": f"file not found: {relative_path}"}
    content = path.read_text(encoding="utf-8", errors="replace")
    page_title = title or path.stem.replace("-", " ").title()
    return _notion_create_page(parent, page_title, content)


@mcp.tool
def jira_create_issue(summary: str, description: str, issue_type: str = "Task") -> dict[str, Any]:
    """Create a Jira issue using JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, and JIRA_PROJECT_KEY."""
    missing = _env_required("JIRA_BASE_URL", "JIRA_EMAIL", "JIRA_API_TOKEN", "JIRA_PROJECT_KEY")
    if missing:
        return {"error": missing}
    base_url = os.environ["JIRA_BASE_URL"].rstrip("/")
    auth = _basic_auth(os.environ["JIRA_EMAIL"], os.environ["JIRA_API_TOKEN"])
    payload = {
        "fields": {
            "project": {"key": os.environ["JIRA_PROJECT_KEY"]},
            "summary": summary,
            "description": description,
            "issuetype": {"name": issue_type},
        }
    }
    return _post_json(
        f"{base_url}/rest/api/2/issue",
        payload,
        headers={"Authorization": auth, "Accept": "application/json"},
    )


@mcp.tool
def docker_ps(all_containers: bool = False) -> dict[str, Any]:
    """Return docker container status when Docker CLI is available."""
    if not shutil.which("docker"):
        return {"error": "docker CLI is not installed on this host"}
    argv = ["docker", "ps", "--format", "json"]
    if all_containers:
        argv.insert(2, "--all")
    result = _run(argv, ROOT)
    if result["returncode"] != 0:
        return result
    rows = [json.loads(line) for line in result["stdout"].splitlines() if line.strip()]
    return {"containers": rows}


@mcp.tool
def docker_logs(container: str, tail: int = 100) -> dict[str, Any]:
    """Return recent docker logs for a container when Docker CLI is available."""
    if not shutil.which("docker"):
        return {"error": "docker CLI is not installed on this host"}
    tail = max(1, min(tail, 1000))
    return _run(["docker", "logs", "--tail", str(tail), container], ROOT, timeout=60)


@mcp.tool
def docker_restart(container: str) -> dict[str, Any]:
    """Restart a docker container. Requires explicit MCP tool approval in Codex."""
    if not shutil.which("docker"):
        return {"error": "docker CLI is not installed on this host"}
    return _run(["docker", "restart", container], ROOT, timeout=120)


@mcp.tool
def proxmox_vms() -> dict[str, Any]:
    """Read Proxmox cluster VM resources using token env vars."""
    missing = _env_required("PROXMOX_URL", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET")
    if missing:
        return {"error": missing}
    base_url = os.environ["PROXMOX_URL"].rstrip("/")
    headers = {
        "Authorization": f"PVEAPIToken={os.environ['PROXMOX_TOKEN_ID']}={os.environ['PROXMOX_TOKEN_SECRET']}",
        "Accept": "application/json",
    }
    return _http_json(f"{base_url}/api2/json/cluster/resources?type=vm", headers=headers)


@mcp.tool
def proxmox_node_status(node: str = "pve01") -> dict[str, Any]:
    """Read Proxmox node status using token env vars."""
    missing = _env_required("PROXMOX_URL", "PROXMOX_TOKEN_ID", "PROXMOX_TOKEN_SECRET")
    if missing:
        return {"error": missing}
    base_url = os.environ["PROXMOX_URL"].rstrip("/")
    headers = {
        "Authorization": f"PVEAPIToken={os.environ['PROXMOX_TOKEN_ID']}={os.environ['PROXMOX_TOKEN_SECRET']}",
        "Accept": "application/json",
    }
    return _http_json(f"{base_url}/api2/json/nodes/{node}/status", headers=headers)


if __name__ == "__main__":
    mcp.run()
