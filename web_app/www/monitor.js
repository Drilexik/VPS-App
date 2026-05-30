// ─── MonitorService – SSE stream + polling fallback ───────────────
// Strategy:
//   1. Open EventSource (?token=...) — works in Capacitor WebView
//   2. If EventSource fails OR no data within 6s → switch to polling
//   3. Polling: GET /api/system/overview every 5s
//
// This way the LIVE badge + dashboard gauges always update, even when
// SSE is blocked (mobile networks, nginx misconfig, etc.).

class MonitorService {
  constructor() {
    this.es = null;
    this.url = null;
    this.key = null;
    this.connected = false;
    this.mode = 'idle';          // 'sse' | 'poll' | 'idle'
    this.pollTimer = null;
    this.fallbackTimer = null;
    this.lastAlertAt = {};
    this.cooldownMs = 5 * 60 * 1000;
    this._listeners = { stats: [], alert: [], state: [] };

    this.cpuPercent = 0;
    this.ramPercent = 0;
    this.diskPercent = 0;

    // Heartbeat-lost detection (edge-triggered: fires once on loss, reset on next event)
    this.lastEventAt = 0;
    this.heartbeatLostNotified = false;
    this.heartbeatTimeoutMs = 30 * 1000;   // 30s without any SSE/poll event = "lost"
    this.heartbeatCheckTimer = null;
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
  _emit(event, data) {
    (this._listeners[event] || []).forEach(fn => { try { fn(data); } catch (e) { console.error(e); } });
  }
  _setConnected(c) {
    if (this.connected !== c) {
      this.connected = c;
      this._emit('state', c);
    }
  }

  // Start monitor — try SSE, schedule poll fallback + heartbeat checker
  start() {
    if (this.mode !== 'idle' || !this.url) return;
    this.lastEventAt = Date.now();   // reset so we don't immediately alert
    this.heartbeatLostNotified = false;
    this._connectSSE();
    // Polling fallback if SSE doesn't deliver first stats within 6s
    this.fallbackTimer = setTimeout(() => {
      if (this.mode !== 'sse-ok') this._switchToPoll();
    }, 6000);
    // Periodic heartbeat-lost check (every 5s)
    this.heartbeatCheckTimer = setInterval(() => this._checkHeartbeat(), 5000);
  }

  stop() {
    if (this.es) { this.es.close(); this.es = null; }
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
    if (this.fallbackTimer) { clearTimeout(this.fallbackTimer); this.fallbackTimer = null; }
    if (this.heartbeatCheckTimer) { clearInterval(this.heartbeatCheckTimer); this.heartbeatCheckTimer = null; }
    this.mode = 'idle';
    this._setConnected(false);
  }

  // Record any successful interaction (SSE event or poll response).
  // Resets heartbeatLostNotified so a future loss fires the notification again.
  _markActivity() {
    this.lastEventAt = Date.now();
    if (this.heartbeatLostNotified) {
      this.heartbeatLostNotified = false;   // edge-triggered reset (silent, no toast)
    }
  }

  // Periodic check: if no event for >timeout, fire heartbeat-lost notification ONCE.
  // Will not re-fire until _markActivity() is called (i.e. connection restored).
  _checkHeartbeat() {
    if (this.mode === 'idle' || this.lastEventAt === 0) return;
    const elapsed = Date.now() - this.lastEventAt;
    if (elapsed > this.heartbeatTimeoutMs && !this.heartbeatLostNotified) {
      this.heartbeatLostNotified = true;
      const seconds = Math.floor(elapsed / 1000);
      notify.show({
        kind: 'heartbeat',
        title: 'Drilex VPS',
        body: `Spojení ztraceno (${seconds}s bez odezvy)`,
      });
      this._emit('alert', { kind: 'heartbeat', message: 'Heartbeat lost' });
    }
  }

  // Open EventSource (token in URL — EventSource can't set custom headers)
  _connectSSE() {
    try {
      const url = `${this.url}/api/events/stream?token=${encodeURIComponent(this.key)}`;
      const es = new EventSource(url);
      this.es = es;
      this.mode = 'sse';

      es.onmessage = (ev) => {
        this._markActivity();
        if (this.mode !== 'sse-ok') {
          this.mode = 'sse-ok';
          if (this.fallbackTimer) { clearTimeout(this.fallbackTimer); this.fallbackTimer = null; }
        }
        this._setConnected(true);
        let data;
        try { data = JSON.parse(ev.data); } catch { return; }
        this._handlePayload(data);
      };

      es.onerror = () => {
        // EventSource auto-reconnects internally. If it doesn't, fall back to poll after 6s.
        this._setConnected(false);
        if (this.mode !== 'sse-ok' && !this.fallbackTimer) {
          this.fallbackTimer = setTimeout(() => this._switchToPoll(), 6000);
        }
      };
    } catch (e) {
      console.warn('EventSource not available:', e);
      this._switchToPoll();
    }
  }

  // Polling fallback — calls /api/system/overview every 5s
  _switchToPoll() {
    if (this.es) { this.es.close(); this.es = null; }
    if (this.pollTimer) return;
    this.mode = 'poll';
    console.log('[monitor] Switching to polling mode');

    const poll = async () => {
      try {
        const r = await fetch(`${this.url}/api/system/overview`, {
          headers: { 'Authorization': 'Bearer ' + this.key },
        });
        if (!r.ok) throw new Error('HTTP ' + r.status);
        const ov = await r.json();
        const cpu  = Number(ov.cpu?.usage_percent) || 0;
        const ram  = Number(ov.ram?.percent)       || 0;
        const disk = Number(ov.disk?.percent)      || 0;
        this.cpuPercent = cpu; this.ramPercent = ram; this.diskPercent = disk;
        this._markActivity();
        this._setConnected(true);
        this._emit('stats', { cpu, ram, disk, timestamp: Date.now() / 1000 });
      } catch (e) {
        this._setConnected(false);
        // Heartbeat checker will fire alert once if poll keeps failing >30s
      }
    };
    poll();
    this.pollTimer = setInterval(poll, 5000);
  }

  // Route SSE payload by type (stats/alert/heartbeat)
  _handlePayload(data) {
    const kind = data.type || 'stats';
    if (kind === 'stats') {
      this.cpuPercent  = Number(data.cpu)  || 0;
      this.ramPercent  = Number(data.ram)  || 0;
      this.diskPercent = Number(data.disk) || 0;
      this._emit('stats', data);
    } else if (kind === 'alert') {
      this._handleAlert(data);
    }
    // heartbeat → ignore
  }

  // Dedupe alerts per kind (5min cooldown) + fire notification.
  // Test events (data.test === true) bypass the cooldown so testnotifyapp
  // always delivers, even when re-run within 5 minutes.
  _handleAlert(data) {
    const kind = data.kind || 'info';
    const now = Date.now();
    if (!data.test) {
      const last = this.lastAlertAt[kind] || 0;
      if (now - last < this.cooldownMs) return;
      this.lastAlertAt[kind] = now;
    }
    this._emit('alert', data);
    notify.show({
      kind,
      title: data.title || (data.test ? 'Drilex VPS (TEST)' : 'Drilex VPS'),
      body:  data.message || '',
    });
  }
}

// ─── NotificationService ──────────────────────────────────────────
// Wraps Capacitor LocalNotifications, falls back to in-app toasts on web.

const notify = {
  available: false,
  _lastForegroundAt: Date.now(),
  _toastStack: null,
  _fcmToken: null,
  _registerCallback: null,

  // Set a callback to be called when FCM token arrives (used to register with backend)
  onTokenReceived(fn) {
    if (this._fcmToken) fn(this._fcmToken);          // already received
    else this._registerCallback = fn;
  },

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
            importance: 4,           // HIGH = heads-up notification (Samsung floating)
            visibility: 1,            // PUBLIC – show on lockscreen
            sound: 'default',
            lights: true,
            lightColor: '#8B5CF6',
            vibration: true,
          });
          this.available = true;
        }
      } catch (e) { console.warn('Notifications init failed:', e); }
    }
    // Register for FCM push notifications (separate from LocalNotifications).
    // Push is delivered by Google's servers, works even when app is fully killed.
    // Requires Firebase setup (google-services.json + backend service account).
    if (window.Capacitor && Capacitor.isNativePlatform && Capacitor.isNativePlatform()) {
      try {
        const PN = Capacitor.Plugins.PushNotifications;
        if (PN) {
          const perm = await PN.requestPermissions();
          if (perm.receive === 'granted') {
            await PN.register();
            // Token arrives asynchronously
            PN.addListener('registration', async (tokenObj) => {
              this._fcmToken = tokenObj.value;
              console.log('[push] FCM token received');
              if (this._registerCallback) this._registerCallback(tokenObj.value);
            });
            PN.addListener('registrationError', (err) => {
              console.warn('[push] registration error:', err);
            });
            // When push arrives while app is open → show as toast
            PN.addListener('pushNotificationReceived', (n) => {
              this._toast('info', n.title || 'Drilex VPS', n.body || '');
            });
            // When user taps notification → just focus app (default behavior)
          }
        }
      } catch (e) { console.warn('PushNotifications init failed:', e); }
    }
  },

  // Mark app as foreground-active (resets heartbeat anti-spam timer)
  markForeground() {
    this._lastForegroundAt = Date.now();
  },

  // Send notification – in-app toast always + native heads-up when backgrounded.
  // Heads-up (Samsung "floating") = channel importance HIGH + matching channelId.
  async show({ kind, title, body }) {
    this._toast(kind, title, body);
    if (this.available && document.visibilityState === 'hidden') {
      try {
        const LN = Capacitor.Plugins.LocalNotifications;
        await LN.schedule({
          notifications: [{
            id: Math.floor(Math.random() * 1e9),
            title,
            body,
            channelId: 'drilex-default',
            smallIcon: 'ic_stat_drilex',
            largeIcon: 'ic_launcher',
            sound: null,                 // use channel default
            autoCancel: true,
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
