/* Shared helpers + global namespace. Plain ES2017 (webOS 4+ / Chromium 68). */
window.CC = window.CC || {};

(function () {
  var FA = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  CC.faDigits = function (value) {
    return String(value).replace(/[0-9]/g, function (d) { return FA[+d]; });
  };

  CC.esc = function (s) {
    if (s === null || s === undefined) return '';
    return String(s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  };

  CC.clamp = function (v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); };

  CC.fmtTime = function (sec) {
    if (!isFinite(sec) || sec < 0) sec = 0;
    sec = Math.floor(sec);
    var h = Math.floor(sec / 3600);
    var m = Math.floor((sec % 3600) / 60);
    var s = sec % 60;
    var mm = (m < 10 && h > 0 ? '0' : '') + m;
    var ss = (s < 10 ? '0' : '') + s;
    return CC.faDigits(h > 0 ? h + ':' + mm + ':' + ss : m + ':' + ss);
  };

  CC.debounce = function (fn, ms) {
    var t = null;
    return function () {
      var args = arguments, self = this;
      if (t) clearTimeout(t);
      t = setTimeout(function () { t = null; fn.apply(self, args); }, ms);
    };
  };

  // ---- persistent storage (localStorage; survives app relaunch on webOS) ----
  var PREFIX = 'ccloud.';
  CC.store = {
    get: function (key, fallback) {
      try {
        var raw = localStorage.getItem(PREFIX + key);
        if (raw === null) return fallback;
        return JSON.parse(raw);
      } catch (e) { return fallback; }
    },
    set: function (key, value) {
      try { localStorage.setItem(PREFIX + key, JSON.stringify(value)); } catch (e) {}
    },
    remove: function (key) {
      try { localStorage.removeItem(PREFIX + key); } catch (e) {}
    }
  };

  CC.normalizeSearch = function (raw) {
    var text = String(raw || '')
      .replace(/\u064A/g, '\u06CC').replace(/\u0643/g, '\u06A9')
      .replace(/\u200E/g, '').replace(/\u200F/g, '')
      .replace(/[\/\\]/g, ' ').replace(/\u0000/g, '');
    text = text.split(/\s+/).filter(function (e) { return e.length; }).join(' ');
    return text.length > 120 ? text.substring(0, 120) : text;
  };

  CC.uid = function () { return Date.now().toString(36) + Math.random().toString(36).slice(2, 7); };

  // True when running inside a packaged webOS app (vs. desktop browser dev).
  CC.isWebOS = function () {
    return !!(window.webOS && window.webOS.service) ||
      /Web0S|webOS|WebAppManager/i.test(navigator.userAgent) ||
      window.location.protocol === 'file:';
  };
})();