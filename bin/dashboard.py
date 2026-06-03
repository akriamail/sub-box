#!/usr/bin/env python3
"""sub-box dashboard — FastAPI backend (single file)."""

import asyncio
import hashlib
import json
import re
import secrets
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel

# ── Constants ──────────────────────────────────────────────
SUB_BOX_DIR    = Path("/opt/subscribe")
CONFIG_INI     = SUB_BOX_DIR / "config.ini"
EXTEND_INI     = SUB_BOX_DIR / "extend.ini"
AIRPORT_URL    = SUB_BOX_DIR / "airport_url.txt"
ENROLL_TOKEN   = SUB_BOX_DIR / ".enroll-token"
DASH_TOKEN     = SUB_BOX_DIR / ".dashboard-token"
SING_BOX_JSON  = Path("/etc/sing-box/config.json")
CERT_DIR       = Path("/root/cert")
BIN_DIR        = SUB_BOX_DIR / "bin"
STATE_DIR      = SUB_BOX_DIR / "state"
AGENTS_JSON    = STATE_DIR / "agents.json"
INSTALL_TOKENS = STATE_DIR / "install_tokens.json"
AGENT_NODES_INI = STATE_DIR / "agent_nodes.ini"
ARTIFACT_DIR   = SUB_BOX_DIR / "artifacts"

app = FastAPI(title="sub-box dashboard", version="2.1.0")

# ── Auth ───────────────────────────────────────────────────
def get_dash_token() -> str:
    if DASH_TOKEN.exists():
        return DASH_TOKEN.read_text().strip()
    tok = secrets.token_hex(16)
    DASH_TOKEN.write_text(tok)
    DASH_TOKEN.chmod(0o600)
    return tok

def verify_token(request: Request) -> None:
    tok = request.headers.get("X-Dashboard-Token", "")
    if not tok or tok != get_dash_token():
        raise HTTPException(401, "invalid dashboard token")

def node_id(path: Path, line: str) -> str:
    return hashlib.sha256(f"{path.name}\0{line}".encode()).hexdigest()[:12]

def now_iso() -> str:
    return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"

def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except Exception:
        return default

def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)

def model_updates(model: BaseModel) -> dict[str, Any]:
    if hasattr(model, "model_dump"):
        return model.model_dump(exclude_unset=True)
    return model.dict(exclude_unset=True)

def get_agents() -> dict[str, Any]:
    return read_json(AGENTS_JSON, {})

def save_agents(agents: dict[str, Any]) -> None:
    write_json(AGENTS_JSON, agents)
    write_agent_nodes_ini(agents)

def get_install_tokens() -> dict[str, Any]:
    return read_json(INSTALL_TOKENS, {})

def save_install_tokens(tokens: dict[str, Any]) -> None:
    write_json(INSTALL_TOKENS, tokens)

def default_secret(protocol: str) -> str:
    if protocol in {"vmess", "vless"}:
        import uuid
        return str(uuid.uuid4())
    return secrets.token_hex(8)

def public_base_url(request: Request | None = None) -> str:
    if request is not None:
        proto = request.headers.get("X-Forwarded-Proto") or request.url.scheme
        host = request.headers.get("X-Forwarded-Host") or request.headers.get("Host")
        if host:
            return f"{proto}://{host}"
    cfg = read_ini(CONFIG_INI, "common")
    domain = cfg.get("domain", "127.0.0.1")
    port = cfg.get("port", "8080")
    if port == "443":
        return f"https://{domain}"
    return f"https://{domain}:{port}"

def agent_node_line(agent: dict[str, Any]) -> str:
    desired = agent.get("desired", {})
    protocol = desired.get("protocol", "trojan")
    domain = desired.get("domain") or agent.get("reported", {}).get("public_ip") or agent["id"]
    port = int(desired.get("port", 443))
    secret = desired.get("secret", "")
    remark = desired.get("remark") or agent.get("name") or agent["id"]
    if protocol == "vmess":
        payload = {
            "v": "2",
            "ps": remark,
            "add": domain,
            "port": str(port),
            "id": secret,
            "aid": "0",
            "net": "tcp",
            "type": "none",
            "host": "",
            "path": "",
            "tls": "",
        }
        import base64
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        link = "vmess://" + base64.b64encode(raw.encode()).decode()
    elif protocol == "trojan":
        link = f"trojan://{secret}@{domain}:{port}?security=none&type=tcp#{remark}"
    elif protocol in {"hysteria2", "hy2"}:
        link = f"hysteria2://{secret}@{domain}:{port}?insecure=1#{remark}"
    elif protocol == "vless":
        link = f"vless://{secret}@{domain}:{port}?encryption=none&security=none&type=tcp#{remark}"
    else:
        link = build_node_uri(protocol, domain, port, secret, remark)
    return f"{link}|{remark}"

def write_agent_nodes_ini(agents: dict[str, Any]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["[nodes]"]
    for agent in agents.values():
        desired = agent.get("desired", {})
        reported = agent.get("reported", {})
        if desired.get("enabled", True) and reported.get("enrolled"):
            lines.append(agent_node_line(agent))
    AGENT_NODES_INI.write_text("\n".join(lines) + "\n")

# ── INI Helpers ────────────────────────────────────────────
def read_ini(path: Path, section: str) -> dict[str, str]:
    """Read key=value pairs from an INI section."""
    if not path.exists():
        return {}
    text = path.read_text()
    in_section = False
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_section = (line[1:-1].strip() == section)
            continue
        if in_section and "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            result[k.strip()] = v.strip()
    return result

def read_nodes_section(path: Path) -> list[dict]:
    """Read [nodes] section, return list of parsed nodes."""
    if not path.exists():
        return []
    text = path.read_text()
    in_nodes = False
    nodes = []
    for i, line in enumerate(text.splitlines()):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_nodes = (stripped[1:-1].strip() == "nodes")
            continue
        if not in_nodes or not stripped or stripped.startswith("#"):
            continue
        # Parse node line: either full URI|remark or proto|host|port|secret|remark
        if "|" in stripped:
            parts = [p.strip() for p in stripped.split("|")]
            if "://" in parts[0]:
                # Full URI format
                node = {"id": node_id(path, stripped),
                        "line": stripped, "source": path.stem, "raw": stripped}
                node.update(parse_uri_node(parts[0], parts[1] if len(parts) > 1 else ""))
            elif len(parts) >= 4:
                proto, host, port, secret = parts[0], parts[1], parts[2], parts[3]
                remark = parts[4] if len(parts) > 4 else f"{proto}-{host}-{port}"
                link = build_node_uri(proto, host, int(port), secret, remark if remark else proto)
                node = {"id": node_id(path, stripped),
                        "line": stripped, "source": path.stem,
                        "protocol": proto, "host": host, "port": int(port),
                        "secret": secret, "remark": remark, "link": link}
            nodes.append(node)
    return nodes

def parse_uri_node(uri: str, remark: str) -> dict:
    """Extract protocol/host/port/secret from a node URI."""
    m = re.match(r"(\w+)://([^@]+)@([^:]+):(\d+)", uri)
    if m:
        return {"protocol": m.group(1), "secret": m.group(2),
                "host": m.group(3), "port": int(m.group(4)),
                "remark": remark, "link": uri}
    return {"protocol": "?", "secret": "?", "host": "?", "port": 0,
            "remark": remark, "link": uri}

def build_node_uri(proto: str, host: str, port: int, secret: str, remark: str) -> str:
    """Build a standard node URI string."""
    enc = remark  # simplified
    if proto == "trojan":
        return f"trojan://{secret}@{host}:{port}?security=tls&sni={host}&type=tcp#{enc}"
    elif proto == "vmess":
        return f"vmess://{secret}@{host}:{port}?encryption=none#{enc}"
    elif proto == "vless":
        return f"vless://{secret}@{host}:{port}?encryption=none&security=reality#{enc}"
    elif proto == "hysteria2" or proto == "hy2":
        return f"hysteria2://{secret}@{host}:{port}?sni={host}#{enc}"
    elif proto == "ss":
        return f"ss://{secret}@{host}:{port}#{enc}"
    return f"{proto}://{secret}@{host}:{port}#{enc}"

def append_node_line(path: Path, line: str) -> None:
    """Append a node without rewriting existing comments or formatting."""
    if not path.exists():
        path.write_text("[nodes]\n")
    text = path.read_text()
    suffix = "\n" if text.endswith("\n") else "\n\n"
    if "[nodes]" not in text:
        path.write_text(text + suffix + "[nodes]\n" + line + "\n")
    else:
        path.write_text(text + suffix + line + "\n")

def delete_node_line(path: Path, wanted_id: str) -> bool:
    if not path.exists():
        return False
    lines = path.read_text().splitlines()
    out = []
    in_nodes = False
    deleted = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_nodes = (stripped[1:-1].strip() == "nodes")
        if in_nodes and not deleted and stripped and not stripped.startswith("#"):
            if node_id(path, stripped) == wanted_id:
                deleted = True
                continue
        out.append(line)
    if deleted:
        path.write_text("\n".join(out) + "\n")
    return deleted

# ── System Status ──────────────────────────────────────────
def run(cmd: list[str], timeout: int = 5) -> tuple[int, str, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except Exception:
        return -1, "", ""

def system_status() -> dict:
    rc, out, _ = run(["systemctl", "is-active", "sing-box"])
    if rc != 0:
        # fallback: check via pgrep in container envs without systemd
        rc2, _, _ = run(["pgrep", "sing-box"])
        singbox_ok = (rc2 == 0)
    else:
        singbox_ok = True

    rc, out, _ = run(["systemctl", "is-active", "nginx"])
    if rc != 0:
        rc2, _, _ = run(["pgrep", "nginx"])
        nginx_ok = (rc2 == 0)
    else:
        nginx_ok = True

    cert_days = "?"
    cert_domain = read_ini(CONFIG_INI, "common").get("cert_domain", "")
    domain = read_ini(CONFIG_INI, "common").get("domain", "")
    d = cert_domain or domain
    if d:
        # cert-manager mounts tls.crt; acme.sh uses fullchain.pem
        for name in ["tls.crt", "fullchain.pem"]:
            cert_file = CERT_DIR / d / name
            if cert_file.exists():
                rc, out, _ = run(["openssl", "x509", "-in", str(cert_file),
                                  "-noout", "-enddate"])
                if rc == 0 and "notAfter=" in out:
                    end_str = out.split("=", 1)[1].strip()
                    try:
                        end = datetime.strptime(end_str, "%b %d %H:%M:%S %Y %Z")
                        cert_days = (end - datetime.now()).days
                    except Exception:
                        cert_days = "?"
                break

    _, mem_out, _ = run(["free", "-m"])
    mem_used = mem_total = "?"
    for line in mem_out.splitlines():
        if "Mem:" in line:
            parts = line.split()
            mem_total, mem_used = parts[1], parts[2]

    _, df_out, _ = run(["df", "-h", "/"])
    disk_pct = disk_total = disk_used = "?"
    for line in df_out.splitlines():
        if "/dev/" in line or "overlay" in line:
            parts = line.split()
            if len(parts) >= 5:
                disk_total, disk_used, disk_pct = parts[1], parts[2], parts[4]

    return {
        "singbox": "running" if singbox_ok else "stopped",
        "nginx": "running" if nginx_ok else "stopped",
        "cert_domain": d,
        "cert_days": cert_days,
        "mem_used_mb": mem_used,
        "mem_total_mb": mem_total,
        "disk_total": disk_total,
        "disk_used": disk_used,
        "disk_pct": disk_pct,
    }

# ── TCP Latency Check ──────────────────────────────────────
def tcp_check(host: str, port: int, timeout: float = 3.0) -> Optional[int]:
    """TCP connect latency in ms, or None if timeout."""
    import socket
    start = time.monotonic()
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        elapsed = int((time.monotonic() - start) * 1000)
        s.close()
        return elapsed
    except Exception:
        return None

# ── Pydantic Models ────────────────────────────────────────
class NodeInput(BaseModel):
    protocol: str
    host: str
    port: int = 443
    secret: str
    remark: str = ""

class AirportSelect(BaseModel):
    nodes: list[str]  # list of node IDs to enable

class InstallTokenInput(BaseModel):
    name: str
    domain: str = ""
    protocol: str = "vmess"
    port: int = 443
    remark: str = ""
    enabled: bool = True

class AgentEnrollInput(BaseModel):
    hostname: str
    public_ip: str = ""
    version: str = "unknown"

class AgentReportInput(BaseModel):
    revision: int = 0
    apply_ok: bool = True
    apply_error: str = ""
    metrics: dict[str, Any] = {}
    services: dict[str, Any] = {}

class AgentDesiredInput(BaseModel):
    protocol: Optional[str] = None
    port: Optional[int] = None
    secret: Optional[str] = None
    domain: Optional[str] = None
    remark: Optional[str] = None
    enabled: Optional[bool] = None

# ═══════════════════════════════════════════════════════════
#  API Routes
# ═══════════════════════════════════════════════════════════

# ── Nodes ──────────────────────────────────────────────────
@app.get("/api/nodes")
async def list_nodes(request: Request):
    verify_token(request)
    config_nodes = read_nodes_section(CONFIG_INI)
    extend_nodes = read_nodes_section(EXTEND_INI)
    return {"nodes": config_nodes + extend_nodes}

# ── Agents ─────────────────────────────────────────────────
@app.get("/api/agents")
async def list_agents(request: Request):
    verify_token(request)
    return {"agents": list(get_agents().values())}

@app.post("/api/agents/install-token")
async def create_install_token(data: InstallTokenInput, request: Request):
    verify_token(request)
    tokens = get_install_tokens()
    token = secrets.token_urlsafe(24)
    agent_id = re.sub(r"[^a-zA-Z0-9_.-]+", "-", data.name.strip()).strip("-").lower()
    if not agent_id:
        agent_id = "agent-" + secrets.token_hex(3)
    desired = {
        "protocol": data.protocol,
        "port": data.port,
        "secret": default_secret(data.protocol),
        "domain": data.domain,
        "remark": data.remark or data.name,
        "enabled": data.enabled,
        "revision": 1,
    }
    tokens[token] = {
        "token": token,
        "agent_id": agent_id,
        "name": data.name,
        "desired": desired,
        "created_at": now_iso(),
        "used": False,
    }
    save_install_tokens(tokens)
    base_url = public_base_url(request)
    return {
        "token": token,
        "install_url": f"{base_url}/install/{token}",
        "command": f"curl -fsSL {base_url}/install/{token} | bash",
        "desired": desired,
    }

@app.patch("/api/agents/{agent_id}/desired")
async def update_agent_desired(agent_id: str, data: AgentDesiredInput, request: Request):
    verify_token(request)
    agents = get_agents()
    agent = agents.get(agent_id)
    if not agent:
        raise HTTPException(404, "agent not found")
    desired = agent.setdefault("desired", {})
    updates = model_updates(data)
    if updates.get("protocol") and not updates.get("secret"):
        current_protocol = desired.get("protocol")
        if updates["protocol"] != current_protocol:
            updates["secret"] = default_secret(updates["protocol"])
    desired.update(updates)
    desired["revision"] = int(desired.get("revision", 0)) + 1
    agent["updated_at"] = now_iso()
    agents[agent_id] = agent
    save_agents(agents)
    trigger_update()
    return {"ok": True, "agent": agent}

@app.get("/install/{token}")
async def install_script(token: str, request: Request):
    tokens = get_install_tokens()
    item = tokens.get(token)
    if not item or item.get("used"):
        raise HTTPException(404, "install token not found")
    server_url = public_base_url(request)
    script = f"""#!/bin/bash
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash"
  exit 1
fi
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl git python3 python3-venv openssl
if [ ! -d /opt/subscribe ]; then
  git clone https://github.com/akriamail/sub-box.git /opt/subscribe
fi
cd /opt/subscribe
arch="$(uname -m)"
case "$arch" in
  x86_64) sb_arch="amd64" ;;
  aarch64) sb_arch="arm64" ;;
  *) echo "unsupported arch: $arch"; exit 1 ;;
esac
curl -fsSL "{server_url}/artifacts/sing-box/linux/${{sb_arch}}" -o /usr/local/bin/sing-box
chmod 755 /usr/local/bin/sing-box
mkdir -p /etc/sing-box
cat > /etc/systemd/system/sing-box.service <<'SBSERVICE'
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/etc/sing-box
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SBSERVICE
python3 -m venv .agent-venv
.agent-venv/bin/pip install --upgrade pip >/dev/null
.agent-venv/bin/pip install requests >/dev/null
mkdir -p /opt/subscribe/state
cat > /opt/subscribe/state/agent.env <<'ENVEOF'
SUB_BOX_SERVER={server_url}
SUB_BOX_INSTALL_TOKEN={token}
ENVEOF
cat > /etc/systemd/system/sub-box-agent.service <<'SERVICEEOF'
[Unit]
Description=sub-box agent
After=network.target

[Service]
User=root
WorkingDirectory=/opt/subscribe
EnvironmentFile=/opt/subscribe/state/agent.env
ExecStart=/opt/subscribe/.agent-venv/bin/python /opt/subscribe/bin/agent.py
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SERVICEEOF
systemctl daemon-reload
systemctl enable --now sub-box-agent
echo "sub-box agent installed and started"
"""
    return PlainTextResponse(script, media_type="text/plain")

@app.get("/artifacts/sing-box/linux/{arch}")
async def download_sing_box(arch: str):
    if arch not in {"amd64", "arm64"}:
        raise HTTPException(404, "unsupported arch")
    path = ARTIFACT_DIR / f"sing-box-linux-{arch}"
    if not path.exists():
        raise HTTPException(404, "artifact not prepared")
    return FileResponse(path, media_type="application/octet-stream", filename=f"sing-box-linux-{arch}")

@app.get("/artifacts/sha256sums.txt")
async def download_sha256sums():
    path = ARTIFACT_DIR / "sha256sums.txt"
    if not path.exists():
        raise HTTPException(404, "artifact not prepared")
    return FileResponse(path, media_type="text/plain")

@app.post("/api/agents/enroll")
async def enroll_agent(data: AgentEnrollInput, request: Request):
    token = request.headers.get("X-Install-Token", "")
    tokens = get_install_tokens()
    item = tokens.get(token)
    if not item or item.get("used"):
        raise HTTPException(401, "invalid install token")
    agent_token = secrets.token_urlsafe(32)
    agent = {
        "id": item["agent_id"],
        "name": item["name"],
        "agent_token": agent_token,
        "desired": item["desired"],
        "reported": {
            "enrolled": True,
            "hostname": data.hostname,
            "public_ip": data.public_ip,
            "version": data.version,
            "last_seen": now_iso(),
        },
        "created_at": now_iso(),
        "updated_at": now_iso(),
    }
    agents = get_agents()
    agents[agent["id"]] = agent
    save_agents(agents)
    item["used"] = True
    item["used_at"] = now_iso()
    save_install_tokens(tokens)
    trigger_update()
    return {"agent_id": agent["id"], "agent_token": agent_token, "desired": agent["desired"]}

def verify_agent(request: Request) -> tuple[str, dict[str, Any]]:
    agent_id = request.headers.get("X-Agent-Id", "")
    agent_token = request.headers.get("X-Agent-Token", "")
    agents = get_agents()
    agent = agents.get(agent_id)
    if not agent or agent.get("agent_token") != agent_token:
        raise HTTPException(401, "invalid agent token")
    return agent_id, agent

@app.get("/api/agents/config")
async def agent_config(request: Request):
    _, agent = verify_agent(request)
    return {"desired": agent.get("desired", {})}

@app.post("/api/agents/report")
async def agent_report(data: AgentReportInput, request: Request):
    agent_id, agent = verify_agent(request)
    agents = get_agents()
    reported = agent.setdefault("reported", {})
    reported.update({
        "revision": data.revision,
        "last_apply_ok": data.apply_ok,
        "last_apply_error": data.apply_error,
        "metrics": data.metrics,
        "services": data.services,
        "last_seen": now_iso(),
    })
    agent["updated_at"] = now_iso()
    agents[agent_id] = agent
    save_agents(agents)
    trigger_update()
    return {"ok": True}

@app.post("/api/nodes")
async def add_node(node: NodeInput, request: Request):
    verify_token(request)
    remark = node.remark or f"{node.protocol}-{node.host}-{node.port}"
    link = build_node_uri(node.protocol, node.host, node.port, node.secret, remark)
    line = f"{link}|{remark}"

    append_node_line(CONFIG_INI, line)
    trigger_update()
    return {"ok": True, "node": {"id": node_id(CONFIG_INI, line), "line": line}}

@app.delete("/api/nodes/{node_id}")
async def delete_node(node_id: str, request: Request):
    verify_token(request)
    for path in [CONFIG_INI, EXTEND_INI]:
        if delete_node_line(path, node_id):
            trigger_update()
            return {"ok": True}
    raise HTTPException(404, "node not found")

@app.post("/api/nodes/tcp-check")
async def check_node_tcp(host: str, port: int, request: Request):
    verify_token(request)
    lat = tcp_check(host, port)
    return {"host": host, "port": port, "latency_ms": lat, "reachable": lat is not None}

# ── Airport ────────────────────────────────────────────────
@app.get("/api/airport/status")
async def airport_status(request: Request):
    verify_token(request)
    url = ""
    if AIRPORT_URL.exists():
        url = AIRPORT_URL.read_text().strip()
    nodes = read_nodes_section(EXTEND_INI)
    return {"url": url[:50] + "..." if len(url) > 50 else url,
            "enabled_nodes": len(nodes),
            "nodes": nodes}

@app.post("/api/airport/refresh")
async def airport_refresh(request: Request):
    verify_token(request)
    fetch_sh = BIN_DIR / "fetch_ext.sh"
    if not fetch_sh.exists():
        fetch_sh = SUB_BOX_DIR / "fetch_ext.sh"  # v1.x compat
    rc, out, err = run(["bash", str(fetch_sh)], timeout=45)
    nodes = read_nodes_section(EXTEND_INI)
    return {"ok": rc == 0, "output": out + err, "nodes": nodes}

@app.get("/api/airport/all-nodes")
async def airport_all_nodes(request: Request):
    """Fetch and decode all airport nodes with TCP latency."""
    verify_token(request)
    if not AIRPORT_URL.exists():
        return {"nodes": [], "info": {}}

    import urllib.parse
    sub_url = AIRPORT_URL.read_text().strip()
    if not sub_url:
        return {"nodes": [], "info": {}}

    # Download & decode
    rc, encoded, _ = run(["curl", "-fsSL", "--max-time", "30", sub_url], timeout=35)
    if rc != 0 or not encoded:
        return {"nodes": [], "error": "download failed"}

    try:
        import base64
        raw = base64.b64decode(encoded.replace("\r", "")).decode()
    except Exception:
        return {"nodes": [], "error": "decode failed"}

    # Parse: skip info lines
    skip_kw = ["剩余流量", "下次重置", "套餐到期", "距离下次"]
    all_nodes = []
    info = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or "#" not in line:
            continue
        decoded = urllib.parse.unquote(line)
        if any(k in decoded for k in skip_kw):
            # Extract info
            if "流量" in decoded:
                info["traffic"] = decoded.split("#")[-1]
            elif "到期" in decoded:
                info["expiry"] = decoded.split("#")[-1]
            continue
        link, remark = decoded.split("#", 1)
        m = re.search(r"@([^:]+):(\d+)", link)
        if not m or m.group(1) == "127.0.0.1":
            continue
        host, port = m.group(1), int(m.group(2))
        # Extract region from remark (🇯🇵日本高速01|...)
        region = "其他"
        if "日本" in remark:
            region = "日本"
        elif "台湾" in remark:
            region = "台湾"
        elif "香港" in remark:
            region = "香港"
        elif "新加坡" in remark:
            region = "新加坡"
        elif "美国" in remark:
            region = "美国"
        elif "韩国" in remark:
            region = "韩国"
        elif "英国" in remark:
            region = "英国"

        node_id = hashlib.md5(f"{host}:{port}".encode()).hexdigest()[:8]
        all_nodes.append({
            "id": node_id, "host": host, "port": port,
            "link": link, "remark": remark, "region": region,
            "latency_ms": None, "reachable": False,
        })

    # Speed test in parallel (limited concurrency)
    # Group by host:port to avoid duplicate checks
    seen = {}
    for n in all_nodes:
        key = f"{n['host']}:{n['port']}"
        if key not in seen:
            seen[key] = n

    for n in all_nodes:
        key = f"{n['host']}:{n['port']}"
        if key in seen and seen[key].get("latency_ms") is not None:
            n["latency_ms"] = seen[key]["latency_ms"]
            n["reachable"] = True
        elif key in seen:
            lat = tcp_check(n["host"], n["port"])
            if lat is not None:
                seen[key]["latency_ms"] = lat
                seen[key]["reachable"] = True
                n["latency_ms"] = lat
                n["reachable"] = True

    return {"nodes": sorted(all_nodes, key=lambda n: (n["region"], n.get("latency_ms", 99999) if n.get("latency_ms") else 99999)),
            "info": info}

@app.post("/api/airport/select")
async def airport_select(data: AirportSelect, request: Request):
    """Select specific airport nodes, write to extend.ini."""
    verify_token(request)
    # Get all airport nodes
    result = await airport_all_nodes(request)
    all_nodes = result.get("nodes", [])
    selected = [n for n in all_nodes if n["id"] in data.nodes]

    lines = ["[nodes]"]
    for n in selected:
        lines.append(f"{n['link']}|机场-{n['region']}")

    EXTEND_INI.write_text("\n".join(lines) + "\n")
    trigger_update()
    return {"ok": True, "selected": len(selected)}

# ── Subscription ───────────────────────────────────────────
@app.get("/api/subscription")
async def subscription_info(request: Request):
    verify_token(request)
    cfg = read_ini(CONFIG_INI, "common")
    token = cfg.get("token", "?")
    domain = cfg.get("domain", "?")
    port = cfg.get("port", "8080")
    return {
        "domain": domain, "port": port, "token": token,
        "url": f"https://{domain}:{port}/{token}",
    }

@app.post("/api/subscription/rotate-token")
async def rotate_token(request: Request):
    verify_token(request)
    import secrets
    new_tok = secrets.token_hex(16)
    if CONFIG_INI.exists():
        text = CONFIG_INI.read_text()
        text = re.sub(r"^token\s*=\s*.*", f"token = {new_tok}", text, flags=re.MULTILINE)
        CONFIG_INI.write_text(text)
    trigger_update()
    return {"token": new_tok}

# ── System ─────────────────────────────────────────────────
@app.get("/api/system/status")
async def api_system_status(request: Request):
    verify_token(request)
    return system_status()

# ── SSE Events ─────────────────────────────────────────────
event_queue: list[asyncio.Queue] = []

@app.get("/api/events")
async def sse_events(request: Request):
    verify_token(request)
    q: asyncio.Queue = asyncio.Queue()
    event_queue.append(q)
    try:
        async def gen():
            yield f"data: {json.dumps({'event': 'connected'})}\n\n"
            while True:
                try:
                    data = await asyncio.wait_for(q.get(), timeout=30)
                    yield f"data: {json.dumps(data)}\n\n"
                except asyncio.TimeoutError:
                    yield f"data: {json.dumps({'event': 'ping'})}\n\n"
        return StreamingResponse(gen(), media_type="text/event-stream")
    finally:
        event_queue.remove(q)

def emit_event(data: dict):
    for q in event_queue:
        try:
            q.put_nowait(data)
        except asyncio.QueueFull:
            pass

# ── Misc ───────────────────────────────────────────────────
def trigger_update():
    update_sh = BIN_DIR / "update.sh"
    if not update_sh.exists():
        update_sh = SUB_BOX_DIR / "update.sh"
    if update_sh.exists():
        subprocess.Popen(["bash", str(update_sh)],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    emit_event({"event": "subscription-updated", "time": datetime.now().isoformat()})

@app.post("/api/trigger-update")
async def api_trigger_update(request: Request):
    verify_token(request)
    trigger_update()
    return {"ok": True}

# ── Static (web frontend) ─────────────────────────────────
WEB_DIR = SUB_BOX_DIR / "web" / "dist"
if not WEB_DIR.exists():
    WEB_DIR = SUB_BOX_DIR / "web"

# Serve static assets and SPA index.html
@app.get("/{full_path:path}")
async def serve_spa(full_path: str, request: Request):
    # API routes are matched first via order; this catches everything else
    path = WEB_DIR / (full_path or "index.html")
    if path.exists() and path.is_file():
        return FileResponse(path)
    # SPA fallback
    index_html = WEB_DIR / "index.html"
    if index_html.exists():
        return FileResponse(index_html)
    return {"message": "sub-box dashboard"}

# ═══════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════
if __name__ == "__main__":
    # Ensure token exists
    get_dash_token()
    print(f"Dashboard token: {get_dash_token()}")
    print(f"API docs: http://0.0.0.0:9190/docs")
    uvicorn.run(app, host="0.0.0.0", port=9190, log_level="info")
