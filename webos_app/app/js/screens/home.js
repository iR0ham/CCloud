/* Home: cinematic hero + content rails. */
(function () {
  var heroTimer = null;

  CC.screens.home = {
    render: function (container) {
      container.innerHTML = CC.ui.loadingHTML('در حال آماده‌سازی خانه…');
      var settings = CC.settings.all();
      Promise.all([
        CC.api.movies({ page: 0, sort: 'created' }),
        CC.api.series({ page: 0, sort: 'created' }),
        CC.api.genres().catch(function () { return []; })
      ]).then(function (res) {
        var movies = CC.applyFeedFilter(res[0], settings);
        var series = CC.applyFeedFilter(res[1], settings);
        var genres = res[2];
        var slides = CC.mixHeroSlides(movies, series);
        var history = CC.history.entries().slice(0, 12).map(function (e) { return e.item; });

        var html = '<div class="home">';
        html += heroHTML(slides[0], slides);
        html += '<div class="home-rails">';
        if (history.length) html += CC.ui.railHTML('continue', 'ادامهٔ تماشا', history, { action: 'همه', cardOpts: {} });
        html += CC.ui.railHTML('movies', 'تازه‌ترین فیلم‌ها', movies.slice(0, 15), { action: 'همه' });
        html += CC.ui.railHTML('series', 'تازه‌ترین سریال‌ها', series.slice(0, 15), { action: 'همه' });
        var pick = genres.filter(function (g) { return g.id !== 0; }).slice(0, 4);
        pick.forEach(function (g) {
          html += '<section class="rail rail-genre" data-genre="' + g.id + '"><div class="rail-head"><h2 class="rail-title">' + CC.esc(g.title) + '</h2>' +
            '<button class="rail-action focusable" data-genre-more="' + g.id + '" type="button">همه</button></div>' +
            '<div class="rail-track" data-genre-track="' + g.id + '"><div class="rail-loading">در حال بارگذاری…</div></div></section>';
        });
        html += '</div></div>';
        container.innerHTML = html;

        bindHero(container, slides);
        // continue rail progress
        if (history.length) {
          var contRail = container.querySelector('[data-rail="continue"] .rail-track');
          var hitems = CC.history.entries().slice(0, 12);
          contRail.innerHTML = hitems.map(function (e, i) {
            return CC.ui.posterHTML(e.item, i, { progress: e.progress, subtitle: e.item.isSeries ? 'سریال' : '' });
          }).join('');
          CC.ui.bindPosters(contRail, hitems.map(function (e) { return e.item; }), function (item) { CC.nav.go('detail', { item: item, resume: true }); });
        }
        bindRail(container, 'movies', movies, function () { CC.nav.go('browse', { kind: 'movie' }); });
        bindRail(container, 'series', series, function () { CC.nav.go('browse', { kind: 'serie' }); });
        var contAction = container.querySelector('[data-rail-action="continue"]');
        if (contAction) contAction.addEventListener('click', function () { CC.nav.go('history'); });

        // genre rails (lazy)
        pick.forEach(function (g) {
          CC.api.movies({ page: 0, genreId: g.id, sort: 'created' }).then(function (list) {
            list = CC.applyFeedFilter(list, settings).slice(0, 12);
            var track = container.querySelector('[data-genre-track="' + g.id + '"]');
            if (!track) return;
            if (!list.length) { track.innerHTML = '<div class="rail-loading">موردی نیست</div>'; return; }
            track.innerHTML = list.map(function (it, i) { return CC.ui.posterHTML(it, i); }).join('');
            CC.ui.bindPosters(track, list, function (item) { CC.nav.go('detail', { item: item }); });
          }).catch(function () {
            var track = container.querySelector('[data-genre-track="' + g.id + '"]');
            if (track) track.innerHTML = '<div class="rail-loading">خطا در بارگذاری</div>';
          });
          var more = container.querySelector('[data-genre-more="' + g.id + '"]');
          if (more) more.addEventListener('click', function () { CC.nav.go('browse', { kind: 'movie', genreId: g.id, genreTitle: g.title }); });
        });

        startHeroTimer(container, slides);
      }).catch(function (err) {
        container.innerHTML = CC.ui.errorHTML(err && err.message);
        CC.ui.bindRetry(container, function () { CC.nav.replace('home'); });
        CC.focus.first(container);
      });
    },
    focusFirst: function (container) {
      var b = container.querySelector('[data-hero-play]') || container.querySelector('.focusable');
      if (b) { b.focus(); b.scrollIntoView({ block: 'nearest' }); }
    }
  };

  function heroHTML(item, slides) {
    if (!item) return '';
    var cover = CC.api.imageUrl(item.cover) || CC.api.imageUrl(item.image) || 'assets/img/logo-dark.png';
    var dots = slides.map(function (s, i) {
      return '<button class="hero-dot focusable' + (i === 0 ? ' is-active' : '') + '" data-hero-dot="' + i + '" type="button" aria-label="' + CC.esc(s.title) + '"></button>';
    }).join('');
    return '' +
      '<section class="hero" id="hero">' +
        '<div class="hero-bg" id="hero-bg" style="background-image:url(\'' + CC.esc(cover) + '\')"></div>' +
        '<div class="hero-scrim"></div>' +
        '<div class="hero-body">' +
          '<div class="hero-badges" id="hero-badges">' + CC.ui.metaBadges(item) + '</div>' +
          '<h1 class="hero-title" id="hero-title">' + CC.esc(item.title) + '</h1>' +
          '<p class="hero-genres" id="hero-genres">' + CC.esc(item.genreText) + '</p>' +
          '<p class="hero-desc" id="hero-desc">' + CC.esc(item.description || '') + '</p>' +
          '<div class="hero-actions">' +
            '<button class="btn btn-primary btn-lg focusable" data-hero-play type="button">▶ پخش</button>' +
            '<button class="btn btn-ghost btn-lg focusable" data-hero-info type="button">اطلاعات بیشتر</button>' +
          '</div>' +
          '<div class="hero-dots" id="hero-dots">' + dots + '</div>' +
        '</div>' +
      '</section>';
  }

  function setHero(container, slides, idx) {
    var item = slides[idx];
    if (!item) return;
    container._heroIdx = idx;
    var cover = CC.api.imageUrl(item.cover) || CC.api.imageUrl(item.image) || 'assets/img/logo-dark.png';
    var bg = container.querySelector('#hero-bg');
    if (bg) bg.style.backgroundImage = 'url(\'' + cover + '\')';
    var t = container.querySelector('#hero-title'); if (t) t.textContent = item.title;
    var g = container.querySelector('#hero-genres'); if (g) g.textContent = item.genreText;
    var d = container.querySelector('#hero-desc'); if (d) d.textContent = item.description || '';
    var b = container.querySelector('#hero-badges'); if (b) b.innerHTML = CC.ui.metaBadges(item);
    Array.prototype.forEach.call(container.querySelectorAll('.hero-dot'), function (dot, i) {
      dot.classList.toggle('is-active', i === idx);
    });
  }

  function bindHero(container, slides) {
    container._heroIdx = 0;
    function play() {
      var item = slides[container._heroIdx || 0];
      if (!item) return;
      if (item.isSeries) { CC.nav.go('detail', { item: item }); return; }
      var src = CC.preferredSource(item.playableSources, CC.settings.get('preferredQuality'));
      if (!src) { CC.ui.toast(item.hasOnlyTrailer ? 'فقط تیزر برای این عنوان موجود است' : 'منبع پخش موجود نیست'); return; }
      CC.player.open({ item: item, source: src });
    }
    var pb = container.querySelector('[data-hero-play]'); if (pb) pb.addEventListener('click', play);
    var ib = container.querySelector('[data-hero-info]');
    if (ib) ib.addEventListener('click', function () { CC.nav.go('detail', { item: slides[container._heroIdx || 0] }); });
    Array.prototype.forEach.call(container.querySelectorAll('.hero-dot'), function (dot) {
      dot.addEventListener('click', function () {
        stopHeroTimer();
        setHero(container, slides, parseInt(dot.getAttribute('data-hero-dot'), 10));
      });
    });
    var hero = container.querySelector('#hero');
    if (hero) hero.addEventListener('focusin', stopHeroTimer);
  }

  function startHeroTimer(container, slides) {
    stopHeroTimer();
    if (slides.length < 2) return;
    heroTimer = setInterval(function () {
      if (!document.getElementById('hero')) { stopHeroTimer(); return; }
      var next = ((container._heroIdx || 0) + 1) % slides.length;
      setHero(container, slides, next);
    }, 8000);
  }
  function stopHeroTimer() { if (heroTimer) { clearInterval(heroTimer); heroTimer = null; } }

  function bindRail(container, id, items, onMore) {
    var rail = container.querySelector('[data-rail="' + id + '"]');
    if (!rail) return;
    var track = rail.querySelector('.rail-track');
    CC.ui.bindPosters(track, items.slice(0, 15), function (item) { CC.nav.go('detail', { item: item }); });
    var more = rail.querySelector('[data-rail-action="' + id + '"]');
    if (more) more.addEventListener('click', onMore);
  }
})();