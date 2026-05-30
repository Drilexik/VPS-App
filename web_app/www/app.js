// ─── Drilex VPS – main app ─────────────────────────────────────────
// All screens + navigation. Vanilla JS, no framework.
//
// Architecture:
//   Storage   → persists URL+API key (Capacitor Preferences / localStorage)
//   App       → boot, navigation, lifecycle (app object)
//   Pages     → one render function per screen (Pages.home, Pages.disk, …)
//   helpers   → fmtBytes, gaugeHtml, confirmDialog, …

// Storage abstraction – uses Capacitor secure prefs on Android, localStorage on web
const Storage = {
  async get(key) {
    if (window.Capacitor?.Plugins?.Preferences) {
      const r = await Capacitor.Plugins.Preferences.get({ key });
      return r.value;
    }
    return localStorage.getItem(key);
  },
  async set(key, value) {
    if (window.Capacitor?.Plugins?.Preferences) {
      return Capacitor.Plugins.Preferences.set({ key, value });
    }
    localStorage.setItem(key, value);
  },
  async remove(key) {
    if (window.Capacitor?.Plugins?.Preferences) {
      return Capacitor.Plugins.Preferences.remove({ key });
    }
    localStorage.removeItem(key);
  },
};

// Main app object – holds API client + monitor service + routing state
const App = {
  api: null,
  monitor: null,
  currentPage: 'home',

  // Boot the app: load saved creds → show setup or main; hook lifecycle events
  async init() {
    await notify.init();
    this.monitor = new MonitorService();

    const url = await Storage.get('drilex_url');
    const key = await Storage.get('drilex_key');

    if (url && key) {
      this._enterApp(url, key);
    } else {
      this._setupListeners();
    }

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        notify.markForeground();
        if (this.monitor && !this.monitor.connected) this.monitor.start();
      } else {
        if (this.monitor) this.monitor.stop();
      }
    });
  },

  // Wire setup-screen events (Connect button + Enter key)
  _setupListeners() {
    document.getElementById('btn-connect').onclick = () => this._connect();
    document.getElementById('input-key').addEventListener('keypress', (e) => {
      if (e.key === 'Enter') this._connect();
    });
  },

  // Validate URL+key, ping /api/health, on success persist + enter main app
  async _connect() {
    const url = document.getElementById('input-url').value.trim();
    const key = document.getElementById('input-key').value.trim();
    const errEl = document.getElementById('setup-error');
    errEl.classList.add('hidden');

    if (!url || !key) {
      errEl.textContent = 'Please fill both fields';
      errEl.classList.remove('hidden');
      return;
    }
    const btn = document.getElementById('btn-connect');
    btn.disabled = true; btn.textContent = 'Connecting...';

    try {
      const tmpApi = new ApiClient(url, key);
      await tmpApi.health();
      await Storage.set('drilex_url', url);
      await Storage.set('drilex_key', key);
      this._enterApp(url, key);
    } catch (e) {
      errEl.textContent = 'Connection failed: ' + e.message;
      errEl.classList.remove('hidden');
      btn.disabled = false; btn.textContent = 'Connect';
    }
  },

  // Hide setup screen, build API client + monitor, wire header/drawer, start SSE
  async _enterApp(url, key) {
    this.api = new ApiClient(url, key);
    this.monitor.configure(url, key);

    document.getElementById('screen-setup').classList.add('hidden');
    document.getElementById('screen-main').classList.remove('hidden');

    try { document.getElementById('drawer-host').textContent = new URL(url).host; }
    catch { document.getElementById('drawer-host').textContent = url; }

    this._wireHeader();
    this._wireDrawer();
    this._wireMonitorState();

    notify.markForeground();
    this.monitor.start();
    this.showPage('home');

    // Register FCM token with backend when it arrives (push notifications)
    notify.onTokenReceived(async (token) => {
      try {
        await this.api._req('/api/push/register', { method: 'POST', body: { token } });
        console.log('[push] FCM token registered with backend');
      } catch (e) {
        console.warn('[push] failed to register token:', e.message);
      }
    });
  },

  // Menu button → open drawer
  _wireHeader() {
    document.getElementById('btn-menu').onclick = () => this._toggleDrawer(true);
  },

  // Drawer: clicking outside / on item closes it; Disconnect wipes creds + reloads
  _wireDrawer() {
    const drawer = document.getElementById('drawer');
    drawer.querySelectorAll('[data-close-drawer]').forEach(el =>
      el.onclick = () => this._toggleDrawer(false)
    );
    drawer.querySelectorAll('.drawer-item[data-page]').forEach(item => {
      item.onclick = () => {
        this.showPage(item.dataset.page);
        this._toggleDrawer(false);
      };
    });
    document.getElementById('btn-disconnect').onclick = async () => {
      await Storage.remove('drilex_url');
      await Storage.remove('drilex_key');
      this.monitor.stop();
      location.reload();
    };
  },

  // SSE connection badge: pulsing green "LIVE" when connected, gray "SYNC" when reconnecting
  _wireMonitorState() {
    const badge = document.getElementById('live-badge');
    this.monitor.on('state', (connected) => {
      badge.classList.toggle('connected', connected);
      badge.querySelector('.live-text').textContent = connected ? 'LIVE' : 'SYNC';
    });
  },

  // Show/hide side drawer
  _toggleDrawer(show) {
    document.getElementById('drawer').classList.toggle('hidden', !show);
  },

  // Switch to a page: highlight drawer item, update title, render content
  showPage(name) {
    this.currentPage = name;
    document.querySelectorAll('.drawer-item').forEach(i =>
      i.classList.toggle('active', i.dataset.page === name)
    );
    const titles = {
      home: 'Dashboard', stats: 'Statistics',
      cpu: 'CPU Monitor', ram: 'RAM Monitor',
      disk: 'Disk Manager', network: 'Network',
      docker: 'Docker', terminal: 'Terminal',
    };
    document.getElementById('header-title').textContent = titles[name] || 'Drilex VPS';
    const content = document.getElementById('page-content');
    content.innerHTML = '<div class="center-msg"><div class="spinner"></div></div>';
    const fn = Pages[name];
    if (fn) fn(content, this.api, this.monitor);
  },
};

// ─── PAGES ─────────────────────────────────────────────────────────
// Each page is async (root, api, monitor) => fills `root` with HTML and
// wires its own event handlers.
const Pages = {};

// HOME – Dashboard with 3 live gauges + system info + top CPU chart
Pages.home = async function(root, api, monitor) {
  root.innerHTML = `
    <div class="gauge-row">
      ${gaugeHtml('cpu', 'CPU')}
      ${gaugeHtml('ram', 'RAM')}
      ${gaugeHtml('disk', 'DISK')}
    </div>
    <div class="section">
      <h3 class="section-title">System</h3>
      <div id="home-info" class="list">
        <div class="center-msg"><div class="spinner"></div></div>
      </div>
    </div>
    <div class="section">
      <h3 class="section-title">Top CPU</h3>
      <div id="home-cpu" class="bar-chart"></div>
    </div>`;

  const update = (cpu, ram, disk) => {
    setGauge('cpu', cpu);
    setGauge('ram', ram);
    setGauge('disk', disk);
  };

  // Show last-known gauge values immediately (from monitor cache) — no blank state
  update(monitor.cpuPercent, monitor.ramPercent, monitor.diskPercent);

  // Subscribe to live updates
  const off = monitor.on('stats', (s) =>
    update(Number(s.cpu)||0, Number(s.ram)||0, Number(s.disk)||0)
  );
  root._cleanup = off;

  // Fetch overview + top CPU in parallel; render each as it lands
  const ovPromise = api.overview().catch(e => ({ _error: e.message }));
  const topPromise = api.topCpu(5).catch(e => ({ _error: e.message }));

  ovPromise.then(ov => {
    const info = document.getElementById('home-info');
    if (!info) return;
    if (ov._error) {
      info.innerHTML = errorBox(ov._error, () => App.showPage('home'));
      return;
    }
    const cpu  = ov.cpu  || {};
    const ram  = ov.ram  || {};
    const disk = ov.disk || {};
    update(num(cpu.usage_percent), num(ram.percent), num(disk.percent));
    info.innerHTML = `
      ${row('🖥', 'Hostname', ov.hostname || '—')}
      ${row('💻', 'OS', ov.os || '—')}
      ${row('⏱', 'Uptime', formatUptime(num(ov.uptime_seconds)))}
      ${row('💾', 'RAM', `${fmtBytes(ram.used)} / ${fmtBytes(ram.total)}`)}
      ${row('📁', 'Disk', `${fmtBytes(disk.used)} / ${fmtBytes(disk.total)}`)}
      ${row('🔥', 'CPU Cores', `${cpu.cores || '—'} (${cpu.logical_cores || '?'} threads)`)}
      ${cpu.temperature ? row('🌡', 'CPU Temp', `${cpu.temperature}°C`) : ''}
    `;
  });

  topPromise.then(top => {
    const el = document.getElementById('home-cpu');
    if (!el) return;
    if (top._error || !Array.isArray(top)) {
      el.innerHTML = empty('—');
      return;
    }
    el.innerHTML = top.map(p => `
      <div class="bar-row">
        <span class="name">${escapeHtml(p.name)}</span>
        <span class="bar"><span class="fill" style="width: ${Math.min(100, num(p.cpu_percent))}%"></span></span>
        <span class="val">${num(p.cpu_percent).toFixed(1)}%</span>
      </div>`).join('') || empty('No processes');
  });
};

// STATS – 4 bar charts: top CPU, top RAM, top Disk folders, top Network
Pages.stats = async function(root, api) {
  root.innerHTML = `
    <div class="section">
      <h3 class="section-title">Top CPU</h3>
      <div id="s-cpu" class="bar-chart"></div>
    </div>
    <div class="section">
      <h3 class="section-title">Top RAM</h3>
      <div id="s-ram" class="bar-chart"></div>
    </div>
    <div class="section">
      <h3 class="section-title">Top Disk Usage</h3>
      <div id="s-disk" class="bar-chart"></div>
    </div>
    <div class="section">
      <h3 class="section-title">Top Network</h3>
      <div id="s-net" class="bar-chart"></div>
    </div>`;
  try {
    const [cpu, ram, disk, net] = await Promise.all([
      api.topCpu(5), api.topRam(5), api.topDisk('/home', 5), api.topNetwork(5)
    ]);
    // Backend returns: top-cpu [{pid,name,cpu_percent,ram_mb,status}]
    document.getElementById('s-cpu').innerHTML  = barList(cpu, p => p.name, p => num(p.cpu_percent), v => `${v.toFixed(1)}%`);
    // top-ram has same shape; show MB used
    document.getElementById('s-ram').innerHTML  = barList(ram, p => p.name, p => num(p.ram_mb), v => `${fmtBytes(v * 1024 * 1024)}`);
    // top-disk-folders: [{path, size}] – display folder basename + raw size
    document.getElementById('s-disk').innerHTML = barList(disk, d => (d.path || '').split('/').pop() || d.path, d => num(d.size), v => fmtBytes(v));
    // top-network: [{pid, name, connections}]
    document.getElementById('s-net').innerHTML  = barList(net, p => p.name, p => num(p.connections), v => `${v} conn`);
  } catch (e) {
    root.innerHTML = errorBox(e.message, () => App.showPage('stats'));
  }
};

// CPU & RAM Monitor – same process list, just sorted differently
Pages.cpu = (root, api) => processList(root, api, 'cpu');
Pages.ram = (root, api) => processList(root, api, 'ram');

// Render 30 processes sorted by cpu/ram with Kill button on each row
async function processList(root, api, sortBy) {
  root.innerHTML = `<div class="list" id="proc-list"></div>`;
  try {
    const data = await api.processes(0, 30, sortBy);
    const list = document.getElementById('proc-list');
    if (!data.processes?.length) { list.innerHTML = empty('No processes'); return; }
    // Backend returns: [{pid, name, cpu_percent, ram_mb, status, command, killable}]
    list.innerHTML = data.processes.map(p => `
      <div class="row">
        <div class="row-icon">${sortBy === 'cpu' ? '⚡' : '▣'}</div>
        <div class="row-main">
          <div class="row-title">${escapeHtml(p.name)}</div>
          <div class="row-sub">PID ${p.pid} • CPU ${num(p.cpu_percent).toFixed(1)}% • RAM ${fmtBytes(num(p.ram_mb) * 1024 * 1024)} • ${escapeHtml(p.status || '')}</div>
        </div>
        ${p.killable !== false
          ? `<button class="row-btn danger" data-pid="${p.pid}">Kill</button>`
          : `<span style="color: var(--text-dim); font-size: 11px">protected</span>`}
      </div>`).join('');
    list.querySelectorAll('[data-pid]').forEach(btn => {
      btn.onclick = () => confirmKill(api, Number(btn.dataset.pid), btn.parentElement);
    });
  } catch (e) {
    root.innerHTML = errorBox(e.message, () => App.showPage(sortBy));
  }
}

// Show confirmation modal → call /api/processes/kill → remove row on success
async function confirmKill(api, pid, rowEl) {
  if (!await confirmDialog('Kill process?', `PID ${pid} – this cannot be undone.`)) return;
  try {
    await api.kill(pid, 15);
    rowEl.remove();
    notify._toast('success', 'Process killed', `PID ${pid}`);
  } catch (e) {
    notify._toast('error', 'Kill failed', e.message);
  }
}

// DISK – File browser with back button, mkdir, delete, and file viewer/editor
// `diskState.stack` keeps the navigation history so Back button works.
const diskState = { stack: ['/home'] };

Pages.disk = async function(root, api) {
  const path = diskState.stack[diskState.stack.length - 1];
  const canBack = diskState.stack.length > 1;
  const shortcuts = ['/home', '/root', '/etc/nginx', '/etc/systemd/system', '/var', '/opt', '/srv'];
  root.innerHTML = `
    <div class="path-bar">
      ${canBack ? `<button class="icon-btn" id="d-back">←</button>` : ''}
      <div class="path">${escapeHtml(path)}</div>
      <button class="icon-btn" id="d-mkdir" style="background: var(--primary-dim); color: var(--primary)" title="New folder">+</button>
    </div>
    <div style="display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px; overflow-x:auto">
      ${shortcuts.map(p => `<button class="row-btn" data-jump="${escapeAttr(p)}">${escapeHtml(p)}</button>`).join('')}
    </div>
    <div id="disk-list" class="list"></div>`;

  if (canBack) document.getElementById('d-back').onclick = () => {
    diskState.stack.pop(); App.showPage('disk');
  };
  document.getElementById('d-mkdir').onclick = () => mkdirPrompt(api, path);
  root.querySelectorAll('[data-jump]').forEach(btn => {
    btn.onclick = () => { diskState.stack = [btn.dataset.jump]; App.showPage('disk'); };
  });

  try {
    const data = await api.diskList(path);
    const list = document.getElementById('disk-list');
    if (!data.entries?.length) { list.innerHTML = empty('Empty folder'); return; }
    list.innerHTML = data.entries.map(e => `
      <div class="row">
        <div class="row-icon">${e.is_dir ? '📁' : fileIcon(e.name)}</div>
        <div class="row-main" data-action="open" data-path="${escapeAttr(e.path)}" data-dir="${e.is_dir}" data-name="${escapeAttr(e.name)}">
          <div class="row-title">${escapeHtml(e.name)}</div>
          <div class="row-sub">${e.is_dir ? 'Folder' : fmtBytes(num(e.size))}</div>
        </div>
        <button class="row-btn danger" data-action="del" data-path="${escapeAttr(e.path)}" data-dir="${e.is_dir}">×</button>
      </div>`).join('');

    list.querySelectorAll('[data-action="open"]').forEach(el => {
      el.onclick = () => {
        const p = el.dataset.path;
        if (el.dataset.dir === 'true') { diskState.stack.push(p); App.showPage('disk'); }
        else openFile(api, p, el.dataset.name);
      };
    });
    list.querySelectorAll('[data-action="del"]').forEach(btn => {
      btn.onclick = () => confirmDelete(api, btn.dataset.path, btn.dataset.dir === 'true');
    });
  } catch (e) {
    document.getElementById('disk-list').innerHTML = errorBox(e.message, () => App.showPage('disk'));
  }
};

// Prompt for new folder name → call /api/disk/mkdir → reload disk page
async function mkdirPrompt(api, parent) {
  const name = await promptDialog('New Folder', 'Folder name:');
  if (!name) return;
  try {
    await api.mkdir(parent.replace(/\/$/,'') + '/' + name);
    App.showPage('disk');
  } catch (e) {
    notify._toast('error', 'Failed to create', e.message);
  }
}

// Confirm dialog with recursive checkbox for folders → call /api/disk/delete
async function confirmDelete(api, path, isDir) {
  const recursive = isDir ? await confirmDialog('Delete folder?', `Path: ${path}\n\nDelete recursively (including contents)?`, 'Delete recursively') : false;
  if (recursive === null) return;
  if (!isDir && !await confirmDialog('Delete file?', `Path: ${path}`)) return;
  try {
    await api.rm(path, recursive === true);
    App.showPage('disk');
  } catch (e) {
    notify._toast('error', 'Delete failed', e.message);
  }
}

// File viewer/editor – read file → show in viewer; Edit toggles to textarea; Save POSTs back
async function openFile(api, path, name) {
  const root = document.getElementById('page-content');
  root.innerHTML = `
    <div style="display:flex; gap:8px; margin-bottom:12px; align-items:center">
      <button class="btn outline" id="fv-back">← Back</button>
      <div style="flex:1; font-family:monospace; font-size:13px; color: var(--accent); overflow:hidden; text-overflow:ellipsis; white-space:nowrap">${escapeHtml(name)}</div>
      <button class="btn" id="fv-edit">Edit</button>
      <button class="btn primary hidden" id="fv-save">Save</button>
    </div>
    <div class="file-viewer" id="fv-view"><div class="spinner"></div></div>
    <textarea class="file-editor hidden" id="fv-edit-area" spellcheck="false"></textarea>`;

  document.getElementById('fv-back').onclick = () => App.showPage('disk');

  let content = '';
  try {
    const r = await api.readFile(path);
    content = r.content || '';
    document.getElementById('fv-view').textContent = content || '(empty file)';
  } catch (e) {
    document.getElementById('fv-view').innerHTML = `<div style="color: var(--danger)">${escapeHtml(e.message)}</div>`;
    return;
  }

  document.getElementById('fv-edit').onclick = () => {
    document.getElementById('fv-view').classList.add('hidden');
    document.getElementById('fv-edit').classList.add('hidden');
    const ta = document.getElementById('fv-edit-area');
    ta.value = content;
    ta.classList.remove('hidden');
    document.getElementById('fv-save').classList.remove('hidden');
  };
  document.getElementById('fv-save').onclick = async () => {
    const text = document.getElementById('fv-edit-area').value;
    try {
      await api.writeFile(path, text);
      content = text;
      document.getElementById('fv-view').textContent = text || '(empty file)';
      document.getElementById('fv-view').classList.remove('hidden');
      document.getElementById('fv-edit').classList.remove('hidden');
      document.getElementById('fv-edit-area').classList.add('hidden');
      document.getElementById('fv-save').classList.add('hidden');
      notify._toast('success', 'File saved', name);
    } catch (e) {
      notify._toast('error', 'Save failed', e.message);
    }
  };
}

// NETWORK – Interface stats (bytes sent/recv) + IP ban/unban via iptables
Pages.network = async function(root, api) {
  root.innerHTML = `
    <div class="section">
      <h3 class="section-title">Interfaces</h3>
      <div id="net-ifaces" class="list"></div>
    </div>
    <div class="section">
      <h3 class="section-title">Banned IPs</h3>
      <div style="display:flex; gap:8px; margin-bottom:12px">
        <input class="text-input" id="net-ip" placeholder="IP address (e.g. 1.2.3.4)">
        <button class="btn danger" id="net-ban">Ban</button>
      </div>
      <div id="net-banned" class="list"></div>
    </div>`;

  try {
    const ifaces = await api.netStats();
    document.getElementById('net-ifaces').innerHTML = (Array.isArray(ifaces) ? ifaces : Object.entries(ifaces).map(([k,v]) => ({ name:k, ...v }))).map(i => `
      <div class="row">
        <div class="row-icon">🌐</div>
        <div class="row-main">
          <div class="row-title">${escapeHtml(i.name)}</div>
          <div class="row-sub">↑ ${fmtBytes(num(i.bytesSent ?? i.bytes_sent))} • ↓ ${fmtBytes(num(i.bytesRecv ?? i.bytes_recv))}</div>
        </div>
      </div>`).join('') || empty('No interfaces');

    await renderBanned(api);
  } catch (e) {
    root.innerHTML = errorBox(e.message, () => App.showPage('network'));
  }

  document.getElementById('net-ban').onclick = async () => {
    const ip = document.getElementById('net-ip').value.trim();
    if (!ip) return;
    try {
      await api.ban(ip);
      document.getElementById('net-ip').value = '';
      await renderBanned(api);
      notify._toast('success', 'IP banned', ip);
    } catch (e) {
      notify._toast('error', 'Ban failed', e.message);
    }
  };
};

// Fetch banned IP list + render each row with Unban button
async function renderBanned(api) {
  const wrap = document.getElementById('net-banned');
  wrap.innerHTML = '<div class="center-msg"><div class="spinner"></div></div>';
  try {
    const r = await api.netBanned();
    const list = r.banned || r;
    if (!list.length) { wrap.innerHTML = empty('No banned IPs'); return; }
    wrap.innerHTML = list.map(b => `
      <div class="row">
        <div class="row-icon">🚫</div>
        <div class="row-main">
          <div class="row-title">${escapeHtml(b.ip)}</div>
          ${b.reason ? `<div class="row-sub">${escapeHtml(b.reason)}</div>` : ''}
        </div>
        <button class="row-btn accent" data-ip="${escapeAttr(b.ip)}">Unban</button>
      </div>`).join('');
    wrap.querySelectorAll('[data-ip]').forEach(btn => {
      btn.onclick = async () => {
        try { await api.unban(btn.dataset.ip); await renderBanned(api); notify._toast('success','Unbanned',btn.dataset.ip); }
        catch (e) { notify._toast('error','Unban failed', e.message); }
      };
    });
  } catch (e) {
    wrap.innerHTML = errorBox(e.message, () => renderBanned(api));
  }
}

// DOCKER – List containers with start/stop/restart actions + logs viewer
Pages.docker = async function(root, api) {
  root.innerHTML = `<div id="docker-list" class="list"></div>`;
  try {
    const r = await api.containers();
    const list = r.containers || r;
    if (!list.length) { document.getElementById('docker-list').innerHTML = empty('No containers'); return; }
    document.getElementById('docker-list').innerHTML = list.map(c => {
      // Backend returns {id,name,image,status,cpu_percent,ram_mb}; status is e.g. "running" or "exited"
      const running = c.status === 'running' || c.state === 'running' || c.status?.startsWith?.('Up');
      const stats = running ? ` • CPU ${num(c.cpu_percent).toFixed(1)}% • RAM ${fmtBytes(num(c.ram_mb) * 1024 * 1024)}` : '';
      return `
        <div class="row">
          <div class="row-icon" style="background: ${running ? 'var(--accent-dim)' : 'var(--surface-2)'}; color: ${running ? 'var(--accent)' : 'var(--text-dim)'}">◈</div>
          <div class="row-main">
            <div class="row-title">${escapeHtml(c.name)}</div>
            <div class="row-sub">${escapeHtml(c.image || '?')} • ${escapeHtml(c.status || '?')}${stats}</div>
          </div>
          <div class="row-actions">
            ${running
              ? `<button class="row-btn" data-act="restart" data-id="${escapeAttr(c.id)}">↻</button>
                 <button class="row-btn danger" data-act="stop" data-id="${escapeAttr(c.id)}">■</button>`
              : `<button class="row-btn accent" data-act="start" data-id="${escapeAttr(c.id)}">▶</button>`}
            <button class="row-btn" data-act="logs" data-id="${escapeAttr(c.id)}" data-name="${escapeAttr(c.name)}">≡</button>
          </div>
        </div>`;
    }).join('');
    document.querySelectorAll('[data-act]').forEach(btn => {
      btn.onclick = async () => {
        const act = btn.dataset.act, id = btn.dataset.id;
        if (act === 'logs') return showLogs(api, id, btn.dataset.name);
        try { await api.containerAction(id, act); App.showPage('docker'); }
        catch (e) { notify._toast('error', `${act} failed`, e.message); }
      };
    });
  } catch (e) {
    root.innerHTML = errorBox(e.message, () => App.showPage('docker'));
  }
};

// Fetch last 200 log lines for a container and display in a terminal-style box
async function showLogs(api, id, name) {
  const root = document.getElementById('page-content');
  root.innerHTML = `
    <div style="display:flex; gap:8px; margin-bottom:12px; align-items:center">
      <button class="btn outline" id="lg-back">← Back</button>
      <div style="flex:1; font-family:monospace; font-size:13px; color: var(--accent)">${escapeHtml(name)}</div>
    </div>
    <div class="terminal" id="lg-out"><div class="spinner"></div></div>`;
  document.getElementById('lg-back').onclick = () => App.showPage('docker');
  try {
    const r = await api.containerLogs(id, 200);
    document.getElementById('lg-out').textContent = r.logs || r || '(no logs)';
  } catch (e) {
    document.getElementById('lg-out').innerHTML = `<span style="color: var(--danger)">${escapeHtml(e.message)}</span>`;
  }
}

// TERMINAL – Whitelisted shell command runner with scrollback history
const termHistory = [];

Pages.terminal = async function(root, api) {
  root.innerHTML = `
    <div class="terminal" id="t-out"></div>
    <div class="terminal-input-bar">
      <input id="t-input" placeholder="Enter command (ls, ps, df, ...)">
      <button class="btn primary" id="t-run">Run</button>
    </div>`;

  const out = document.getElementById('t-out');
  out.innerHTML = termHistory.length
    ? termHistory.join('\n')
    : '<div style="color: var(--text-dim)">Whitelisted commands only. Type any command and press Run.</div>';

  const run = async () => {
    const cmd = document.getElementById('t-input').value.trim();
    if (!cmd) return;
    document.getElementById('t-input').value = '';
    appendTerm(`<span class="cmd">$ ${escapeHtml(cmd)}</span>`);
    try {
      const r = await api.exec(cmd);
      if (r.stdout) appendTerm(`<span class="out">${escapeHtml(r.stdout)}</span>`);
      if (r.stderr) appendTerm(`<span class="err">${escapeHtml(r.stderr)}</span>`);
    } catch (e) {
      appendTerm(`<span class="err">${escapeHtml(e.message)}</span>`);
    }
    out.scrollTop = out.scrollHeight;
  };
  document.getElementById('t-run').onclick = run;
  document.getElementById('t-input').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') run();
  });
};

// Append output line to terminal scrollback (caps at 200 lines)
function appendTerm(html) {
  termHistory.push(html);
  if (termHistory.length > 200) termHistory.shift();
  const out = document.getElementById('t-out');
  if (out) out.innerHTML = termHistory.join('\n');
}

// ─── HELPERS ───────────────────────────────────────────────────────

// Safe number conversion (returns 0 instead of NaN)
function num(v) { const n = Number(v); return isFinite(n) ? n : 0; }

// Format bytes → human-readable (e.g. 1536000 → "1.5 MB")
function fmtBytes(bytes) {
  bytes = num(bytes);
  if (bytes < 1024) return bytes + ' B';
  const units = ['KB','MB','GB','TB'];
  let i = -1, v = bytes;
  do { v /= 1024; i++; } while (v >= 1024 && i < units.length - 1);
  return v.toFixed(v < 10 ? 1 : 0) + ' ' + units[i];
}

// Format uptime seconds → "5d 3h 12m" / "2h 30m" / "45m"
function formatUptime(sec) {
  sec = num(sec);
  const d = Math.floor(sec / 86400);
  const h = Math.floor((sec % 86400) / 3600);
  const m = Math.floor((sec % 3600) / 60);
  if (d) return `${d}d ${h}h ${m}m`;
  if (h) return `${h}h ${m}m`;
  return `${m}m`;
}

// Build circular SVG gauge HTML (empty arc, label below). Update via setGauge().
function gaugeHtml(id, label) {
  const r = 32, c = 2 * Math.PI * r;
  return `
    <div class="gauge">
      <div class="gauge-ring">
        <svg width="80" height="80" viewBox="0 0 80 80">
          <circle class="bg-arc" cx="40" cy="40" r="${r}" fill="none" stroke-width="6"/>
          <circle id="gauge-${id}" class="fg-arc" cx="40" cy="40" r="${r}" fill="none"
                  stroke="var(--primary)" stroke-width="6" stroke-linecap="round"
                  stroke-dasharray="${c}" stroke-dashoffset="${c}"/>
        </svg>
        <div class="gauge-value" id="gv-${id}">0%</div>
      </div>
      <div class="gauge-label">${label}</div>
    </div>`;
}
// Update gauge arc + percentage + color (green→purple→orange→red as value grows)
function setGauge(id, value) {
  const r = 32, c = 2 * Math.PI * r;
  const arc = document.getElementById(`gauge-${id}`);
  const val = document.getElementById(`gv-${id}`);
  if (!arc || !val) return;
  const v = Math.max(0, Math.min(100, value));
  arc.style.strokeDashoffset = c * (1 - v / 100);
  arc.style.stroke = v > 90 ? 'var(--danger)' : v > 75 ? 'var(--warning)' : v > 50 ? 'var(--primary)' : 'var(--accent)';
  val.textContent = v.toFixed(0) + '%';
}

// Render a generic info row (icon + title + right-aligned value)
function row(icon, title, value) {
  return `<div class="row">
    <div class="row-icon">${icon}</div>
    <div class="row-main"><div class="row-title">${escapeHtml(title)}</div></div>
    <div class="row-value">${escapeHtml(value)}</div>
  </div>`;
}

// Render horizontal bar chart from an array (bars scaled to the max value)
function barList(items, getName, getVal, formatter) {
  if (!items?.length) return empty('No data');
  const max = Math.max(...items.map(i => num(getVal(i)))) || 1;
  return items.map(i => {
    const v = num(getVal(i));
    return `<div class="bar-row">
      <span class="name">${escapeHtml(getName(i))}</span>
      <span class="bar"><span class="fill" style="width: ${(v/max*100).toFixed(0)}%"></span></span>
      <span class="val">${formatter(v)}</span>
    </div>`;
  }).join('');
}

// "No data" placeholder
function empty(msg)  { return `<div class="center-msg">${escapeHtml(msg)}</div>`; }
// Error placeholder with Retry button (caller passes a callback)
function errorBox(msg, retry) {
  const id = 'r' + Math.random().toString(36).slice(2,8);
  setTimeout(() => { const el = document.getElementById(id); if (el && retry) el.onclick = retry; }, 0);
  return `<div class="center-msg">
    <div style="color: var(--danger); font-size: 13px; word-break: break-word">${escapeHtml(msg)}</div>
    <button class="btn primary" id="${id}">Retry</button>
  </div>`;
}

// Pick emoji icon based on file extension (used in disk browser rows)
function fileIcon(name) {
  const ext = (name.split('.').pop() || '').toLowerCase();
  const map = {
    jpg:'🖼',jpeg:'🖼',png:'🖼',gif:'🖼',
    mp4:'🎬',mkv:'🎬',
    mp3:'🎵',wav:'🎵',
    pdf:'📕', zip:'🗜', tar:'🗜', gz:'🗜',
    py:'🐍', js:'📜', json:'📜', yaml:'📜', yml:'📜', sh:'📜',
    txt:'📝', log:'📝', md:'📝', conf:'⚙', service:'⚙',
  };
  return map[ext] || '📄';
}

// Escape value for use inside an HTML attribute
function escapeAttr(s) { return escapeHtml(s).replaceAll('"', '&quot;'); }

// Modal yes/no dialog (returns Promise<bool>). With `recursiveCheckboxLabel` it
// becomes a tri-state: true (with checkbox), false (without), null (cancelled).
function confirmDialog(title, text, recursiveCheckboxLabel) {
  return new Promise(resolve => {
    const showCheckbox = !!recursiveCheckboxLabel;
    const html = `
      <div class="modal-bg">
        <div class="modal">
          <h3 class="modal-title">${escapeHtml(title)}</h3>
          <p class="modal-text" style="white-space:pre-wrap">${escapeHtml(text)}</p>
          ${showCheckbox ? `<label style="display:flex; align-items:center; gap:8px; font-size:14px"><input type="checkbox" id="dl-rec">${escapeHtml(recursiveCheckboxLabel)}</label>` : ''}
          <div class="modal-actions">
            <button class="btn outline" id="dl-cancel">Cancel</button>
            <button class="btn danger" id="dl-ok">OK</button>
          </div>
        </div>
      </div>`;
    const wrap = document.createElement('div');
    wrap.innerHTML = html;
    document.body.appendChild(wrap);
    const done = (v) => { wrap.remove(); resolve(v); };
    wrap.querySelector('#dl-cancel').onclick = () => done(showCheckbox ? null : false);
    wrap.querySelector('#dl-ok').onclick = () => {
      if (showCheckbox) done(wrap.querySelector('#dl-rec').checked);
      else done(true);
    };
  });
}

// Modal text-input dialog (returns Promise<string|null>)
function promptDialog(title, label) {
  return new Promise(resolve => {
    const wrap = document.createElement('div');
    wrap.innerHTML = `
      <div class="modal-bg">
        <div class="modal">
          <h3 class="modal-title">${escapeHtml(title)}</h3>
          <label class="modal-text">${escapeHtml(label)}</label>
          <input class="text-input" id="dl-input" autofocus>
          <div class="modal-actions">
            <button class="btn outline" id="dl-cancel">Cancel</button>
            <button class="btn primary" id="dl-ok">OK</button>
          </div>
        </div>
      </div>`;
    document.body.appendChild(wrap);
    const input = wrap.querySelector('#dl-input');
    input.focus();
    const done = (v) => { wrap.remove(); resolve(v); };
    wrap.querySelector('#dl-cancel').onclick = () => done(null);
    wrap.querySelector('#dl-ok').onclick = () => done(input.value.trim() || null);
    input.addEventListener('keypress', e => { if (e.key === 'Enter') done(input.value.trim() || null); });
  });
}

// ─── BOOT ──────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => App.init());
