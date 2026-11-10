/* Reusable UI builders (HTML strings) + small binding helpers. */
(function () {
  var PLACEHOLDER = 'assets/img/logo-dark.png';

  function img(url, cls, alt) {
    var src = url || PLACEHOLDER;
    return '<img class="' + (cls || '') + '" src="' + CC.esc(src) + '" alt="' + CC.esc(alt || '') + '" loading="lazy" ' +
      'onerror="this.onerror=null;this.src=\'' + PLACEHOLDER + '\';this.classList.add(\'img-fallback\')">';
  }

  function metaBadges(item) {
    var out = '';
    if (item.imdbText) out += '<span class="badge badge-imdb">IMDb ' + CC.faDigits(item.imdbText) + '</span>';
    if (item.yearText) out += '<span class="badge">' + CC.faDigits(item.yearText) + '</span>';
    if (item.isSeries) out += '<span class="badge badge-series">سریال</span>';
    else out += '<span class="badge badge-movie">فیلم</span>';
    return out;
  }

  CC.ui = {
    img: img,
    metaBadges: metaBadges,

    posterHTML: function (item, idx, opts) {
      opts = opts || {};
      var poster = CC.api.imageUrl(item.image) || PLACEHOLDER;
      var progress = typeof opts.progress === 'number' ? CC.clamp(opts.progress, 0, 1) : 0;
      var sub = opts.subtitle || [item.yearText ? CC.faDigits(item.yearText) : '', item.imdbText ? 'IMDb ' + CC.faDigits(item.imdbText) : ''].filter(function (x) { return x; }).join(' • ');
      return '' +
        '<button class="poster focusable" data-idx="' + idx + '" type="button" aria-label="' + CC.esc(item.title) + '">' +
          '<span class="poster-art">' + img(poster, 'poster-img', item.title) +
            '<span class="poster-shade"></span>' +
            (item.isSeries ? '<span class="poster-tag">سریال</span>' : '') +
            (opts.watched ? '<span class="poster-watched">✓</span>' : '') +
            (progress > 0 ? '<span class="poster-progress"><i style="width:' + Math.round(progress * 100) + '%"></i></span>' : '') +
          '</span>' +
          '<span class="poster-title">' + CC.esc(item.title) + '</span>' +
          (sub ? '<span class="poster-sub">' + CC.esc(sub) + '</span>' : '') +
        '</button>';
    },

    bindPosters: function (scope, items, onOpen) {
      Array.prototype.forEach.call(scope.querySelectorAll('.poster'), function (el) {
        el.addEventListener('click', function () {
          var idx = parseInt(el.getAttribute('data-idx'), 10);
          if (items[idx]) onOpen(items[idx], idx);
        });
      });
    },

    railHTML: function (id, title, items, opts) {
      opts = opts || {};
      if (!items || !items.length) return '';
      var cards = items.map(function (it, i) { return CC.ui.posterHTML(it, i, opts.cardOpts || {}); }).join('');
      return '' +
        '<section class="rail" data-rail="' + id + '">' +
          '<div class="rail-head"><h2 class="rail-title">' + CC.esc(title) + '</h2>' +
            (opts.action ? '<button class="rail-action focusable" data-rail-action="' + id + '" type="button">' + CC.esc(opts.action) + '</button>' : '') +
          '</div>' +
          '<div class="rail-track">' + cards + '</div>' +
        '</section>';
    },

    chipsHTML: function (options, activeKey, attr) {
      return '<div class="chips">' + options.map(function (o) {
        var key = o.key !== undefined ? o.key : o.id;
        var label = o.title;
        var active = String(key) === String(activeKey);
        return '<button class="chip focusable' + (active ? ' is-active' : '') + '" type="button" data-' + (attr || 'key') + '="' + CC.esc(key) + '">' + CC.esc(label) + '</button>';
      }).join('') + '</div>';
    },

    loadingHTML: function (msg) {
      return '<div class="state-view"><div class="spinner"></div><p class="state-msg">' + CC.esc(msg || 'در حال بارگذاری…') + '</p></div>';
    },
    errorHTML: function (msg) {
      return '<div class="state-view"><div class="state-icon">⚠️</div><p class="state-msg">' + CC.esc(msg || 'خطایی رخ داد') + '</p>' +
        '<button class="btn btn-primary focusable" data-retry type="button">تلاش دوباره</button></div>';
    },
    emptyHTML: function (msg, hint) {
      return '<div class="state-view"><div class="state-icon">🎬</div><p class="state-msg">' + CC.esc(msg || 'چیزی اینجا نیست') + '</p>' +
        (hint ? '<p class="state-hint">' + CC.esc(hint) + '</p>' : '') + '</div>';
    },
    bindRetry: function (scope, fn) {
      var b = scope.querySelector('[data-retry]');
      if (b) b.addEventListener('click', fn);
    },

    toast: function (msg) {
      var host = document.getElementById('toast');
      if (!host) { host = document.createElement('div'); host.id = 'toast'; document.body.appendChild(host); }
      host.textContent = msg;
      host.classList.add('show');
      clearTimeout(host._t);
      host._t = setTimeout(function () { host.classList.remove('show'); }, 2600);
    },

    pageHead: function (title, subtitle, rightHTML) {
      return '<header class="page-head"><div class="page-head-text">' +
        '<h1 class="page-title">' + CC.esc(title) + '</h1>' +
        (subtitle ? '<p class="page-sub">' + CC.esc(subtitle) + '</p>' : '') +
        '</div>' + (rightHTML || '') + '</header>';
    }
  };

  // graceful image fallback already handled inline; keep focus ring visible after re-render
})();