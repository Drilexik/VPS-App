import os
import re
import time
import shlex
import subprocess
from typing import Optional

import psutil
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, validator
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

load_dotenv()

API_KEY = os.getenv("DRILEX_API_KEY", "")

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Drilex VPS Manager", docs_url=None, redoc_url=None)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

security = HTTPBearer()

PROTECTED_PIDS = {1, 2}
PROTECTED_NAMES = {"systemd", "sshd", "uvicorn", "init", "kthreadd", "kworker"}
WHITELISTED_PATHS = {"/home", "/var", "/opt", "/srv", "/tmp/drilex"}
WHITELISTED_IPS = {"127.0.0.1", "::1"}

ALLOWED_COMMANDS = {
    "ps", "top", "df", "du", "ls", "cat", "grep", "docker",
    "systemctl", "free", "uptime", "netstat", "ss", "ip",
    "iostat", "vmstat", "who", "w", "last", "journalctl",
    "lsof", "tail", "head", "wc", "sort", "uniq", "awk",
    "find", "ping", "traceroute", "curl", "wget", "nmap",
    "htop", "iotop", "iftop", "hostname", "uname", "date",
    "env", "printenv", "echo", "stat",
}

DANGEROUS_PATTERNS = [
    r"rm\s+-[rRf]{1,3}\s*/",
    r"dd\s+.*of=/dev",
    r"\bshutdown\b",
    r"\breboot\b",
    r"\bhalt\b",
    r"\bpoweroff\b",
    r"\bpasswd\b",
    r"iptables\s+-F",
    r">\s*/dev/sd[a-z]",
    r"mkfs\.",
    r"\bfdisk\b",
    r"\bparted\b",
    r">\s*/etc/",
    r"chmod\s+[0-7]{3,4}\s+/",
    r"chown\s+\S+\s+/[^h]",
    r"kill\s+-9\s+1\b",
    r"--no-preserve-root",
    r"mv\s+/\s+",
    r"\bformat\b",
    r"\bwipefs\b",
]

IPv4_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"
)

VALID_SIGNALS = {1, 2, 3, 9, 15}
VALID_DOCKER_ACTIONS = {"start", "stop", "restart", "pause", "unpause", "remove"}


# ── Auth ─────────────────────────────────────────────────────────────────────

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)) -> str:
    if not API_KEY:
        raise HTTPException(500, "API key not configured on server")
    if creds.credentials != API_KEY:
        raise HTTPException(401, "Invalid API key")
    return creds.credentials


# ── Helpers ───────────────────────────────────────────────────────────────────

def is_whitelisted(path: str) -> bool:
    p = os.path.normpath(path)
    return any(p == wp or p.startswith(wp + "/") for wp in WHITELISTED_PATHS)


def process_killable(proc: psutil.Process) -> bool:
    try:
        return proc.pid not in PROTECTED_PIDS and proc.name() not in PROTECTED_NAMES
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        return False


def cpu_model() -> str:
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if "model name" in line:
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return "Unknown CPU"


def fmt_bytes(b: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(b) < 1024:
            return f"{b:.1f} {unit}"
        b /= 1024
    return f"{b:.1f} PB"


# ── Pydantic models ───────────────────────────────────────────────────────────

class KillRequest(BaseModel):
    pid: int
    signal: int = 15

    @validator("signal")
    def valid_sig(cls, v):
        if v not in VALID_SIGNALS:
            raise ValueError(f"Signal must be one of {VALID_SIGNALS}")
        return v


class MkdirRequest(BaseModel):
    path: str


class DeleteRequest(BaseModel):
    path: str
    recursive: bool = False


class BanRequest(BaseModel):
    ip: str
    reason: str = ""


class UnbanRequest(BaseModel):
    ip: str


class DockerActionRequest(BaseModel):
    container_id: str
    action: str

    @validator("action")
    def valid_action(cls, v):
        if v not in VALID_DOCKER_ACTIONS:
            raise ValueError(f"Action must be one of {VALID_DOCKER_ACTIONS}")
        return v


class TerminalRequest(BaseModel):
    command: str
    timeout: int = 30

    @validator("timeout")
    def cap_timeout(cls, v):
        return min(max(v, 1), 30)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    return {"status": "ok", "timestamp": int(time.time())}


@app.get("/api/system/overview")
@limiter.limit("60/minute")
async def system_overview(request: Request, _: str = Depends(verify_token)):
    cpu_temp = None
    try:
        temps = psutil.sensors_temperatures()
        if temps:
            for entries in temps.values():
                if entries:
                    cpu_temp = round(entries[0].current, 1)
                    break
    except Exception:
        pass

    freq = psutil.cpu_freq()
    ram = psutil.virtual_memory()
    swap = psutil.swap_memory()
    disk = psutil.disk_usage("/")
    net = psutil.net_io_counters()

    import platform
    return {
        "cpu": {
            "model": cpu_model(),
            "cores": psutil.cpu_count(logical=False) or 1,
            "logical_cores": psutil.cpu_count(logical=True) or 1,
            "usage_percent": psutil.cpu_percent(interval=0.5),
            "per_core": psutil.cpu_percent(interval=None, percpu=True),
            "frequency_mhz": round(freq.current, 1) if freq else None,
            "temperature": cpu_temp,
        },
        "ram": {
            "total": ram.total,
            "used": ram.used,
            "free": ram.available,
            "percent": ram.percent,
            "swap_total": swap.total,
            "swap_used": swap.used,
            "swap_free": swap.free,
            "swap_percent": swap.percent,
        },
        "disk": {
            "total": disk.total,
            "used": disk.used,
            "free": disk.free,
            "percent": disk.percent,
        },
        "network": {
            "bytes_sent": net.bytes_sent,
            "bytes_recv": net.bytes_recv,
        },
        "hostname": platform.node(),
        "os": f"{platform.system()} {platform.release()}",
        "uptime_seconds": int(time.time() - psutil.boot_time()),
    }


def _process_list():
    procs = []
    for p in psutil.process_iter(
        ["pid", "name", "cpu_percent", "memory_info", "status", "cmdline"]
    ):
        try:
            ram = p.info["memory_info"]
            procs.append(
                {
                    "pid": p.info["pid"],
                    "name": p.info["name"] or "",
                    "cpu_percent": p.info["cpu_percent"] or 0.0,
                    "ram_mb": round((ram.rss if ram else 0) / 1_048_576, 2),
                    "status": p.info["status"] or "",
                    "killable": process_killable(p),
                    "cmdline": p.info.get("cmdline") or [],
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return procs


@app.get("/api/stats/top-cpu")
@limiter.limit("60/minute")
async def top_cpu(request: Request, limit: int = 5, _: str = Depends(verify_token)):
    procs = sorted(_process_list(), key=lambda x: x["cpu_percent"], reverse=True)
    return [{"pid": p["pid"], "name": p["name"], "cpu_percent": p["cpu_percent"], "ram_mb": p["ram_mb"], "status": p["status"]} for p in procs[:limit]]


@app.get("/api/stats/top-ram")
@limiter.limit("60/minute")
async def top_ram(request: Request, limit: int = 5, _: str = Depends(verify_token)):
    procs = sorted(_process_list(), key=lambda x: x["ram_mb"], reverse=True)
    return [{"pid": p["pid"], "name": p["name"], "cpu_percent": p["cpu_percent"], "ram_mb": p["ram_mb"], "status": p["status"]} for p in procs[:limit]]


@app.get("/api/stats/top-network")
@limiter.limit("60/minute")
async def top_network(request: Request, limit: int = 5, _: str = Depends(verify_token)):
    procs = []
    for p in psutil.process_iter(["pid", "name"]):
        try:
            conns = len(p.net_connections())
            if conns:
                procs.append({"pid": p.pid, "name": p.name(), "connections": conns})
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    return sorted(procs, key=lambda x: x["connections"], reverse=True)[:limit]


@app.get("/api/stats/top-disk-folders")
@limiter.limit("10/minute")
async def top_disk_folders(
    request: Request,
    path: str = "/home",
    limit: int = 5,
    _: str = Depends(verify_token),
):
    path = os.path.normpath(path)
    if not is_whitelisted(path):
        raise HTTPException(403, "Path not in whitelist")
    try:
        result = subprocess.run(
            ["du", "-sb", "--max-depth=1", path],
            capture_output=True, text=True, timeout=30,
        )
        folders = []
        for line in result.stdout.strip().splitlines():
            if "\t" in line:
                size_str, folder = line.split("\t", 1)
                if folder.rstrip("/") != path.rstrip("/"):
                    folders.append({"path": folder, "size": int(size_str)})
        return sorted(folders, key=lambda x: x["size"], reverse=True)[:limit]
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/processes/list")
@limiter.limit("60/minute")
async def processes_list(
    request: Request,
    offset: int = 0,
    limit: int = 15,
    sort_by: str = "cpu",
    _: str = Depends(verify_token),
):
    procs = _process_list()
    sort_map = {
        "cpu": lambda x: x["cpu_percent"],
        "ram": lambda x: x["ram_mb"],
        "name": lambda x: x["name"].lower(),
    }
    key = sort_map.get(sort_by, sort_map["cpu"])
    procs.sort(key=key, reverse=(sort_by != "name"))

    result = []
    for p in procs[offset: offset + limit]:
        cmd = " ".join(p["cmdline"]) if p["cmdline"] else p["name"]
        result.append(
            {
                "pid": p["pid"],
                "name": p["name"],
                "cpu_percent": p["cpu_percent"],
                "ram_mb": p["ram_mb"],
                "status": p["status"],
                "command": cmd[:120],
                "killable": p["killable"],
            }
        )
    return {"total": len(procs), "offset": offset, "limit": limit, "processes": result}


@app.post("/api/processes/kill")
@limiter.limit("20/minute")
async def kill_process(request: Request, body: KillRequest, _: str = Depends(verify_token)):
    if body.pid in PROTECTED_PIDS:
        raise HTTPException(403, "Cannot kill protected process")
    try:
        proc = psutil.Process(body.pid)
        if proc.name() in PROTECTED_NAMES:
            raise HTTPException(403, "Cannot kill protected process")
        proc.send_signal(body.signal)
        return {"success": True, "pid": body.pid}
    except psutil.NoSuchProcess:
        raise HTTPException(404, "Process not found")
    except psutil.AccessDenied:
        raise HTTPException(403, "Access denied")
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/disk/list")
@limiter.limit("60/minute")
async def disk_list(request: Request, path: str = "/home", _: str = Depends(verify_token)):
    path = os.path.normpath(path)
    if not is_whitelisted(path):
        raise HTTPException(403, "Path not in whitelist")
    try:
        entries = []
        for entry in os.scandir(path):
            try:
                st = entry.stat(follow_symlinks=False)
                entries.append(
                    {
                        "name": entry.name,
                        "path": entry.path,
                        "is_dir": entry.is_dir(),
                        "size": st.st_size if not entry.is_dir() else 0,
                        "modified": st.st_mtime,
                    }
                )
            except PermissionError:
                pass
        entries.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
        return {"path": path, "entries": entries}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.post("/api/disk/mkdir")
@limiter.limit("20/minute")
async def disk_mkdir(request: Request, body: MkdirRequest, _: str = Depends(verify_token)):
    path = os.path.normpath(body.path)
    if not is_whitelisted(path):
        raise HTTPException(403, "Path not in whitelist")
    try:
        os.makedirs(path, exist_ok=True)
        return {"success": True, "path": path}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.delete("/api/disk/delete")
@limiter.limit("20/minute")
async def disk_delete(request: Request, body: DeleteRequest, _: str = Depends(verify_token)):
    import shutil

    path = os.path.normpath(body.path)
    if not is_whitelisted(path):
        raise HTTPException(403, "Path not in whitelist")
    if path in WHITELISTED_PATHS:
        raise HTTPException(403, "Cannot delete a whitelisted root path")
    try:
        if os.path.isdir(path):
            if body.recursive:
                shutil.rmtree(path)
            else:
                os.rmdir(path)
        else:
            os.remove(path)
        return {"success": True}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/network/stats")
@limiter.limit("60/minute")
async def network_stats(request: Request, _: str = Depends(verify_token)):
    stats = psutil.net_io_counters(pernic=True)
    return {
        iface: {
            "bytes_sent": d.bytes_sent,
            "bytes_recv": d.bytes_recv,
            "packets_sent": d.packets_sent,
            "packets_recv": d.packets_recv,
            "errin": d.errin,
            "errout": d.errout,
        }
        for iface, d in stats.items()
    }


@app.get("/api/network/banned")
@limiter.limit("30/minute")
async def network_banned(request: Request, _: str = Depends(verify_token)):
    try:
        r = subprocess.run(
            ["iptables", "-L", "INPUT", "-n", "--line-numbers"],
            capture_output=True, text=True, timeout=10,
        )
        banned = []
        for line in r.stdout.splitlines():
            if "DROP" in line:
                m = IPv4_RE.search(line)
                if m:
                    banned.append({"ip": m.group()})
        return {"banned": banned}
    except FileNotFoundError:
        return {"banned": [], "warning": "iptables not available"}
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.post("/api/network/ban")
@limiter.limit("20/minute")
async def network_ban(request: Request, body: BanRequest, _: str = Depends(verify_token)):
    if not IPv4_RE.match(body.ip):
        raise HTTPException(400, "Invalid IPv4 address")
    if body.ip in WHITELISTED_IPS:
        raise HTTPException(403, "Cannot ban whitelisted IP")
    try:
        subprocess.run(
            ["iptables", "-I", "INPUT", "-s", body.ip, "-j", "DROP"],
            capture_output=True, text=True, timeout=10, check=True,
        )
        return {"success": True, "ip": body.ip}
    except subprocess.CalledProcessError as exc:
        raise HTTPException(500, exc.stderr or "iptables error")


@app.post("/api/network/unban")
@limiter.limit("20/minute")
async def network_unban(request: Request, body: UnbanRequest, _: str = Depends(verify_token)):
    if not IPv4_RE.match(body.ip):
        raise HTTPException(400, "Invalid IPv4 address")
    try:
        subprocess.run(
            ["iptables", "-D", "INPUT", "-s", body.ip, "-j", "DROP"],
            capture_output=True, text=True, timeout=10, check=True,
        )
        return {"success": True, "ip": body.ip}
    except subprocess.CalledProcessError as exc:
        raise HTTPException(500, exc.stderr or "iptables error")


@app.get("/api/docker/containers")
@limiter.limit("30/minute")
async def docker_containers(request: Request, _: str = Depends(verify_token)):
    try:
        import docker as docker_sdk

        client = docker_sdk.from_env()
        result = []
        for c in client.containers.list(all=True):
            cpu_pct = 0.0
            ram_mb = 0.0
            if c.status == "running":
                try:
                    s = c.stats(stream=False)
                    cpu_delta = (
                        s["cpu_stats"]["cpu_usage"]["total_usage"]
                        - s["precpu_stats"]["cpu_usage"]["total_usage"]
                    )
                    sys_delta = s["cpu_stats"].get(
                        "system_cpu_usage", 0
                    ) - s["precpu_stats"].get("system_cpu_usage", 0)
                    n_cpu = s["cpu_stats"].get("online_cpus", 1)
                    if sys_delta > 0:
                        cpu_pct = (cpu_delta / sys_delta) * n_cpu * 100.0
                    ram_mb = s["memory_stats"].get("usage", 0) / 1_048_576
                except Exception:
                    pass
            result.append(
                {
                    "id": c.id[:12],
                    "name": c.name,
                    "image": (c.image.tags or [c.image.id[:12]])[0],
                    "status": c.status,
                    "cpu_percent": round(cpu_pct, 2),
                    "ram_mb": round(ram_mb, 2),
                }
            )
        return {"containers": result}
    except ImportError:
        raise HTTPException(503, "Docker SDK not installed")
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.post("/api/docker/action")
@limiter.limit("20/minute")
async def docker_action(
    request: Request, body: DockerActionRequest, _: str = Depends(verify_token)
):
    try:
        import docker as docker_sdk

        client = docker_sdk.from_env()
        container = client.containers.get(body.container_id)
        if body.action == "remove":
            container.remove(force=True)
        else:
            getattr(container, body.action)()
        return {"success": True}
    except ImportError:
        raise HTTPException(503, "Docker SDK not installed")
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.get("/api/docker/containers/{container_id}/logs")
@limiter.limit("20/minute")
async def docker_logs(
    request: Request,
    container_id: str,
    lines: int = 50,
    _: str = Depends(verify_token),
):
    try:
        import docker as docker_sdk

        client = docker_sdk.from_env()
        container = client.containers.get(container_id)
        raw = container.logs(tail=lines, timestamps=True)
        return {"logs": raw.decode("utf-8", errors="replace")}
    except ImportError:
        raise HTTPException(503, "Docker SDK not installed")
    except Exception as exc:
        raise HTTPException(500, str(exc))


@app.post("/api/terminal/exec")
@limiter.limit("20/minute")
async def terminal_exec(
    request: Request, body: TerminalRequest, _: str = Depends(verify_token)
):
    cmd = body.command.strip()
    if not cmd:
        raise HTTPException(400, "Empty command")

    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, cmd, re.IGNORECASE):
            raise HTTPException(403, "Command pattern not allowed")

    try:
        parts = shlex.split(cmd)
    except ValueError as exc:
        raise HTTPException(400, f"Parse error: {exc}")

    base = os.path.basename(parts[0])
    if base not in ALLOWED_COMMANDS:
        raise HTTPException(403, f"Command '{base}' not in allowlist")

    try:
        r = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            timeout=body.timeout,
        )
        return {
            "stdout": r.stdout,
            "stderr": r.stderr,
            "returncode": r.returncode,
        }
    except subprocess.TimeoutExpired:
        raise HTTPException(408, "Command timed out")
    except Exception as exc:
        raise HTTPException(500, str(exc))
