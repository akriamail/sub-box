#!/usr/bin/env python3
"""sub-box agent daemon.

The agent enrolls once with the server, pulls desired config, applies local
sing-box config, and reports metrics. It is intentionally small and dependency
light so the one-line installer can run on plain Ubuntu/Debian hosts.
"""

import json
import os
import socket
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Any

import requests

SUB_BOX_DIR = Path("/opt/subscribe")
STATE_DIR = SUB_BOX_DIR / "state"
AGENT_STATE = STATE_DIR / "agent.json"
SING_BOX_CONFIG = Path("/etc/sing-box/config.json")
SING_BOX_BIN = Path("/usr/local/bin/sing-box")
CERT_DIR = Path("/root/cert")

SERVER = os.environ.get("SUB_BOX_SERVER", "").rstrip("/")
INSTALL_TOKEN = os.environ.get("SUB_BOX_INSTALL_TOKEN", "")
INTERVAL = int(os.environ.get("SUB_BOX_AGENT_INTERVAL", "20"))


def now_iso() -> str:
    return datetime.utcnow().replace(microsecond=0).isoformat() + "Z"


def run(cmd: list[str], timeout: int = 10) -> tuple[int, str, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except Exception as exc:
        return -1, "", str(exc)


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


def request_public_ip() -> str:
    for url in ["https://api.ipify.org", "https://icanhazip.com"]:
        try:
            r = requests.get(url, timeout=5)
            if r.ok and r.text.strip():
                return r.text.strip()
        except Exception:
            pass
    return ""


def headers(state: dict[str, Any]) -> dict[str, str]:
    return {
        "X-Agent-Id": state["agent_id"],
        "X-Agent-Token": state["agent_token"],
        "Content-Type": "application/json",
    }


def enroll() -> dict[str, Any]:
    state = read_json(AGENT_STATE, {})
    if state.get("agent_id") and state.get("agent_token"):
        return state
    if not SERVER or not INSTALL_TOKEN:
        raise RuntimeError("missing SUB_BOX_SERVER or SUB_BOX_INSTALL_TOKEN")
    payload = {
        "hostname": socket.gethostname(),
        "public_ip": request_public_ip(),
        "version": "2.1.0",
    }
    r = requests.post(
        f"{SERVER}/api/agents/enroll",
        headers={"X-Install-Token": INSTALL_TOKEN},
        json=payload,
        timeout=20,
    )
    r.raise_for_status()
    data = r.json()
    state = {
        "server": SERVER,
        "agent_id": data["agent_id"],
        "agent_token": data["agent_token"],
        "revision": 0,
        "last_enroll": now_iso(),
    }
    write_json(AGENT_STATE, state)
    return state


def get_config(state: dict[str, Any]) -> dict[str, Any]:
    r = requests.get(f"{SERVER}/api/agents/config", headers=headers(state), timeout=20)
    r.raise_for_status()
    return r.json().get("desired", {})


def singbox_inbound(desired: dict[str, Any]) -> dict[str, Any]:
    protocol = desired.get("protocol", "trojan")
    port = int(desired.get("port", 443))
    secret = desired.get("secret", "")
    domain = desired.get("domain") or socket.getfqdn()
    if protocol == "trojan":
        return {
            "type": "trojan",
            "tag": "agent-in",
            "listen": "::",
            "listen_port": port,
            "users": [{"password": secret}],
        }
    if protocol == "vmess":
        return {
            "type": "vmess",
            "tag": "agent-in",
            "listen": "::",
            "listen_port": port,
            "users": [{"uuid": secret, "alterId": 0}],
        }
    if protocol == "hysteria2":
        return {
            "type": "hysteria2",
            "tag": "agent-in",
            "listen": "::",
            "listen_port": port,
            "users": [{"password": secret}],
        }
    if protocol == "vless":
        return {
            "type": "vless",
            "tag": "agent-in",
            "listen": "::",
            "listen_port": port,
            "users": [{"uuid": secret}],
        }
    raise RuntimeError(f"unsupported protocol: {protocol}")


def apply_config(desired: dict[str, Any]) -> tuple[bool, str]:
    if not desired.get("enabled", True):
        stop_sing_box()
        return True, ""
    config = {
        "log": {"level": "warn", "output": "/var/log/sing-box.log"},
        "inbounds": [singbox_inbound(desired)],
        "outbounds": [{"type": "direct", "tag": "direct"}],
    }
    SING_BOX_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    SING_BOX_CONFIG.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    if SING_BOX_BIN.exists():
        return restart_sing_box()
    return False, f"{SING_BOX_BIN} not found"


def has_systemd() -> bool:
    return Path("/run/systemd/system").exists()


def stop_sing_box() -> None:
    if has_systemd():
        run(["systemctl", "stop", "sing-box"], timeout=15)
        return
    run(["pkill", "-f", "/usr/local/bin/sing-box run -c /etc/sing-box/config.json"], timeout=5)


def restart_sing_box() -> tuple[bool, str]:
    if has_systemd():
        rc, _, err = run(["systemctl", "restart", "sing-box"], timeout=30)
        return rc == 0, err.strip()
    stop_sing_box()
    log = open("/tmp/sub-box-sing-box.log", "ab")
    subprocess.Popen(
        [str(SING_BOX_BIN), "run", "-c", str(SING_BOX_CONFIG)],
        stdout=log,
        stderr=log,
        start_new_session=True,
    )
    time.sleep(1)
    rc, _, _ = run(["pgrep", "-f", "/usr/local/bin/sing-box run -c /etc/sing-box/config.json"], timeout=5)
    if rc == 0:
        return True, ""
    tail = Path("/tmp/sub-box-sing-box.log")
    return False, tail.read_text(errors="ignore")[-1000:] if tail.exists() else "sing-box failed to start"


_last_cpu: tuple[int, int] | None = None
_last_net: tuple[float, int, int] | None = None


def cpu_percent() -> float:
    global _last_cpu
    first = Path("/proc/stat").read_text().splitlines()[0].split()[1:]
    vals = [int(x) for x in first]
    idle = vals[3] + vals[4]
    total = sum(vals)
    if _last_cpu is None:
        _last_cpu = (idle, total)
        return 0.0
    old_idle, old_total = _last_cpu
    _last_cpu = (idle, total)
    total_delta = total - old_total
    idle_delta = idle - old_idle
    if total_delta <= 0:
        return 0.0
    return round((1 - idle_delta / total_delta) * 100, 1)


def mem_metrics() -> dict[str, int]:
    data = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, val = line.split(":", 1)
        data[key] = int(val.strip().split()[0])
    total = data.get("MemTotal", 0) // 1024
    available = data.get("MemAvailable", 0) // 1024
    return {"mem_total_mb": total, "mem_used_mb": max(total - available, 0)}


def net_metrics() -> dict[str, int]:
    global _last_net
    rx = tx = 0
    for line in Path("/proc/net/dev").read_text().splitlines()[2:]:
        iface, rest = line.split(":", 1)
        iface = iface.strip()
        if iface == "lo":
            continue
        fields = rest.split()
        rx += int(fields[0])
        tx += int(fields[8])
    now = time.time()
    rx_bps = tx_bps = 0
    if _last_net is not None:
        old_now, old_rx, old_tx = _last_net
        elapsed = max(now - old_now, 1)
        rx_bps = int((rx - old_rx) / elapsed)
        tx_bps = int((tx - old_tx) / elapsed)
    _last_net = (now, rx, tx)
    return {"net_rx_bps": rx_bps, "net_tx_bps": tx_bps, "net_rx_total": rx, "net_tx_total": tx}


def disk_metrics() -> dict[str, str]:
    rc, out, _ = run(["df", "-h", "/"], timeout=5)
    if rc != 0:
        return {}
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 5:
            return {"disk_total": parts[1], "disk_used": parts[2], "disk_pct": parts[4]}
    return {}


def cert_metrics(domain: str) -> dict[str, Any]:
    if not domain:
        return {}
    for name in ["fullchain.pem", "tls.crt"]:
        cert = CERT_DIR / domain / name
        if cert.exists():
            rc, out, _ = run(["openssl", "x509", "-in", str(cert), "-noout", "-enddate"], timeout=5)
            if rc == 0 and "notAfter=" in out:
                raw = out.split("=", 1)[1].strip()
                try:
                    end = datetime.strptime(raw, "%b %d %H:%M:%S %Y %Z")
                    days = int((end - datetime.utcnow()).total_seconds() // 86400)
                    return {"cert_not_after": raw, "cert_days_left": days}
                except Exception:
                    return {"cert_not_after": raw}
    return {}


def service_metrics(desired: dict[str, Any]) -> dict[str, Any]:
    if has_systemd():
        rc, out, _ = run(["systemctl", "is-active", "sing-box"], timeout=5)
        singbox_running = rc == 0 and out.strip() == "active"
    else:
        rc, _, _ = run(["pgrep", "-f", "/usr/local/bin/sing-box run -c /etc/sing-box/config.json"], timeout=5)
        singbox_running = rc == 0
    services = {"singbox": "running" if singbox_running else "stopped"}
    rc, out, _ = run(["sing-box", "version"], timeout=5)
    if rc == 0:
        services["singbox_version"] = out.splitlines()[0] if out.splitlines() else ""
    services.update(cert_metrics(desired.get("domain", "")))
    return services


def collect_metrics() -> dict[str, Any]:
    metrics: dict[str, Any] = {"cpu_percent": cpu_percent()}
    metrics.update(mem_metrics())
    metrics.update(net_metrics())
    metrics.update(disk_metrics())
    return metrics


def report(state: dict[str, Any], desired: dict[str, Any], apply_ok: bool, apply_error: str) -> None:
    payload = {
        "revision": int(desired.get("revision", 0)),
        "apply_ok": apply_ok,
        "apply_error": apply_error,
        "metrics": collect_metrics(),
        "services": service_metrics(desired),
    }
    requests.post(f"{SERVER}/api/agents/report", headers=headers(state), json=payload, timeout=20).raise_for_status()


def main() -> None:
    state = enroll()
    while True:
        apply_ok = True
        apply_error = ""
        desired = {}
        try:
            desired = get_config(state)
            revision = int(desired.get("revision", 0))
            if revision and revision != int(state.get("revision", 0)):
                apply_ok, apply_error = apply_config(desired)
                if apply_ok:
                    state["revision"] = revision
                    write_json(AGENT_STATE, state)
            report(state, desired, apply_ok, apply_error)
        except Exception as exc:
            apply_ok = False
            apply_error = str(exc)
            print(f"[ERR] {apply_error}", flush=True)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
