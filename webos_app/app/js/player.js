/* Full-screen player. HTML5 <video> on webOS plays HLS/MP4/MKV via the TV's
 * hardware pipeline. Remote-first controls, quality switching, episode/channel
 * playlists, resume and watch-history recording. */
(function () {
  var P = null;
  var SPEEDS = [0.5, 1, 1.25, 1.5, 2];

  function el(tag, cls, html) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html !== undefined) e.innerHTML = html;
    return e;
  }

  CC.player = {
    active: function () { return !!P; },
    open: function (opts) {
      if (P) teardown(true);
      build(opts);
    },
    onKey: function (e, code) { return handleKey(e, code); }
  };

  function build(opts) {
    var overlay = el('div', 'player');
    overlay.setAttribute('tabindex', '-1');
    overlay.innerHTML =
      '<video class="player-video" id="pv" playsinline autoplay></video>' +
      '<div class="player-buffering" id="p-buffer"><div class="spinner"></div></div>' +
      '<div class="player-error" id="p-error"></div>' +
      '<div class="player-top" id="p-top">' +
        '<button class="p-icon focusable" data-act="back" type="button" aria-label="بازگشت">✕</button>' +
        '<div class="p-titles"><span class="p-title" id="p-title"></span><span class="p-sub" id="p-sub"></span></div>' +
        '<span class="p-live" id="p-live">● پخش زنده</span>' +
      '</div>' +
      '<div class="player-controls" id="p-controls">' +
        '<div class="p-seekrow" id="p-seekrow">' +
          '<span class="p-time" id="p-cur">۰:۰۰</span>' +
          '<div class="seek focusable" id="p-seek" tabindex="0" role="slider" aria-label="جست‌وجوی زمانی">' +
            '<div class="seek-buffer" id="p-buf"></div><div class="seek-played" id="p-played"></div><div class="seek-knob" id="p-knob"></div>' +
          '</div>' +
          '<span class="p-time" id="p-dur">۰:۰۰</span>' +
        '</div>' +
        '<div class="p-buttons">' +
          '<button class="p-icon focusable" data-act="rew" type="button" aria-label="۱۰ ثانیه عقب">⏪</button>' +
          '<button class="p-icon p-play focusable" data-act="toggle" type="button" aria-label="پخش/توقف">⏸</button>' +
          '<button class="p-icon focusable" data-act="fwd" type="button" aria-label="۱۰ ثانیه جلو">⏩</button>' +
          '<button class="p-text focusable" data-act="speed" type="button" id="p-speed">۱×</button>' +
          '<button class="p-text focusable" data-act="quality" type="button" id="p-quality">کیفیت</button>' +
          '<button class="p-text focusable" data-act="next" type="button" id="p-next">قسمت بعد ⏭</button>' +
        '</div>' +
      '</div>' +
      '<div class="player-menu" id="p-menu"></div>';
    document.body.appendChild(overlay);

    P = {
      opts: opts, overlay: overlay,
      video: overlay.querySelector('#pv'),
      controlsVisible: true, menuOpen: false, hideTimer: null,
      speedIdx: 1, duration: 0, started: false, lastRecord: 0,
      sources: opts.item ? (opts.episode ? opts.episode.playableSources : opts.item.playableSources) : [opts.source],
      currentSource: opts.source
    };

    overlay.querySelector('#p-title').textContent = opts.title || (opts.item ? opts.item.title : '');
    var sub = '';
    if (opts.episode) sub = (opts.seasonTitle ? opts.seasonTitle + ' · ' : '') + (opts.episode.title || '');
    else if (opts.item) sub = [opts.item.yearText, opts.item.genreText].filter(function (x) { return x; }).join(' • ');
    overlay.querySelector('#p-sub').textContent = sub;
    overlay.querySelector('#p-live').style.display = opts.live ? '' : 'none';
    overlay.querySelector('#p-seekrow').style.display = opts.live ? 'none' : '';
    overlay.querySelector('#p-next').style.display = (!opts.live && opts.playlist && opts.playlist.length > 1) ? '' : 'none';
    overlay.querySelector('[data-act="rew"]').style.display = opts.live ? 'none' : '';
    overlay.querySelector('[data-act="fwd"]').style.display = opts.live ? 'none' : '';
    overlay.querySelector('[data-act="speed"]').style.display = opts.live ? 'none' : '';
    overlay.querySelector('#p-quality').textContent = opts.live ? 'شبکه‌ها' : 'کیفیت';

    bindControls();
    loadMedia(opts.source, opts.startFraction || 0);
    showControls();
    overlay.focus();

    P.video.addEventListener('error', onVideoError);
    P.video.addEventListener('waiting', function () { setBuffering(true); });
    P.video.addEventListener('playing', function () { setBuffering(false); });
    P.video.addEventListener('canplay', function () { setBuffering(false); });
    P.video.addEventListener('ended', onEnded);
    P.video.addEventListener('timeupdate', onTimeUpdate);
    P.video.addEventListener('progress', updateBuffered);
    P.video.addEventListener('loadedmetadata', function () {
      P.duration = P.video.duration || 0;
      overlay.querySelector('#p-dur').textContent = opts.live ? 'زنده' : CC.fmtTime(P.duration);
    });
  }

  function loadMedia(source, startFraction) {
    if (!source || !source.url) { onVideoError(); return; }
    P.currentSource = source;
    setBuffering(true);
    hideError();
    P.video.src = source.url;
    P.video.playbackRate = SPEEDS[P.speedIdx];
    var resume = startFraction;
    P.video.load();
    var p = P.video.play();
    if (p && p.catch) p.catch(function () { /* autoplay may need a key; controls remain */ });
    if (resume > 0 && !P.opts.live) {
      P.video.addEventListener('loadedmetadata', function seekOnce() {
        P.video.removeEventListener('loadedmetadata', seekOnce);
        var d = P.video.duration || 0;
        if (d > 0 && isFinite(d)) P.video.currentTime = resume * d;
      });
    }
    updatePlayIcon();
  }

  function bindControls() {
    var o = P.overlay;
    Array.prototype.forEach.call(o.querySelectorAll('[data-act]'), function (btn) {
      btn.addEventListener('click', function () { act(btn.getAttribute('data-act')); });
    });
    var seek = o.querySelector('#p-seek');
    seek.addEventListener('click', function (e) {
      if (P.opts.live || !P.duration) return;
      var r = seek.getBoundingClientRect();
      var frac = CC.clamp((e.clientX - r.left) / r.width, 0, 1);
      // RTL: seek bar fills from right; invert
      frac = 1 - frac;
      P.video.currentTime = frac * P.duration;
      showControls();
    });
    o.addEventListener('mousemove', function () { if (P) showControls(); });
    o.addEventListener('click', function (e) {
      if (e.target === P.video) { act('toggle'); }
    });
  }

  function act(a) {
    if (!P) return;
    showControls();
    if (a === 'back') { close(); return; }
    if (a === 'toggle') { togglePlay(); return; }
    if (a === 'rew') { seekBy(-10); return; }
    if (a === 'fwd') { seekBy(10); return; }
    if (a === 'speed') {
      P.speedIdx = (P.speedIdx + 1) % SPEEDS.length;
      P.video.playbackRate = SPEEDS[P.speedIdx];
      P.overlay.querySelector('#p-speed').textContent = CC.faDigits(SPEEDS[P.speedIdx]) + '×';
      return;
    }
    if (a === 'quality') { openMenu(); return; }
    if (a === 'next') { playNext(); return; }
  }

  function togglePlay() {
    if (!P) return;
    if (P.video.paused) { var p = P.video.play(); if (p && p.catch) p.catch(function () {}); }
    else P.video.pause();
    updatePlayIcon();
  }
  function updatePlayIcon() {
    if (!P) return;
    var b = P.overlay.querySelector('[data-act="toggle"]');
    if (b) b.textContent = P.video.paused ? '▶' : '⏸';
  }
  function seekBy(delta) {
    if (!P || P.opts.live || !P.duration) return;
    P.video.currentTime = CC.clamp(P.video.currentTime + delta, 0, P.duration);
    onTimeUpdate();
  }

  function setBuffering(on) {
    if (!P) return;
    P.overlay.querySelector('#p-buffer').classList.toggle('show', on);
  }

  function onTimeUpdate() {
    if (!P) return;
    var v = P.video, o = P.overlay;
    var cur = v.currentTime || 0;
    o.querySelector('#p-cur').textContent = CC.fmtTime(cur);
    if (P.duration > 0) {
      var frac = CC.clamp(cur / P.duration, 0, 1);
      // RTL fill from right
      o.querySelector('#p-played').style.width = (frac * 100) + '%';
      o.querySelector('#p-knob').style.right = (frac * 100) + '%';
    }
    var now = Date.now();
    if (now - P.lastRecord > 5000) { P.lastRecord = now; recordProgress(); }
  }
  function updateBuffered() {
    if (!P || !P.duration) return;
    try {
      var b = P.video.buffered;
      if (b.length) {
        var end = b.end(b.length - 1);
        P.overlay.querySelector('#p-buf').style.width = CC.clamp(end / P.duration, 0, 1) * 100 + '%';
      }
    } catch (e) {}
  }

  function recordProgress() {
    if (!P || !P.opts.item || P.opts.live) return;
    var frac = P.duration > 0 ? CC.clamp(P.video.currentTime / P.duration, 0, 1) : 0;
    CC.history.record(P.opts.item, {
      progress: frac,
      episodeId: P.opts.episode ? P.opts.episode.id : null,
      seasonTitle: P.opts.seasonTitle || '',
      episodeLabel: P.opts.episode ? P.opts.episode.title : ''
    });
  }

  function onEnded() {
    if (!P) return;
    recordProgress();
    if (!P.opts.live && P.opts.playlist && CC.settings.get('autoPlayNextEpisode')) {
      if (playNext()) return;
    }
    close();
  }

  function playNext() {
    if (!P || !P.opts.playlist) return false;
    var next = P.opts.index + 1;
    if (next >= P.opts.playlist.length) return false;
    var ep = P.opts.playlist[next];
    var src = CC.preferredSource(ep.playableSources, CC.settings.get('preferredQuality'));
    if (!src) return false;
    var opts = Object.assign({}, P.opts, { episode: ep, source: src, index: next, startFraction: 0 });
    teardown(true);
    build(opts);
    CC.history.record(opts.item, { progress: 0, episodeId: ep.id, seasonTitle: opts.seasonTitle, episodeLabel: ep.title });
    return true;
  }

  // ---- quality / channel menu ----
  function openMenu() {
    if (!P) return;
    var menu = P.overlay.querySelector('#p-menu');
    var options, kind;
    if (P.opts.live) {
      kind = 'channel';
      options = (P.opts.channels || []).map(function (ch, i) {
        return { label: ch.name, sub: ch.languageLabel, active: i === P.opts.index, idx: i };
      });
    } else {
      kind = 'quality';
      options = (P.sources || []).map(function (s, i) {
        return { label: s.qualityLabel, sub: s.kindLabel, active: s === P.currentSource, idx: i };
      });
    }
    if (!options.length) { CC.ui.toast('گزینه‌ای موجود نیست'); return; }
    menu.innerHTML = '<div class="menu-title">' + (kind === 'channel' ? 'انتخاب شبکه' : 'انتخاب کیفیت') + '</div>' +
      '<div class="menu-list">' + options.map(function (op) {
        return '<button class="menu-item focusable' + (op.active ? ' is-active' : '') + '" data-mi="' + op.idx + '" type="button">' +
          '<span>' + CC.esc(op.label) + '</span><span class="menu-sub">' + CC.esc(op.sub || '') + '</span></button>';
      }).join('') + '</div>';
    menu.classList.add('show');
    P.menuOpen = true;
    Array.prototype.forEach.call(menu.querySelectorAll('[data-mi]'), function (btn) {
      btn.addEventListener('click', function () {
        var idx = parseInt(btn.getAttribute('data-mi'), 10);
        closeMenu();
        if (kind === 'channel') switchChannel(idx);
        else switchQuality(idx);
      });
    });
    var active = menu.querySelector('.is-active') || menu.querySelector('.menu-item');
    if (active) active.focus();
  }
  function closeMenu() {
    if (!P) return;
    P.overlay.querySelector('#p-menu').classList.remove('show');
    P.menuOpen = false;
    var q = P.overlay.querySelector('#p-quality'); if (q) q.focus();
    showControls();
  }
  function switchQuality(idx) {
    var s = P.sources[idx];
    if (!s) return;
    var t = P.video.currentTime || 0;
    loadMedia(s, 0);
    P.video.addEventListener('loadedmetadata', function once() {
      P.video.removeEventListener('loadedmetadata', once);
      if (t > 0 && P.duration > 0) P.video.currentTime = t;
    });
    CC.ui.toast('کیفیت: ' + s.qualityLabel);
  }
  function switchChannel(idx) {
    var ch = P.opts.channels[idx];
    if (!ch || !ch.primaryStream) return;
    P.opts.index = idx;
    P.opts.title = ch.name;
    P.overlay.querySelector('#p-title').textContent = ch.name;
    loadMedia({ url: ch.primaryStream, kind: 'hls', qualityLabel: 'پخش زنده' }, 0);
  }

  // ---- error ----
  function onVideoError() {
    if (!P) return;
    setBuffering(false);
    var box = P.overlay.querySelector('#p-error');
    var hasAlt = (P.sources || []).length > 1;
    box.innerHTML = '<div class="state-icon">⚠️</div><p class="state-msg">پخش این منبع ممکن نشد</p>' +
      '<p class="state-hint">ممکن است کدک پشتیبانی نشود یا منبع در دسترس نباشد.</p>' +
      '<div class="error-actions">' +
        '<button class="btn btn-primary focusable" data-err="retry" type="button">تلاش دوباره</button>' +
        (hasAlt ? '<button class="btn btn-ghost focusable" data-err="quality" type="button">کیفیت دیگر</button>' : '') +
        '<button class="btn btn-ghost focusable" data-err="back" type="button">بازگشت</button>' +
      '</div>';
    box.classList.add('show');
    Array.prototype.forEach.call(box.querySelectorAll('[data-err]'), function (b) {
      b.addEventListener('click', function () {
        var a = b.getAttribute('data-err');
        if (a === 'retry') { hideError(); loadMedia(P.currentSource, 0); }
        else if (a === 'quality') { hideError(); openMenu(); }
        else close();
      });
    });
    var first = box.querySelector('.focusable'); if (first) first.focus();
  }
  function hideError() { if (P) P.overlay.querySelector('#p-error').classList.remove('show'); }

  // ---- controls visibility ----
  function showControls() {
    if (!P) return;
    P.controlsVisible = true;
    P.overlay.classList.add('controls-visible');
    clearTimeout(P.hideTimer);
    P.hideTimer = setTimeout(function () {
      if (!P || P.menuOpen) return;
      if (!P.video.paused) hideControls();
    }, 4000);
  }
  function hideControls() {
    if (!P) return;
    P.controlsVisible = false;
    P.overlay.classList.remove('controls-visible');
    P.overlay.focus();
  }

  // ---- key handling ----
  function scopedMove(dir) {
    var scope = P.menuOpen ? P.overlay.querySelector('#p-menu') : P.overlay;
    var cur = document.activeElement;
    if (!cur || !scope.contains(cur) || !cur.classList.contains('focusable')) {
      var f = scope.querySelector('.focusable'); if (f) f.focus(); return;
    }
    var r = cur.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    var best = null, bestScore = Infinity;
    Array.prototype.forEach.call(scope.querySelectorAll('.focusable'), function (e) {
      if (e === cur || e.offsetParent === null) return;
      var b = e.getBoundingClientRect(), bx = b.left + b.width / 2, by = b.top + b.height / 2;
      var dx = bx - cx, dy = by - cy, primary, secondary, ok = false;
      if (dir === 'right') { ok = dx > 1; primary = dx; secondary = Math.abs(dy); }
      else if (dir === 'left') { ok = dx < -1; primary = -dx; secondary = Math.abs(dy); }
      else if (dir === 'down') { ok = dy > 1; primary = dy; secondary = Math.abs(dx); }
      else { ok = dy < -1; primary = -dy; secondary = Math.abs(dx); }
      if (!ok) return;
      var score = primary + secondary * 2;
      if (score < bestScore) { bestScore = score; best = e; }
    });
    if (best) best.focus();
  }

  function handleKey(e, code) {
    if (!P) return false;
    var K = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13, BACK: 461, ESC: 27,
      PLAY: 415, PAUSE: 19, STOP: 413, RR: 412, FF: 417, PLAYPAUSE: 10252 };
    // media keys
    if (code === K.PLAY) { if (P.video.paused) togglePlay(); showControls(); return true; }
    if (code === K.PAUSE) { if (!P.video.paused) togglePlay(); showControls(); return true; }
    if (code === K.PLAYPAUSE) { togglePlay(); showControls(); return true; }
    if (code === K.STOP) { close(); return true; }
    if (code === K.RR) { seekBy(-10); showControls(); return true; }
    if (code === K.FF) { seekBy(10); showControls(); return true; }

    if (code === K.BACK || code === K.ESC) {
      if (P.menuOpen) { closeMenu(); return true; }
      close(); return true;
    }

    if (P.menuOpen) {
      if (code === K.LEFT) { scopedMove('left'); return true; }
      if (code === K.RIGHT) { scopedMove('right'); return true; }
      if (code === K.UP) { scopedMove('up'); return true; }
      if (code === K.DOWN) { scopedMove('down'); return true; }
      if (code === K.ENTER) { var c = document.activeElement; if (c) c.click(); return true; }
      return true;
    }

    var seekFocused = document.activeElement === P.overlay.querySelector('#p-seek');

    if (!P.controlsVisible) {
      if (code === K.ENTER) { togglePlay(); showControls(); return true; }
      if (code === K.LEFT) { seekBy(-10); showControls(); return true; }
      if (code === K.RIGHT) { seekBy(10); showControls(); return true; }
      if (code === K.UP || code === K.DOWN) { showControls(); var pb = P.overlay.querySelector('[data-act="toggle"]'); if (pb) pb.focus(); return true; }
      showControls(); return true;
    }

    // controls visible
    if (seekFocused && (code === K.LEFT || code === K.RIGHT)) {
      // RTL: right = backward, left = forward
      seekBy(code === K.LEFT ? 10 : -10); return true;
    }
    if (code === K.LEFT) { scopedMove('left'); return true; }
    if (code === K.RIGHT) { scopedMove('right'); return true; }
    if (code === K.UP) { scopedMove('up'); return true; }
    if (code === K.DOWN) { scopedMove('down'); return true; }
    if (code === K.ENTER) { var cur = document.activeElement; if (cur && cur.classList.contains('focusable')) cur.click(); else togglePlay(); return true; }
    return true;
  }

  function teardown(record) {
    if (!P) return;
    if (record) recordProgress();
    clearTimeout(P.hideTimer);
    try { P.video.pause(); P.video.removeAttribute('src'); P.video.load(); } catch (e) {}
    if (P.overlay && P.overlay.parentNode) P.overlay.parentNode.removeChild(P.overlay);
    P = null;
  }
  function close() {
    teardown(true);
    // restore focus to the page
    setTimeout(function () { CC.focus.first(document.getElementById('content')); }, 30);
  }
})();