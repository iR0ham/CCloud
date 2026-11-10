/* Spatial (D-pad) focus navigation + a small back-stack router. */
(function () {
  CC.screens = {};
  var stack = [];
  var current = null;

  function renderTop() {
    var route = stack[stack.length - 1];
    if (!route) return;
    current = route;
    var screen = CC.screens[route.name];
    var container = document.getElementById('content');
    container.innerHTML = '';
    container.scrollTop = 0;
    document.getElementById('content').setAttribute('data-screen', route.name);
    if (CC.shell) CC.shell.setActive(route.name, route.params);
    if (screen && screen.render) screen.render(container, route.params || {});
    // initial focus
    setTimeout(function () {
      if (screen && screen.focusFirst) screen.focusFirst(container);
      else CC.focus.first(container);
    }, 30);
  }

  CC.nav = {
    go: function (name, params, opts) {
      opts = opts || {};
      var route = { name: name, params: params || {} };
      if (opts.root || stack.length === 0) stack = [route];
      else stack.push(route);
      renderTop();
    },
    replace: function (name, params) {
      if (stack.length) stack[stack.length - 1] = { name: name, params: params || {} };
      else stack = [{ name: name, params: params || {} }];
      renderTop();
    },
    back: function () {
      if (current && CC.screens[current.name] && CC.screens[current.name].onBack) {
        if (CC.screens[current.name].onBack() === true) return;
      }
      if (stack.length > 1) { stack.pop(); renderTop(); return; }
      // at root: exit on TV
      if (window.webOS && window.webOS.platformBack) window.webOS.platformBack();
      else if (CC.isWebOS() && window.close) window.close();
    },
    reset: function (name, params) { stack = [{ name: name, params: params || {} }]; renderTop(); },
    current: function () { return current; },
    depth: function () { return stack.length; }
  };

  // ---- focus helpers ----
  function visible(el) {
    if (!el || el.disabled) return false;
    if (el.offsetParent === null && getComputedStyle(el).position !== 'fixed') return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  function focusables(root) {
    return Array.prototype.slice.call((root || document).querySelectorAll('.focusable'))
      .filter(function (el) { return visible(el); });
  }

  CC.focus = {
    first: function (root) {
      var list = focusables(root || document.getElementById('content'));
      if (list.length) { list[0].focus(); list[0].scrollIntoView({ block: 'nearest', inline: 'nearest' }); }
    },
    current: function () {
      var el = document.activeElement;
      return el && el.classList && el.classList.contains('focusable') ? el : null;
    },
    move: function (dir) {
      var cur = CC.focus.current();
      if (!cur) { CC.focus.first(); return; }
      var r = cur.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      var best = null, bestScore = Infinity;
      focusables(document).forEach(function (el) {
        if (el === cur) return;
        var b = el.getBoundingClientRect();
        var bx = b.left + b.width / 2, by = b.top + b.height / 2;
        var dx = bx - cx, dy = by - cy;
        var primary, secondary, ok = false;
        if (dir === 'right') { ok = dx > 1; primary = dx; secondary = Math.abs(dy); }
        else if (dir === 'left') { ok = dx < -1; primary = -dx; secondary = Math.abs(dy); }
        else if (dir === 'down') { ok = dy > 1; primary = dy; secondary = Math.abs(dx); }
        else if (dir === 'up') { ok = dy < -1; primary = -dy; secondary = Math.abs(dx); }
        if (!ok) return;
        var horizontal = dir === 'left' || dir === 'right';
        var crossSize = horizontal ? r.height : r.width;
        var aligned = secondary <= crossSize * 0.6;
        var score = primary + secondary * (aligned ? 1.2 : 3.0) + (aligned ? 0 : 400);
        if (score < bestScore) { bestScore = score; best = el; }
      });
      if (best) {
        best.focus();
        best.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' });
      }
    }
  };

  // ---- global keys ----
  var KEY = { LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13, BACK: 461, ESC: 27, BACKSPACE: 8 };
  document.addEventListener('keydown', function (e) {
    var code = e.keyCode || e.which;
    // player intercepts media/navigation keys while active
    if (CC.player && CC.player.active && CC.player.active() && CC.player.onKey) {
      if (CC.player.onKey(e, code) === true) { e.preventDefault(); return; }
    }
    var el = document.activeElement;
    var typing = el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);

    if (code === KEY.BACK || code === KEY.ESC || (code === KEY.BACKSPACE && !typing)) {
      e.preventDefault();
      if (typing && code === KEY.ESC) { el.blur(); return; }
      CC.nav.back();
      return;
    }
    if (typing) {
      if (code === KEY.ENTER) { /* let form/submit handlers run */ }
      return;
    }
    if (code === KEY.LEFT) { e.preventDefault(); CC.focus.move('left'); }
    else if (code === KEY.RIGHT) { e.preventDefault(); CC.focus.move('right'); }
    else if (code === KEY.UP) { e.preventDefault(); CC.focus.move('up'); }
    else if (code === KEY.DOWN) { e.preventDefault(); CC.focus.move('down'); }
    else if (code === KEY.ENTER) {
      var cur = CC.focus.current();
      if (cur) { e.preventDefault(); cur.click(); }
    }
  });

  // mouse support for desktop testing
  document.addEventListener('click', function (e) {
    var f = e.target.closest ? e.target.closest('.focusable') : null;
    if (f && document.activeElement !== f) f.focus();
  });
})();