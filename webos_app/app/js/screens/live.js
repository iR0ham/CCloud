/* Live TV: country picker (Iran first) → channel list → playback. */
(function () {
  CC.screens.live = {
    render: function (container) {
      container.innerHTML = CC.ui.loadingHTML('در حال دریافت شبکه‌های زنده…');
      CC.live.countries().then(function (countries) {
        var selected = null;
        for (var i = 0; i < countries.length; i++) if (countries[i].code === 'IR') { selected = countries[i]; break; }
        if (!selected) selected = countries[0];
        var allChannels = [];

        container.innerHTML =
          CC.ui.pageHead('پخش زنده', 'شبکه‌های تلویزیونی از سراسر جهان') +
          '<div class="live-countries" id="live-countries"></div>' +
          '<div class="live-bar">' +
            '<input id="live-search" class="search-input focusable" type="text" autocomplete="off" placeholder="جست‌وجوی شبکه…" aria-label="جست‌وجوی شبکه">' +
            '<span class="live-count" id="live-count"></span>' +
          '</div>' +
          '<div class="live-channels" id="live-channels"></div>';

        var countryHost = container.querySelector('#live-countries');
        var channelHost = container.querySelector('#live-channels');
        var searchInput = container.querySelector('#live-search');
        var countEl = container.querySelector('#live-count');

        function paintCountries() {
          countryHost.innerHTML = countries.map(function (c, i) {
            var active = selected && c.code === selected.code;
            return '<button class="live-country chip focusable' + (active ? ' is-active' : '') + '" data-country="' + i + '" type="button">' +
              '<span class="live-flag">' + CC.liveFlag(c.code) + '</span>' +
              '<span>' + CC.esc(CC.liveCountryName(c.code, c.englishName)) + '</span>' +
              '<span class="live-cc">' + CC.faDigits(c.channelCount) + '</span></button>';
          }).join('');
          Array.prototype.forEach.call(countryHost.querySelectorAll('[data-country]'), function (chip) {
            chip.addEventListener('click', function () {
              selected = countries[parseInt(chip.getAttribute('data-country'), 10)];
              searchInput.value = '';
              paintCountries();
              loadChannels();
              chip.focus();
            });
          });
        }

        function paintChannels() {
          var q = CC.normalizeSearch(searchInput.value).toLowerCase();
          var list = allChannels.filter(function (ch) {
            if (!q) return true;
            return ch.name.toLowerCase().indexOf(q) >= 0 || ch.languageLabel.indexOf(q) >= 0;
          });
          countEl.textContent = list.length ? CC.faDigits(list.length) + ' شبکه' : '';
          if (!list.length) { channelHost.innerHTML = CC.ui.emptyHTML('شبکه‌ای پیدا نشد'); return; }
          channelHost.innerHTML = list.map(function (ch, i) {
            return '<button class="channel focusable" data-ch="' + i + '" type="button">' +
              '<span class="channel-play">▶</span>' +
              '<span class="channel-text"><span class="channel-name">' + CC.esc(ch.name) + '</span>' +
                '<span class="channel-sub">' + CC.esc(ch.languageLabel) + '</span></span>' +
              (ch.isGeoBlocked ? '<span class="badge badge-geo">محدود جغرافیایی</span>' : '') +
            '</button>';
          }).join('');
          Array.prototype.forEach.call(channelHost.querySelectorAll('[data-ch]'), function (row) {
            row.addEventListener('click', function () {
              var ch = list[parseInt(row.getAttribute('data-ch'), 10)];
              if (!ch || !ch.primaryStream) { CC.ui.toast('استریمی برای این شبکه نیست'); return; }
              CC.player.open({
                live: true, title: ch.name,
                source: { url: ch.primaryStream, kind: 'hls', qualityLabel: 'پخش زنده' },
                channels: list, index: list.indexOf(ch)
              });
            });
          });
        }

        function loadChannels() {
          channelHost.innerHTML = CC.ui.loadingHTML('در حال دریافت شبکه‌ها…');
          CC.live.channels(selected.code).then(function (channels) {
            allChannels = channels;
            paintChannels();
          }).catch(function (err) {
            allChannels = [];
            channelHost.innerHTML = CC.ui.errorHTML(err && err.message);
            CC.ui.bindRetry(channelHost, loadChannels);
          });
        }

        searchInput.addEventListener('input', CC.debounce(paintChannels, 200));
        searchInput.addEventListener('keydown', function (e) { if ((e.keyCode || e.which) === 13) { e.preventDefault(); paintChannels(); searchInput.blur(); } });

        paintCountries();
        loadChannels();
      }).catch(function (err) {
        container.innerHTML = CC.ui.errorHTML(err && err.message);
        CC.ui.bindRetry(container, function () { CC.nav.replace('live'); });
        CC.focus.first(container);
      });
    },
    focusFirst: function (container) {
      var c = container.querySelector('.live-country.is-active') || container.querySelector('.focusable');
      if (c) { c.focus(); c.scrollIntoView({ block: 'nearest', inline: 'nearest' }); }
    }
  };
})();