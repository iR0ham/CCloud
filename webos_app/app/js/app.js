/* App shell: RTL sidebar navigation, top bar, splash, bootstrap. */
(function () {
  var ICONS = {
    home: '<svg viewBox="0 0 24 24"><path d="M12 3l9 8h-3v9h-5v-6h-2v6H6v-9H3z"/></svg>',
    movie: '<svg viewBox="0 0 24 24"><path d="M4 4h16v16H4z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 4v16M16 4v16M4 9h4M4 15h4M16 9h4M16 15h4" stroke="currentColor" stroke-width="1.4"/></svg>',
    serie: '<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="13" rx="2" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 3l4 3 4-3" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M10 10l5 2.5-5 2.5z"/></svg>',
    search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M16.5 16.5L21 21" stroke="currentColor" stroke-width="1.8"/></svg>',
    globe: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M3 12h18M12 3c3 3 3 15 0 18M12 3c-3 3-3 15 0 18" fill="none" stroke="currentColor" stroke-width="1.4"/></svg>',
    live: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="2.4"/><path d="M7.5 7.5a6 6 0 000 9M16.5 7.5a6 6 0 010 9M4.7 4.7a10 10 0 000 14.6M19.3 4.7a10 10 0 010 14.6" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    heart: '<svg viewBox="0 0 24 24"><path d="M12 21s-8-5.3-8-11a4.5 4.5 0 018-2.8A4.5 4.5 0 0120 10c0 5.7-8 11-8 11z"/></svg>',
    history: '<svg viewBox="0 0 24 24"><path d="M12 8v5l3 2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M3.5 12a8.5 8.5 0 103-6.5M3.5 4v4h4" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    settings: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M12 2l1.5 3 3.3-.6 1 3.1 3 1.5-1.4 3 1.4 3-3 1.5-1 3.1-3.3-.6L12 22l-1.5-3-3.3.6-1-3.1-3-1.5 1.4-3-1.4-3 3-1.5 1-3.1 3.3.6z" fill="none" stroke="currentColor" stroke-width="1.2"/></svg>'
  };

  var TABS = [
    { name: 'home', label: 'خانه', icon: 'home' },
    { name: 'browse', kind: 'movie', label: 'فیلم‌ها', icon: 'movie' },
    { name: 'browse', kind: 'serie', label: 'سریال‌ها', icon: 'serie' },
    { name: 'search', label: 'جست‌وجو', icon: 'search' },
    { name: 'countries', label: 'کشورها', icon: 'globe' },
    { name: 'live', label: 'پخش زنده', icon: 'live' },
    { name: 'favorites', label: 'علاقه‌مندی', icon: 'heart' },
    { name: 'history', label: 'تاریخچه', icon: 'history' },
    { name: 'settings', label: 'تنظیمات', icon: 'settings' }
  ];

  function buildShell() {
    var nav = TABS.map(function (t, i) {
      return '<button class="nav-item focusable" data-tab="' + i + '" type="button">' +
        '<span class="nav-icon">' + ICONS[t.icon] + '</span><span class="nav-label">' + CC.esc(t.label) + '</span></button>';
    }).join('');
    document.getElementById('app').innerHTML =
      '<aside id="sidebar"><div class="side-brand">' + CC.ui.img('assets/img/logo.png', 'side-logo', 'CCloud') + '</div>' +
        '<nav class="side-nav">' + nav + '</nav>' +
        '<div class="side-foot"><span class="conn-dot" id="conn-dot"></span><span id="conn-text">در حال اتصال…</span></div>' +
      '</aside>' +
      '<div id="main"><main id="content"></main></div>';

    Array.prototype.forEach.call(document.querySelectorAll('[data-tab]'), function (btn) {
      btn.addEventListener('click', function () {
        var t = TABS[parseInt(btn.getAttribute('data-tab'), 10)];
        var params = t.kind ? { kind: t.kind } : {};
        CC.nav.go(t.name, params, { root: true });
      });
    });
  }

  CC.shell = {
    setActive: function (name, params) {
      params = params || {};
      var match = -1;
      for (var i = 0; i < TABS.length; i++) {
        var t = TABS[i];
        if (t.name !== name) continue;
        if (t.kind && t.kind !== params.kind) continue;
        match = i; break;
      }
      if (match < 0 && name === 'country') match = 4;
      Array.prototype.forEach.call(document.querySelectorAll('[data-tab]'), function (btn, i) {
        btn.classList.toggle('is-active', i === match);
      });
    },
    setConnection: function (ok, host) {
      var dot = document.getElementById('conn-dot');
      var text = document.getElementById('conn-text');
      if (dot) dot.className = 'conn-dot ' + (ok ? 'ok' : 'bad');
      if (text) text.textContent = ok ? 'متصل' : 'عدم اتصال';
      if (text && host) text.title = host;
    }
  };

  function boot() {
    CC.applyAppearance();
    buildShell();
    CC.nav.reset('home');
    CC.api.healthCheck().then(function (ok) {
      CC.shell.setConnection(ok, CC.api.activeHost);
      if (!ok) CC.ui.toast('اتصال به سرور برقرار نشد؛ میزبان‌های جایگزین بررسی شدند');
    });
    var splash = document.getElementById('splash');
    if (splash) setTimeout(function () { splash.classList.add('hide'); setTimeout(function () { if (splash.parentNode) splash.parentNode.removeChild(splash); }, 500); }, 700);

    document.addEventListener('webOSRelaunch', function () { CC.nav.reset('home'); });
    if (window.matchMedia) {
      try { window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function () { if (CC.settings.get('appearance') === 'system') CC.applyAppearance(); }); } catch (e) {}
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();