/* Persistent settings, favorites and watch history (localStorage). */
(function () {
  function listeners() {
    var fns = [];
    return {
      add: function (fn) { fns.push(fn); },
      fire: function () { fns.forEach(function (fn) { try { fn(); } catch (e) {} }); }
    };
  }

  // ---- settings ----
  var DEFAULTS = {
    appearance: 'dark', fontScale: 1.0, preferredQuality: 'auto',
    autoPlayBest: true, autoPlayNextEpisode: true,
    hideRegionalOrigins: false, hideAnime: false
  };
  var settings = Object.assign({}, DEFAULTS, CC.store.get('settings', {}));
  settings.fontScale = CC.clamp(Number(settings.fontScale) || 1, 0.85, 1.3);
  var settingsChanged = listeners();

  function saveSettings() { CC.store.set('settings', settings); settingsChanged.fire(); }

  CC.settings = {
    qualityOptions: [
      { key: 'auto', title: 'خودکار (بهترین)' },
      { key: '1080', title: '۱۰۸۰p' },
      { key: '720', title: '۷۲۰p' },
      { key: '480', title: '۴۸۰p' }
    ],
    appearanceOptions: [
      { key: 'system', title: 'هماهنگ با سیستم' },
      { key: 'dark', title: 'تیره' },
      { key: 'light', title: 'روشن' }
    ],
    get: function (k) { return settings[k]; },
    all: function () { return Object.assign({}, settings); },
    set: function (k, v) {
      if (k === 'fontScale') v = CC.clamp(Number(v) || 1, 0.85, 1.3);
      settings[k] = v; saveSettings(); CC.applyAppearance();
    },
    reset: function () { settings = Object.assign({}, DEFAULTS); saveSettings(); CC.applyAppearance(); },
    onChange: function (fn) { settingsChanged.add(fn); }
  };

  CC.applyAppearance = function () {
    var mode = settings.appearance;
    if (mode === 'system') {
      mode = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
    }
    document.documentElement.setAttribute('data-theme', mode === 'light' ? 'light' : 'dark');
    document.documentElement.style.setProperty('--font-scale', String(settings.fontScale));
  };

  // ---- favorites ----
  var favEntries = (CC.store.get('favorites', []) || []).filter(function (e) { return e && e.item; });
  var favChanged = listeners();
  function saveFav() { CC.store.set('favorites', favEntries); favChanged.fire(); }
  function sameItem(a, b) { return a.id === b.id && !!a.isSeries === !!b.isSeries; }

  CC.favorites = {
    entries: function () { return favEntries.slice(); },
    movies: function () { return favEntries.filter(function (e) { return !e.item.isSeries; }); },
    series: function () { return favEntries.filter(function (e) { return e.item.isSeries; }); },
    count: function () { return favEntries.length; },
    isFavorite: function (item) { return favEntries.some(function (e) { return sameItem(e.item, item); }); },
    toggle: function (item) {
      var idx = -1;
      for (var i = 0; i < favEntries.length; i++) if (sameItem(favEntries[i].item, item)) { idx = i; break; }
      var added = idx < 0;
      if (added) favEntries.unshift({ item: item, addedAt: new Date().toISOString() });
      else favEntries.splice(idx, 1);
      saveFav(); return added;
    },
    remove: function (item) { favEntries = favEntries.filter(function (e) { return !sameItem(e.item, item); }); saveFav(); },
    clear: function () { favEntries = []; saveFav(); },
    onChange: function (fn) { favChanged.add(fn); }
  };

  // ---- history ----
  var histEntries = (CC.store.get('history', []) || []).filter(function (e) { return e && e.item; });
  histEntries.forEach(function (e) { if (!Array.isArray(e.episodes)) e.episodes = []; });
  histEntries.sort(function (a, b) { return new Date(b.lastWatchedAt) - new Date(a.lastWatchedAt); });
  var histChanged = listeners();
  var MAX = 80;
  function saveHist() { CC.store.set('history', histEntries); histChanged.fire(); }

  CC.history = {
    entries: function () { return histEntries.slice(); },
    record: function (item, opt) {
      opt = opt || {};
      if (!item || item.id === 0) return;
      var now = new Date().toISOString();
      var idx = -1;
      for (var i = 0; i < histEntries.length; i++) if (sameItem(histEntries[i].item, item)) { idx = i; break; }
      var entry;
      if (idx >= 0) {
        entry = histEntries[idx];
        entry.lastWatchedAt = now;
        if (typeof opt.progress === 'number') entry.progress = CC.clamp(opt.progress, 0, 1);
        if (item.isSeries && opt.episodeId != null) {
          var ep = null;
          for (var j = 0; j < entry.episodes.length; j++) if (entry.episodes[j].id === opt.episodeId) { ep = entry.episodes[j]; break; }
          if (ep) {
            if (opt.seasonTitle != null) ep.seasonTitle = opt.seasonTitle;
            if (opt.episodeLabel != null) ep.label = opt.episodeLabel;
            ep.watchedAt = now;
            if (typeof opt.progress === 'number') ep.progress = CC.clamp(opt.progress, 0, 1);
          } else {
            entry.episodes.push({
              id: opt.episodeId, seasonTitle: opt.seasonTitle || '', label: opt.episodeLabel || '',
              watchedAt: now, progress: typeof opt.progress === 'number' ? CC.clamp(opt.progress, 0, 1) : 0
            });
          }
        }
        histEntries.splice(idx, 1);
        histEntries.unshift(entry);
      } else {
        entry = {
          item: item, lastWatchedAt: now,
          progress: typeof opt.progress === 'number' ? CC.clamp(opt.progress, 0, 1) : 0,
          episodes: (item.isSeries && opt.episodeId != null) ? [{
            id: opt.episodeId, seasonTitle: opt.seasonTitle || '', label: opt.episodeLabel || '',
            watchedAt: now, progress: typeof opt.progress === 'number' ? CC.clamp(opt.progress, 0, 1) : 0
          }] : []
        };
        histEntries.unshift(entry);
      }
      if (histEntries.length > MAX) histEntries.length = MAX;
      saveHist();
    },
    entryFor: function (item) {
      for (var i = 0; i < histEntries.length; i++) if (sameItem(histEntries[i].item, item)) return histEntries[i];
      return null;
    },
    watchedEpisodeIds: function (seriesId) {
      for (var i = 0; i < histEntries.length; i++) {
        var e = histEntries[i];
        if (e.item.isSeries && e.item.id === seriesId) return e.episodes.map(function (ep) { return ep.id; });
      }
      return [];
    },
    remove: function (item) { histEntries = histEntries.filter(function (e) { return !sameItem(e.item, item); }); saveHist(); },
    clear: function () { histEntries = []; saveHist(); },
    onChange: function (fn) { histChanged.add(fn); }
  };
})();