// ─── MonitorService – SSE stream + notification dispatch ─────────────
// Reuses the same /api/events/stream endpoint already on the backend.
// Two event kinds arrive over the stream:
//   "stats" → live CPU/RAM/Disk values (every 5s) → drives dashboard gauges
//   "alert" → threshold breaches (CPU>80%, RAM>80%, Disk>90%, SSH login)

class MonitorService {
  // Initialize empty state (no connection until configure() + start())
  constructor() {
    this.es = null;
    this.url = null;
    this.key = null;
    this.connected = false;
    this.lastAlertAt = {};  // dedupe per-kind: { cpu: ts, ram: ts, ... }
    this.cooldownMs = 5 * 60 * 1000;  // 5 minutes
    this._listeners = { stats: [], alert: [], state: [] };

    // Latest values for UI
    this.cpuPercent = 0;
    this.ramPercent = 0;
    this.diskPercent = 0;
  }

  // Save credentials (called once after login)
  configure(url, apiKey) {
    this.url = url.replace(/\/$/, '');
    this.key = apiKey;
  }

  // Subscribe to "stats", "alert", or "state" events. Returns unsubscribe fn.
  on(event, fn) {
    if (!this._listeners[event]) this._listeners[event] = [];
    this._listeners[event].push(fn);
    return () => {
      this._listeners[event] = this._listeners[event].filter(f => f !== fn);
    };
  }
  // Dispatch event to all subscribers (try/catch so one bad listener can't break others)
  _emit(event, data) {
    (this._listeners[event] || []).forEach(fn => { try { fn(data); } catch (e) { console.error(e); } });
  }

  // Open SSE connection (called when app foregrounds)
  start() {
    if (this.es || !this.url) return;
    // Use fetch+ReadableStream instead of EventSource so we can pass Bearer header
    this._connectStream();
  }

  // Close SSE connection (called when app backgrounds, saves battery)
  stop() {
    if (this._abort) { this._abort.abort(); this._abort = null; }
    this._setConnected(false);
  }

  // Update connection status + notify UI ("LIVE" badge color)
  _setConnected(c) {
    if (this.connected !== c) {
      this.connected = c;
      this._emit('state', c);
    }
  }

  // Open SSE stream, read events line-by-line, auto-reconnect on disconnect
  async _connectStream() {
    // Use fetch + reader so we can pass the Authorization header
    try {
      const ctrl = new AbortController();
      this._abort = ctrl;
      const resp = await fetch(this.url + '/api/events/stream', {
        headers: { 'Authorization': 'Bearer ' + this.key, 'Accept': 'text/event-stream' },
        signal: ctrl.signal,
      });
      if (!resp.ok || !resp.body) throw new Error('Stream failed: ' + resp.status);

      this._setConnected(true);
      const reader = resp.body.getReader();
      const decoder = new TextDecoder();
      let buf = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        let i;
        while ((i = buf.indexOf('\n\n')) >= 0) {
          const raw = buf.slice(0, i);
          buf = buf.slice(i + 2);
          this._parseEvent(raw);
        }
      }
    } catch (e) {
      if (e.name !== 'AbortError') console.warn('SSE error:', e.message);
    } finally {
      this._setConnected(false);
      this._abort = null;
      // Auto-reconnect in 12 seconds
      if (this.url && this.key) {
        setTimeout(() => { if (!this.es && !this._abort) this._connectStream(); }, 12000);
      }
    }
  }

  // Parse one SSE chunk → route by data.type (backend sends only "data:" lines,
  // event kind is encoded in the JSON payload as `type`: stats/alert/heartbeat).
  _parseEvent(raw) {
    let dataStr = '';
    for (const line of raw.split('\n')) {
      if (line.startsWith('data:')) dataStr += line.slice(5).trim();
    }
    if (!dataStr) return;
    let data;
    try { data = JSON.parse(dataStr); } catch { return; }

    const kind = data.type || 'stats';
    if (kind === 'stats') {
      // Cache latest values + broadcast to UI subscribers
      this.cpuPercent  = Number(data.cpu)  || 0;
      this.ramPercent  = Number(data.ram)  || 0;
      this.diskPercent = Number(data.disk) || 0;
      this._emit('stats', data);
    } else if (kind === 'alert') {
      this._handleAlert(data);
    }
    // heartbeat → ignore (keepalive only)
  }

  // Dedupe alerts per kind (5min cooldown) + fire notification
  _handleAlert(data) {
    const kind = data.kind || 'info';
    const now = Date.now();
    const last = this.lastAlertAt[kind] || 0;
    if (now - last < this.cooldownMs) return;   // Too soon since last alert of this kind → skip
    this.lastAlertAt[kind] = now;
    this._emit('alert', data);
    notify.show({
      kind,
      title: data.title || 'Drilex VPS',
      body:  data.message || '',
    });
  }

  // One-shot health check (used by background runner for heartbeat)
  async checkOnce() {
    try {
      const r = await fetch(this.url + '/api/health', {
        headers: { 'Authorization': 'Bearer ' + this.key },
        signal: AbortSignal.timeout ? AbortSignal.timeout(10000) : undefined,
      });
      return r.ok;
    } catch { return false; }
  }
}

// ─── NotificationService ──────────────────────────────────────────
// Wraps Capacitor LocalNotifications, falls back to in-app toasts on web.

const notify = {
  available: false,
  _lastForegroundAt: Date.now(),
  _toastStack: null,

  // Request notification permission + create Android channel (called at app boot)
  async init() {
    this._toastStack = document.getElementById('toast-stack');
    if (window.Capacitor && Capacitor.isNativePlatform && Capacitor.isNativePlatform()) {
      try {
        const LN = Capacitor.Plugins.LocalNotifications;
        if (LN) {
          await LN.requestPermissions();
          await LN.createChannel({
            id: 'drilex-default',
            name: 'Drilex VPS Alerts',
            importance: 4,
            visibility: 1,
            sound: 'default',
          });
          this.available = true;
        }
      } catch (e) { console.warn('Notifications init failed:', e); }
    }
  },

  // Mark app as foreground-active (resets heartbeat anti-spam timer)
  markForeground() {
    this._lastForegroundAt = Date.now();
  },

  // Returns true only if app was backgrounded for >5min (prevents phone-off spam)
  shouldHeartbeat() {
    return (Date.now() - this._lastForegroundAt) > 5 * 60 * 1000;
  },

  // Send notification – in-app toast always + native push when backgrounded
  async show({ kind, title, body }) {
    // Always show in-app toast
    this._toast(kind, title, body);

    // Native notification (when in background)
    if (this.available && document.visibilityState === 'hidden') {
      try {
        const LN = Capacitor.Plugins.LocalNotifications;
        await LN.schedule({
          notifications: [{
            id: Math.floor(Math.random() * 1e9),
            title, body,
            channelId: 'drilex-default',
            smallIcon: 'ic_stat_icon',
          }]
        });
      } catch (e) { console.warn('notify failed:', e); }
    }
  },

  // Render in-app toast (auto-disappears after 5s, color-coded by alert kind)
  _toast(kind, title, body) {
    if (!this._toastStack) return;
    const el = document.createElement('div');
    el.className = `toast ${kind || 'info'}`;
    el.innerHTML = `
      <div style="flex:1; min-width:0">
        <div style="font-weight:600; font-size:13px">${escapeHtml(title)}</div>
        <div style="color: var(--text-dim); font-size:12px; margin-top:2px">${escapeHtml(body)}</div>
      </div>`;
    this._toastStack.appendChild(el);
    setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity .3s'; }, 5000);
    setTimeout(() => el.remove(), 5400);
  },
};

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

window.MonitorService = MonitorService;
window.notify = notify;
