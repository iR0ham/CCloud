/* Catalog API client + data normalisation + live-TV dataset. Mirrors the Flutter
 * app's ApiClient / LiveTvClient / models so behaviour and Persian copy match. */
(function () {
  var HOSTS = ['server-hi-speed-iran.info', 'hostinnegar.com', 'windowsdiba.info'];
  var KEY = '4F5A9C3D9A86FA54EACEDDD635185';
  var KNOWN = {};
  HOSTS.forEach(function (h) { KNOWN[h] = true; KNOWN['www.' + h] = true; });
  var CACHE_TTL = 75000;
  var cache = {};
  var inFlight = {};
  var preferred = 0;
  var activeHost = HOSTS[0];

  function asInt(v) {
    if (typeof v === 'number') return Math.round(v);
    var n = parseInt(v, 10); return isNaN(n) ? 0 : n;
  }
  function asNum(v) { var n = parseFloat(v); return isNaN(n) ? 0 : n; }
  function asStr(v) { return v === null || v === undefined ? '' : String(v); }
  function asNullable(v) {
    if (v === null || v === undefined) return null;
    var s = String(v).trim();
    if (!s || s.toLowerCase() === 'null') return null;
    return s;
  }

  function normGenre(j) { return { id: asInt(j.id), title: asStr(j.title) }; }
  function normCountry(j) { return { id: asInt(j.id), title: asStr(j.title), image: asStr(j.image) }; }

  function normSource(j) {
    var type = asStr(j.type);
    var t = type.toLowerCase();
    var kind = t.indexOf('mkv') >= 0 || t.indexOf('matroska') >= 0 ? 'mkv'
      : t.indexOf('m3u8') >= 0 || t.indexOf('hls') >= 0 ? 'hls'
      : t.indexOf('mpd') >= 0 || t.indexOf('dash') >= 0 ? 'dash'
      : t.indexOf('mp4') >= 0 || t.indexOf('m4v') >= 0 ? 'mp4' : t;
    var quality = asNullable(j.quality);
    var kindLabel = { mkv: 'MKV', mp4: 'MP4', hls: 'HLS', dash: 'DASH' }[kind] || kind.toUpperCase();
    var qualityLabel = quality && quality !== 'null' ? quality : kindLabel;
    var res = null;
    if (quality) { var m = quality.match(/[0-9]{3,4}/); if (m) { var d = m[0]; res = (d.length === 3 ? d : d.substring(0, 3)) + 'p'; } }
    return {
      id: asInt(j.id), quality: quality, type: type, url: asStr(j.url),
      kind: kind, kindLabel: kindLabel, qualityLabel: qualityLabel,
      resolutionLabel: res, isTrailer: qualityLabel.indexOf('تیزر') >= 0
    };
  }

  function normItem(j) {
    var type = asStr(j.type) || 'movie';
    var isSeries = type.toLowerCase() === 'serie' || type.toLowerCase() === 'series';
    var genres = Array.isArray(j.genres) ? j.genres.filter(function (g) { return g && typeof g === 'object'; }).map(normGenre) : [];
    var sources = Array.isArray(j.sources) ? j.sources.filter(function (s) { return s && typeof s === 'object'; }).map(normSource) : [];
    var countriesRaw = j.country || j.countries;
    var countries = Array.isArray(countriesRaw) ? countriesRaw.filter(function (c) { return c && typeof c === 'object'; }).map(normCountry) : [];
    var year = asInt(j.year);
    var imdb = asNum(j.imdb);
    var playable = sources.filter(function (s) { return s.url && !s.isTrailer; });
    return {
      id: asInt(j.id), type: type, title: asStr(j.title), description: asStr(j.description),
      year: year, imdb: imdb, rating: asNum(j.rating), duration: asNullable(j.duration),
      image: asStr(j.image), cover: asStr(j.cover),
      genres: genres, sources: sources, countries: countries,
      isSeries: isSeries,
      yearText: year > 0 ? String(year) : '',
      imdbText: imdb > 0 ? imdb.toFixed(1) : '',
      genreText: genres.map(function (g) { return g.title; }).join(' • '),
      playableSources: playable,
      hasOnlyTrailer: sources.length > 0 && playable.length === 0,
      raw: j
    };
  }

  function normEpisode(j) {
    var sources = Array.isArray(j.sources) ? j.sources.filter(function (s) { return s && typeof s === 'object'; }).map(normSource) : [];
    var title = asStr(j.title);
    var digits = title.replace(/[^0-9]/g, '');
    return {
      id: asInt(j.id), title: title, description: asNullable(j.description),
      duration: asNullable(j.duration), image: asNullable(j.image), sources: sources,
      episodeNumber: digits ? parseInt(digits, 10) : null,
      playableSources: sources.filter(function (s) { return s.url && !s.isTrailer; })
    };
  }
  function normSeason(j) {
    var eps = Array.isArray(j.episodes) ? j.episodes.filter(function (e) { return e && typeof e === 'object'; }).map(normEpisode) : [];
    return { id: asInt(j.id), title: asStr(j.title), episodes: eps };
  }

  function dedupe(items, keyFn) {
    var seen = {}, out = [];
    items.forEach(function (it) { var k = keyFn(it); if (!seen[k]) { seen[k] = true; out.push(it); } });
    return out;
  }
  function itemKey(m) { return m.type.toLowerCase() + ':' + m.id; }

  function extractList(decoded) {
    if (Array.isArray(decoded)) return decoded;
    if (decoded && typeof decoded === 'object') {
      var keys = ['posters', 'data', 'items', 'results'];
      for (var i = 0; i < keys.length; i++) if (Array.isArray(decoded[keys[i]])) return decoded[keys[i]];
    }
    return null;
  }

  function fetchPath(path, allowCache) {
    if (allowCache !== false) {
      var c = cache[path];
      if (c && Date.now() - c.at <= CACHE_TTL) return Promise.resolve(c.data);
    }
    if (inFlight[path]) return inFlight[path];
    var p = perform(path).then(function (data) {
      if (data.length <= 4000) {
        cache[path] = { data: data, at: Date.now() };
        var keys = Object.keys(cache);
        if (keys.length > 64) {
          keys.sort(function (a, b) { return cache[a].at - cache[b].at; });
          delete cache[keys[0]];
        }
      }
      return data;
    });
    inFlight[path] = p;
    p.then(function () { delete inFlight[path]; }, function () { delete inFlight[path]; });
    return p;
  }

  function perform(path) {
    var order = [];
    for (var i = 0; i < HOSTS.length; i++) order.push((i + preferred) % HOSTS.length);
    var lastErr = new Error('اتصال به سرور برقرار نشد');
    var chain = Promise.reject();
    order.forEach(function (idx) {
      chain = chain.catch(function () {
        return CC.net.getJson('https://' + HOSTS[idx] + path).then(function (decoded) {
          var list = extractList(decoded);
          if (!list) throw new Error('ساختار پاسخ نامعتبر');
          preferred = idx; activeHost = HOSTS[idx];
          return list.filter(function (e) { return e && typeof e === 'object'; });
        }).catch(function (e) { lastErr = e; throw e; });
      });
    });
    return chain.catch(function () { throw lastErr; });
  }

  var SORTS = [
    { key: 'created', title: 'جدیدترین' },
    { key: 'year', title: 'سال ساخت' },
    { key: 'imdb', title: 'امتیاز IMDb' }
  ];

  CC.api = {
    hosts: HOSTS,
    sorts: SORTS,
    get activeHost() { return activeHost; },
    invalidate: function () { cache = {}; },
    genres: function () {
      return fetchPath('/api/genre/all/' + KEY + '/').then(function (l) {
        return dedupe(l.map(normGenre), function (g) { return String(g.id); });
      });
    },
    movies: function (opt) {
      opt = opt || {};
      var page = Math.max(0, opt.page || 0), genre = opt.genreId || 0, sort = opt.sort || 'created';
      return fetchPath('/api/movie/by/filtres/' + genre + '/' + sort + '/' + page + '/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normItem), itemKey); });
    },
    series: function (opt) {
      opt = opt || {};
      var page = Math.max(0, opt.page || 0), genre = opt.genreId || 0, sort = opt.sort || 'created';
      return fetchPath('/api/serie/by/filtres/' + genre + '/' + sort + '/' + page + '/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normItem), itemKey); });
    },
    seasons: function (seriesId) {
      if (seriesId <= 0) return Promise.reject(new Error('شناسه سریال نامعتبر'));
      return fetchPath('/api/season/by/serie/' + seriesId + '/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normSeason), function (s) { return String(s.id); }); });
    },
    search: function (query) {
      var q = CC.normalizeSearch(query);
      if (!q) return Promise.resolve([]);
      return fetchPath('/api/search/' + encodeURIComponent(q) + '/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normItem), itemKey); });
    },
    countries: function () {
      return fetchPath('/api/country/all/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normCountry), function (c) { return String(c.id); }); });
    },
    countryPosters: function (opt) {
      opt = opt || {};
      if (!opt.countryId || opt.countryId <= 0) return Promise.reject(new Error('شناسه کشور نامعتبر'));
      var page = Math.max(0, opt.page || 0), sort = opt.sort || 'created';
      return fetchPath('/api/poster/by/filtres/0/' + opt.countryId + '/' + sort + '/' + page + '/' + KEY + '/')
        .then(function (l) { return dedupe(l.map(normItem), itemKey); });
    },
    healthCheck: function () {
      return fetchPath('/api/genre/all/' + KEY + '/', false).then(function (l) { return l.length > 0; }, function () { return false; });
    },
    imageUrl: function (path) {
      var raw = String(path || '').trim();
      if (!raw) return null;
      var lower = raw.toLowerCase();
      if (lower === 'null' || lower === 'n/a') return null;
      raw = raw.replace(/\\\//g, '/').replace(/[\r\n]/g, '');
      if (raw.indexOf('//') === 0) raw = 'https:' + raw;
      else if (raw.charAt(0) === '/') raw = 'https://' + activeHost + raw;
      else if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) raw = 'https://' + activeHost + '/' + raw;
      raw = raw.replace(/ /g, '%20');
      if (!/^https?:\/\//i.test(raw)) return null;
      var m = raw.match(/^https?:\/\/([^\/]+)/i);
      if (m && KNOWN[m[1].toLowerCase()]) raw = raw.replace(/^https?:\/\/[^\/]+/i, 'https://' + activeHost);
      return raw;
    }
  };

  // ---- source selection / hero ----
  CC.preferredSource = function (sources, preference) {
    var list = (sources || []).filter(function (s) { return s.url && !s.isTrailer; });
    if (!list.length) return null;
    var pref = preference === 'auto' ? '' : preference;
    if (pref) {
      for (var i = 0; i < list.length; i++) if ((list[i].resolutionLabel || '').indexOf(pref) === 0) return list[i];
    }
    var want = ['1080p', '720p', '480p'];
    for (var w = 0; w < want.length; w++) for (var j = 0; j < list.length; j++) if (list[j].resolutionLabel === want[w]) return list[j];
    return list[0];
  };

  CC.mixHeroSlides = function (movies, series) {
    var m = (movies || []).slice(0, 3), s = (series || []).slice(0, 3), out = [];
    for (var i = 0; i < Math.max(m.length, s.length); i++) {
      if (i < m.length) out.push(m[i]);
      if (i < s.length) out.push(s[i]);
    }
    return out.slice(0, 6);
  };

  // ---- regional visibility (movies/series feeds only) ----
  var COUNTRY_TITLES = ['چین', 'کره جنوبی', 'ترکیه', 'هند', 'تایلند', 'ژاپن', 'پاکستان', 'مصر', 'اردن', 'امارات', 'تونس', 'سوریه', 'عراق', 'عربستان', 'قطر', 'کویت', 'لبنان', 'مراکش'];
  var GENRE_TITLES = ['چینی', 'کره ای', 'ترکی', 'هندی', 'ژاپنی', 'چینی ژاپنی'];
  function normTitle(t) {
    return String(t || '').replace(/\u200C/g, ' ').replace(/\u200E/g, '').replace(/\u200F/g, '').split(/\s+/).filter(function (e) { return e.length; }).join(' ');
  }
  CC.origin = {
    hides: function (item) {
      return (item.countries || []).some(function (c) { return COUNTRY_TITLES.indexOf(normTitle(c.title)) >= 0; }) ||
        (item.genres || []).some(function (g) { return GENRE_TITLES.indexOf(normTitle(g.title)) >= 0; });
    },
    hidesAnime: function (item) {
      var jp = (item.countries || []).some(function (c) { return normTitle(c.title) === 'ژاپن'; });
      if (!jp) return false;
      return (item.genres || []).some(function (g) { return normTitle(g.title).indexOf('انیمه') >= 0; });
    }
  };
  CC.applyFeedFilter = function (items, settings) {
    return (items || []).filter(function (it) {
      if (settings.hideRegionalOrigins && CC.origin.hides(it)) return false;
      if (settings.hideAnime && CC.origin.hidesAnime(it)) return false;
      return true;
    });
  };

  // ================= Live TV (Famelack dataset) =================
  var LIVE_BASES = [
    'https://raw.githubusercontent.com/famelack/famelack-channels/main/tv/raw',
    'https://cdn.jsdelivr.net/gh/famelack/famelack-channels@main/tv/raw'
  ];
  var liveCountries = null, liveCountriesAt = 0, liveCountriesPending = null;
  var liveChannels = {}, liveChannelsAt = {}, liveChannelsPending = {};

  function liveGet(path) {
    var lastErr = new Error('اتصال به سرور پخش زنده برقرار نشد');
    var chain = Promise.reject();
    LIVE_BASES.forEach(function (base) {
      chain = chain.catch(function () {
        return CC.net.getJson(base + path).catch(function (e) { lastErr = e; throw e; });
      });
    });
    return chain.catch(function () { throw lastErr; });
  }

  CC.live = {
    countries: function (force) {
      if (!force && liveCountries && Date.now() - liveCountriesAt < 600000) return Promise.resolve(liveCountries);
      if (liveCountriesPending) return liveCountriesPending;
      liveCountriesPending = liveGet('/countries_metadata.json').then(function (decoded) {
        var items = [];
        if (decoded && typeof decoded === 'object') {
          Object.keys(decoded).forEach(function (code) {
            var v = decoded[code];
            if (!v || typeof v !== 'object') return;
            var country = String(v.country || '');
            var count = parseInt(v.channelCount, 10) || 0;
            if (v.hasChannels !== true || count <= 0 || country.length <= 1) return;
            items.push({ code: code.toUpperCase(), englishName: country, channelCount: count });
          });
        }
        if (!items.length) throw new Error('کشوری برای پخش زنده پیدا نشد');
        liveCountries = sortLiveCountries(items);
        liveCountriesAt = Date.now();
        return liveCountries;
      });
      liveCountriesPending.then(null, function () {}).then(function () { liveCountriesPending = null; });
      return liveCountriesPending;
    },
    channels: function (code, force) {
      code = String(code || '').toLowerCase();
      if (!force && liveChannels[code] && Date.now() - (liveChannelsAt[code] || 0) < 300000) return Promise.resolve(liveChannels[code]);
      if (liveChannelsPending[code]) return liveChannelsPending[code];
      liveChannelsPending[code] = liveGet('/countries/' + code + '.json').then(function (decoded) {
        if (!Array.isArray(decoded)) throw new Error('فهرست شبکه‌ها نامعتبر بود');
        var items = decoded.filter(function (e) { return e && typeof e === 'object'; }).map(normChannel)
          .filter(function (c) { return c.streams.length; });
        items.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1; });
        if (!items.length) throw new Error('شبکه‌ای برای این کشور پیدا نشد');
        liveChannels[code] = items; liveChannelsAt[code] = Date.now();
        return items;
      });
      liveChannelsPending[code].then(null, function () {}).then(function () { delete liveChannelsPending[code]; });
      return liveChannelsPending[code];
    }
  };

  function normChannel(j) {
    var urls = [];
    if (j.sources && Array.isArray(j.sources.streams)) {
      urls = j.sources.streams.map(function (e) { return String(e).trim(); }).filter(function (e) { return e.length; });
    }
    var langs = Array.isArray(j.languages) ? j.languages.map(function (e) { return String(e); }) : [];
    var primary = '';
    for (var i = 0; i < urls.length; i++) if (urls[i].toLowerCase().indexOf('.m3u8') >= 0) { primary = urls[i]; break; }
    if (!primary) primary = urls[0] || '';
    var name = asStr(j.name), country = asStr(j.country), nanoid = asStr(j.nanoid);
    var langLabels = langs.map(persianLanguage).filter(function (e) { return e.length; });
    return {
      nanoid: nanoid, name: name, streams: urls, languages: langs, country: country,
      isGeoBlocked: j.isGeoBlocked === true,
      stringId: nanoid || (name + '-' + country),
      primaryStream: primary,
      languageLabel: langLabels.length ? langLabels.join('، ') : 'نامشخص'
    };
  }

  function rank(code) { return code === 'IR' ? 0 : code === 'AF' ? 1 : code === 'TJ' ? 2 : 3; }
  function sortLiveCountries(items) {
    return items.slice().sort(function (a, b) {
      var l = rank(a.code), r = rank(b.code);
      if (l !== r) return l - r;
      if (a.channelCount !== b.channelCount) return b.channelCount - a.channelCount;
      return persianCountry(a.code, a.englishName) < persianCountry(b.code, b.englishName) ? -1 : 1;
    });
  }

  function persianLanguage(code) {
    var map = {
      fas: 'فارسی', fa: 'فارسی', kur: 'کردی', ckb: 'کردی', ara: 'عربی', ar: 'عربی',
      eng: 'انگلیسی', en: 'انگلیسی', tur: 'ترکی', tr: 'ترکی', aze: 'آذری', az: 'آذری',
      pus: 'پشتو', ps: 'پشتو', urd: 'اردو', ur: 'اردو', rus: 'روسی', ru: 'روسی',
      deu: 'آلمانی', ger: 'آلمانی', de: 'آلمانی', fra: 'فرانسوی', fre: 'فرانسوی', fr: 'فرانسوی',
      spa: 'اسپانیایی', es: 'اسپانیایی', ita: 'ایتالیایی', it: 'ایتالیایی', por: 'پرتغالی', pt: 'پرتغالی',
      hin: 'هندی', hi: 'هندی', zho: 'چینی', chi: 'چینی', zh: 'چینی', jpn: 'ژاپنی', ja: 'ژاپنی',
      kor: 'کره‌ای', ko: 'کره‌ای', ben: 'بنگالی', bn: 'بنگالی', heb: 'عبری', he: 'عبری'
    };
    return map[String(code || '').toLowerCase()] || code;
  }

  var COUNTRY_FA = {
    IR: 'ایران', AF: 'افغانستان', TJ: 'تاجیکستان', US: 'امریکا', GB: 'انگلستان', UK: 'انگلستان', DE: 'آلمان', TR: 'ترکیه',
    IQ: 'عراق', AE: 'امارات', SA: 'عربستان', QA: 'قطر', KW: 'کویت', OM: 'عمان', BH: 'بحرین', YE: 'یمن', SY: 'سوریه', LB: 'لبنان',
    JO: 'اردن', PS: 'فلسطین', EG: 'مصر', LY: 'لیبی', TN: 'تونس', DZ: 'الجزایر', MA: 'مراکش', SD: 'سودان', SO: 'سومالی',
    IN: 'هند', PK: 'پاکستان', BD: 'بنگلادش', LK: 'سریلانکا', NP: 'نپال', CN: 'چین', JP: 'ژاپن', KR: 'کره جنوبی',
    KP: 'کره شمالی', TW: 'تایوان', HK: 'هنگ‌کنگ', TH: 'تایلند', VN: 'ویتنام', ID: 'اندونزی', MY: 'مالزی', SG: 'سنگاپور',
    PH: 'فیلیپین', MM: 'میانمار', KH: 'کامبوج', LA: 'لائوس', MN: 'مغولستان', KZ: 'قزاقستان', UZ: 'ازبکستان', TM: 'ترکمنستان',
    KG: 'قرقیزستان', AZ: 'آذربایجان', AM: 'ارمنستان', GE: 'گرجستان', RU: 'روسیه', UA: 'اوکراین', BY: 'بلاروس', PL: 'لهستان',
    CZ: 'چک', SK: 'اسلواکی', HU: 'مجارستان', RO: 'رومانی', BG: 'بلغارستان', RS: 'صربستان', HR: 'کرواسی', SI: 'اسلوونی',
    BA: 'بوسنی', ME: 'مونته‌نگرو', MK: 'مقدونیه', AL: 'آلبانی', GR: 'یونان', IT: 'ایتالیا', ES: 'اسپانیا', PT: 'پرتغال',
    FR: 'فرانسه', BE: 'بلژیک', NL: 'هلند', LU: 'لوکزامبورگ', CH: 'سوئیس', AT: 'اتریش', DK: 'دانمارک', SE: 'سوئد',
    NO: 'نروژ', FI: 'فنلاند', IS: 'ایسلند', IE: 'ایرلند', EE: 'استونی', LV: 'لتونی', LT: 'لیتوانی', MD: 'مولداوی',
    CA: 'کانادا', MX: 'مکزیک', BR: 'برزیل', AR: 'آرژانتین', CL: 'شیلی', PE: 'پرو', CO: 'کلمبیا', VE: 'ونزوئلا',
    EC: 'اکوادور', BO: 'بولیوی', PY: 'پاراگوئه', UY: 'اروگوئه', CR: 'کاستاریکا', PA: 'پاناما', GT: 'گواتمالا', HN: 'هندوراس',
    SV: 'السالوادور', NI: 'نیکاراگوئه', CU: 'کوبا', DO: 'دومینیکن', HT: 'هائیتی', JM: 'جامائیکا', AU: 'استرالیا', NZ: 'نیوزیلند',
    ZA: 'آفریقای جنوبی', NG: 'نیجریه', KE: 'کنیا', ET: 'اتیوپی', GH: 'غنا', SN: 'سنگال', CI: 'ساحل عاج', CM: 'کامرون',
    UG: 'اوگاندا', TZ: 'تانزانیا', MZ: 'موزامبیک', ZW: 'زیمبابوه', AO: 'آنگولا', ZM: 'زامبیا', BW: 'بوتسوانا', MU: 'موریس',
    ML: 'مالی', BF: 'بورکینافاسو', NE: 'نیجر', TD: 'چاد', MR: 'موریتانی', GM: 'گامبیا', GN: 'گینه', BJ: 'بنین',
    TG: 'توگو', SL: 'سیرالئون', LR: 'لیبریا', RW: 'رواندا', BI: 'بوروندی', MG: 'ماداگاسکار', MW: 'مالاوی', NA: 'نامیبیا',
    LS: 'لسوتو', SZ: 'اسواتینی', CD: 'کنگو', CG: 'کنگو برازاویل', GA: 'گابن', GQ: 'گینه استوایی', CF: 'آفریقای مرکزی', SS: 'سودان جنوبی'
  };
  function persianCountry(code, english) { return COUNTRY_FA[String(code || '').toUpperCase()] || english; }
  CC.liveCountryName = persianCountry;
  CC.liveFlag = function (code) {
    var aliases = { UK: 'GB', EL: 'GR' };
    var n = (aliases[String(code || '').toUpperCase()] || String(code || '').toUpperCase());
    if (n.length !== 2) return '🏳️';
    var out = '';
    for (var i = 0; i < 2; i++) {
      var c = n.charCodeAt(i);
      if (c < 65 || c > 90) return '🏳️';
      out += String.fromCodePoint(0x1F1E6 + c - 65);
    }
    return out;
  };
})();