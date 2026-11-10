/* Countries index + per-country poster feed. */
(function () {
  CC.screens.countries = {
    render: function (container) {
      container.innerHTML = CC.ui.loadingHTML('در حال دریافت کشورها…');
      CC.api.countries().then(function (countries) {
        if (!countries.length) { container.innerHTML = CC.ui.emptyHTML('کشوری پیدا نشد'); return; }
        var cards = countries.map(function (c, i) {
          var image = CC.api.imageUrl(c.image) || 'assets/img/logo-dark.png';
          return '<button class="country-card focusable" data-idx="' + i + '" type="button">' +
            '<span class="country-art">' + CC.ui.img(image, 'country-img', c.title) + '<span class="country-shade"></span></span>' +
            '<span class="country-name">' + CC.esc(c.title) + '</span></button>';
        }).join('');
        container.innerHTML = CC.ui.pageHead('کشورها', 'فیلم‌ها و سریال‌های هر کشور') + '<div class="country-grid">' + cards + '</div>';
        Array.prototype.forEach.call(container.querySelectorAll('.country-card'), function (el) {
          el.addEventListener('click', function () {
            var c = countries[parseInt(el.getAttribute('data-idx'), 10)];
            if (c) CC.nav.go('country', { countryId: c.id, title: c.title });
          });
        });
        CC.focus.first(container);
      }).catch(function (err) {
        container.innerHTML = CC.ui.errorHTML(err && err.message);
        CC.ui.bindRetry(container, function () { CC.nav.replace('countries'); });
        CC.focus.first(container);
      });
    }
  };

  CC.screens.country = {
    render: function (container, params) {
      params = params || {};
      var state = { sort: 'created' };
      var controls = '<div class="feed-controls"><div class="control-group"><span class="control-label">مرتب‌سازی</span>' +
        CC.ui.chipsHTML(CC.api.sorts, state.sort, 'sort') + '</div></div>';
      CC.renderFeed(container, {
        title: params.title || 'کشور',
        subtitle: 'فیلم‌ها و سریال‌های این کشور',
        controls: controls,
        emptyMsg: 'موردی برای این کشور پیدا نشد',
        load: function (page) { return CC.api.countryPosters({ countryId: params.countryId, page: page, sort: state.sort }); },
        bindControls: function (c, reload) {
          Array.prototype.forEach.call(c.querySelectorAll('[data-sort]'), function (chip) {
            chip.addEventListener('click', function () {
              state.sort = chip.getAttribute('data-sort');
              Array.prototype.forEach.call(c.querySelectorAll('[data-sort]'), function (x) { x.classList.toggle('is-active', x === chip); });
              reload();
            });
          });
        }
      });
    }
  };
})();