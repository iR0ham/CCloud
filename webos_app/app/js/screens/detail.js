/* Detail page: metadata, sources, seasons/episodes, favorite + play. */
(function () {
  CC.screens.detail = {
    render: function (container, params) {
      params = params || {};
      var item = params.item;
      if (!item) { container.innerHTML = CC.ui.emptyHTML('عنوانی انتخاب نشده'); return; }
      var cover = CC.api.imageUrl(item.cover) || CC.api.imageUrl(item.image) || 'assets/img/logo-dark.png';
      var poster = CC.api.imageUrl(item.image) || 'assets/img/logo-dark.png';
      var isFav = CC.favorites.isFavorite(item);
      var hist = CC.history.entryFor(item);

      var playLabel = item.isSeries ? 'پخش سریال' : '▶ پخش';
      if (hist && hist.progress > 0.02 && hist.progress < 0.97) playLabel = '▶ ادامهٔ تماشا';

      container.innerHTML =
        '<div class="detail">' +
          '<div class="detail-backdrop" style="background-image:url(\'' + CC.esc(cover) + '\')"></div>' +
          '<div class="detail-scrim"></div>' +
          '<div class="detail-top">' +
            '<div class="detail-poster">' + CC.ui.img(poster, 'detail-poster-img', item.title) + '</div>' +
            '<div class="detail-info">' +
              '<h1 class="detail-title">' + CC.esc(item.title) + '</h1>' +
              '<div class="detail-badges">' + CC.ui.metaBadges(item) +
                (item.duration ? '<span class="badge">' + CC.esc(item.duration) + '</span>' : '') +
              '</div>' +
              (item.genreText ? '<p class="detail-genres">' + CC.esc(item.genreText) + '</p>' : '') +
              '<div class="detail-actions">' +
                '<button class="btn btn-primary btn-lg focusable" data-play type="button">' + CC.esc(playLabel) + '</button>' +
                '<button class="btn btn-ghost btn-lg focusable" data-fav type="button">' + (isFav ? '✓ نشان‌شده' : '♡ علاقه‌مندی') + '</button>' +
              '</div>' +
              (item.description ? '<p class="detail-desc">' + CC.esc(item.description) + '</p>' : '') +
            '</div>' +
          '</div>' +
          '<div class="detail-body" id="detail-body"></div>' +
        '</div>';

      var body = container.querySelector('#detail-body');
      var favBtn = container.querySelector('[data-fav]');
      favBtn.addEventListener('click', function () {
        var added = CC.favorites.toggle(item);
        favBtn.textContent = added ? '✓ نشان‌شده' : '♡ علاقه‌مندی';
        favBtn.classList.toggle('is-on', added);
        CC.ui.toast(added ? 'به علاقه‌مندی‌ها اضافه شد' : 'از علاقه‌مندی‌ها حذف شد');
      });
      if (isFav) favBtn.classList.add('is-on');

      if (item.isSeries) renderSeries(container, body, item, hist);
      else renderMovie(container, body, item, hist);
    },
    focusFirst: function (container) {
      var b = container.querySelector('[data-play]');
      if (b) { b.focus(); b.scrollIntoView({ block: 'nearest' }); }
    }
  };

  function renderMovie(container, body, item, hist) {
    var sources = item.playableSources;
    var playBtn = container.querySelector('[data-play]');
    if (!sources.length) {
      body.innerHTML = CC.ui.emptyHTML(item.hasOnlyTrailer ? 'فقط تیزر موجود است' : 'منبع پخش موجود نیست');
      playBtn.disabled = true;
      return;
    }
    var selected = CC.preferredSource(sources, CC.settings.get('preferredQuality')) || sources[0];
    body.innerHTML =
      '<h2 class="section-title">کیفیت‌ها و منابع</h2>' +
      '<div class="source-list">' + sources.map(function (s, i) {
        return '<button class="source-chip focusable' + (s === selected ? ' is-active' : '') + '" data-src="' + i + '" type="button">' +
          '<span class="source-q">' + CC.esc(s.qualityLabel) + '</span><span class="source-kind">' + CC.esc(s.kindLabel) + '</span></button>';
      }).join('') + '</div>';

    Array.prototype.forEach.call(body.querySelectorAll('[data-src]'), function (chip) {
      chip.addEventListener('click', function () {
        selected = sources[parseInt(chip.getAttribute('data-src'), 10)];
        Array.prototype.forEach.call(body.querySelectorAll('[data-src]'), function (c) { c.classList.toggle('is-active', c === chip); });
      });
    });

    playBtn.addEventListener('click', function () {
      var startAt = (hist && hist.progress > 0.02 && hist.progress < 0.97) ? hist.progress : 0;
      CC.history.record(item, { progress: startAt });
      CC.player.open({ item: item, source: selected, startFraction: startAt });
    });
  }

  function renderSeries(container, body, item, hist) {
    var playBtn = container.querySelector('[data-play]');
    body.innerHTML = CC.ui.loadingHTML('در حال دریافت فصل‌ها…');
    CC.api.seasons(item.id).then(function (seasons) {
      if (!seasons.length) { body.innerHTML = CC.ui.emptyHTML('فصلی برای این سریال پیدا نشد'); playBtn.disabled = true; return; }
      var activeSeason = 0;
      var watched = CC.history.watchedEpisodeIds(item.id);

      function episodePlaylist(season) {
        return season.episodes.filter(function (e) { return e.playableSources.length; });
      }

      function paintSeason() {
        var season = seasons[activeSeason];
        var eps = season.episodes;
        body.innerHTML =
          '<h2 class="section-title">فصل‌ها و قسمت‌ها</h2>' +
          '<div class="chips season-chips">' + seasons.map(function (s, i) {
            return '<button class="chip focusable' + (i === activeSeason ? ' is-active' : '') + '" data-season="' + i + '" type="button">' + CC.esc(s.title || ('فصل ' + CC.faDigits(i + 1))) + '</button>';
          }).join('') + '</div>' +
          '<div class="episode-list">' + (eps.length ? eps.map(function (ep, i) {
            var isWatched = watched.indexOf(ep.id) >= 0;
            var canPlay = ep.playableSources.length > 0;
            return '<button class="episode focusable' + (isWatched ? ' is-watched' : '') + '" data-ep="' + i + '" type="button"' + (canPlay ? '' : ' disabled') + '>' +
              '<span class="episode-num">' + (ep.episodeNumber != null ? CC.faDigits(ep.episodeNumber) : CC.faDigits(i + 1)) + '</span>' +
              '<span class="episode-text"><span class="episode-title">' + CC.esc(ep.title || ('قسمت ' + CC.faDigits(i + 1))) + '</span>' +
                (ep.duration ? '<span class="episode-sub">' + CC.esc(ep.duration) + '</span>' : '') + '</span>' +
              '<span class="episode-state">' + (isWatched ? '✓ دیده‌شده' : (canPlay ? '▶' : '—')) + '</span>' +
            '</button>';
          }).join('') : '<p class="state-hint">قسمتی برای این فصل نیست</p>') + '</div>';

        Array.prototype.forEach.call(body.querySelectorAll('[data-season]'), function (chip) {
          chip.addEventListener('click', function () {
            activeSeason = parseInt(chip.getAttribute('data-season'), 10);
            paintSeason();
            var first = body.querySelector('[data-season="' + activeSeason + '"]');
            if (first) first.focus();
          });
        });
        Array.prototype.forEach.call(body.querySelectorAll('[data-ep]'), function (row) {
          row.addEventListener('click', function () {
            var ep = eps[parseInt(row.getAttribute('data-ep'), 10)];
            playEpisode(season, ep);
          });
        });
      }

      function playEpisode(season, ep) {
        var src = CC.preferredSource(ep.playableSources, CC.settings.get('preferredQuality'));
        if (!src) { CC.ui.toast('منبع پخش برای این قسمت موجود نیست'); return; }
        var list = episodePlaylist(season);
        var index = list.indexOf(ep);
        CC.history.record(item, { progress: 0, episodeId: ep.id, seasonTitle: season.title, episodeLabel: ep.title });
        CC.player.open({
          item: item, source: src, episode: ep, seasonTitle: season.title,
          playlist: list, index: index < 0 ? 0 : index
        });
      }

      playBtn.addEventListener('click', function () {
        // resume last watched episode, else first playable of first season
        var last = hist && hist.episodes && hist.episodes.length ? hist.episodes[hist.episodes.length - 1] : null;
        if (last) {
          for (var si = 0; si < seasons.length; si++) {
            var found = seasons[si].episodes.filter(function (e) { return e.id === last.id; })[0];
            if (found) { activeSeason = si; paintSeason(); playEpisode(seasons[si], found); return; }
          }
        }
        for (var s = 0; s < seasons.length; s++) {
          var pl = episodePlaylist(seasons[s]);
          if (pl.length) { activeSeason = s; paintSeason(); playEpisode(seasons[s], pl[0]); return; }
        }
        CC.ui.toast('قسمت قابل پخشی پیدا نشد');
      });

      paintSeason();
    }).catch(function (err) {
      body.innerHTML = CC.ui.errorHTML(err && err.message);
      CC.ui.bindRetry(body, function () { CC.nav.replace('detail', { item: item }); });
    });
  }
})();