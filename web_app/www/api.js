// ─── API client ────────────────────────────────────────────────────
// Wraps fetch() with Bearer auth + defensive JSON parsing.
// Every method here maps 1:1 to a FastAPI endpoint in backend/main.py.

class ApiClient {
  // Store base URL (trim trailing slash) + API key for all future requests
  constructor(baseUrl, apiKey) {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.apiKey = apiKey;
  }

  // Send Request – internal helper: adds Bearer header, JSON body,
  // 10s timeout. Throws Error with backend's detail message on failure.
  async _req(path, opts = {}) {
    const url = this.baseUrl + path;
    const headers = {
      'Authorization': 'Bearer ' + this.apiKey,
      'Accept': 'application/json',
      ...(opts.headers || {}),
    };
    if (opts.body && typeof opts.body !== 'string') {
      headers['Content-Type'] = 'application/json';
      opts.body = JSON.stringify(opts.body);
    }
    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), opts.timeout || 10000);
    try {
      const r = await fetch(url, { ...opts, headers, signal: ctrl.signal });
      clearTimeout(tid);
      if (!r.ok) {
        let msg = `${r.status} ${r.statusText || ''}`.trim();
        try { const j = await r.json(); if (j.detail) msg = j.detail; } catch {}
        throw new Error(msg);
      }
      const ct = r.headers.get('content-type') || '';
      return ct.includes('json') ? await r.json() : await r.text();
    } catch (e) {
      clearTimeout(tid);
      if (e.name === 'AbortError') throw new Error(`Timeout: ${path}`);
      // Network errors give "Failed to fetch" with no detail — add the path for debugging
      if (e.message === 'Failed to fetch' || e.message === 'Network request failed') {
        throw new Error(`Network error reaching ${path} (server unreachable or CORS/HTTPS issue)`);
      }
      throw e;
    }
  }

  // ── Health & overview ──────────────────────────────────────────
  health()        { return this._req('/api/health'); }              // Ping backend (returns {status:"ok"})
  overview()      { return this._req('/api/system/overview'); }     // Get hostname, uptime, CPU/RAM/disk totals

  // ── Stats (top N) ──────────────────────────────────────────────
  topCpu(limit=5)        { return this._req(`/api/stats/top-cpu?limit=${limit}`); }      // Get top N CPU-hungry processes
  topRam(limit=5)        { return this._req(`/api/stats/top-ram?limit=${limit}`); }      // Get top N RAM-hungry processes
  topNetwork(limit=5)    { return this._req(`/api/stats/top-network?limit=${limit}`); }  // Get top N network-active processes
  topDisk(path='/home', limit=5) {                                                       // Get largest folders inside `path`
    return this._req(`/api/stats/top-disk-folders?path=${encodeURIComponent(path)}&limit=${limit}`);
  }

  // ── Processes ──────────────────────────────────────────────────
  processes(offset=0, limit=20, sortBy='cpu') {                                          // Get paged process list (sortable)
    return this._req(`/api/processes/list?offset=${offset}&limit=${limit}&sort_by=${sortBy}`);
  }
  kill(pid, signal=15) {                                                                 // Kill process by PID (SIGTERM default)
    return this._req('/api/processes/kill', { method:'POST', body:{ pid, signal }});
  }

  // ── Disk (file manager) ────────────────────────────────────────
  diskList(path) {                                                                       // List contents of a folder
    return this._req(`/api/disk/list?path=${encodeURIComponent(path)}`);
  }
  mkdir(path) {                                                                          // Create new folder
    return this._req('/api/disk/mkdir', { method:'POST', body:{ path }});
  }
  rm(path, recursive=false) {                                                            // Delete file or folder
    return this._req('/api/disk/delete', { method:'DELETE', body:{ path, recursive }});
  }
  readFile(path) {                                                                       // Read text file (up to 2 MB)
    return this._req(`/api/disk/read?path=${encodeURIComponent(path)}`);
  }
  writeFile(path, content) {                                                             // Overwrite text file content
    return this._req('/api/disk/write', { method:'POST', body:{ path, content }});
  }

  // ── Network ────────────────────────────────────────────────────
  netStats()  { return this._req('/api/network/stats'); }                                // Get per-interface bytes/packets
  netBanned() { return this._req('/api/network/banned'); }                               // Get list of iptables-banned IPs
  ban(ip, reason='') {                                                                   // Ban IP via iptables (DROP rule)
    return this._req('/api/network/ban', { method:'POST', body:{ ip, reason }});
  }
  unban(ip) {                                                                            // Remove iptables ban for IP
    return this._req('/api/network/unban', { method:'POST', body:{ ip }});
  }

  // ── Docker ─────────────────────────────────────────────────────
  containers() { return this._req('/api/docker/containers'); }                           // List all Docker containers
  containerAction(id, action) {                                                          // start / stop / restart
    return this._req('/api/docker/action', { method:'POST', body:{ container_id:id, action }});
  }
  containerLogs(id, lines=100) {                                                         // Fetch last N log lines
    return this._req(`/api/docker/containers/${id}/logs?lines=${lines}`);
  }

  // ── Terminal ───────────────────────────────────────────────────
  exec(command, timeout=30) {                                                            // Run whitelisted shell command
    return this._req('/api/terminal/exec', { method:'POST', body:{ command, timeout }});
  }
}

window.ApiClient = ApiClient;
