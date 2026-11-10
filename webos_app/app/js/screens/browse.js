/* Browse feed: movies or series, with genre + sort filters. */
(function () {
  CC.screens.browse = {
    render: function (container, params) {
      params = params || {};
      var kind = params.kind === 'serie' ? 'serie' : 'movie';
      var state = { genreId: params.genreId || 0, sort: 'created' };
      container.innerHTML = CC.ui.loadingHTML('در حال دریافت فهرست…');

      CC.api.genres().catch(function () { return []; }).then(function (genres) {
        var title = params.genreTitle || (kind === 'serie' ? 'سریال‌ها' : 'فیلم‌ها');
        var genreOptions = [{ id: 0, title: 'همه' }].concat(genres);
        var controls =
          '<div class="feed-controls">' +
            '<div class="control-group"><span class="control-label">ژانر</span>' + CC.ui.chipsHTML(genreOptions, state.genreId, 'genre') + '</div>' +
            '<div class="control-group"><span class="control-label">مرتب‌سازی</span>' + CC.ui.chipsHTML(CC.api.sorts, state.sort, 'sort') + '</div>' +
          '</div>';

        CC.renderFeed(container, {
          title: title,
          subtitle: kind === 'serie' ? 'مرور سریال‌های کاتالوگ' : 'مرور فیلم‌های کاتالوگ',
          controls: controls,
          emptyMsg: 'موردی با این فیلتر پیدا نشد',
          load: function (page) {
            var fn = kind === 'serie' ? CC.api.series : CC.api.movies;
            return fn({ page: page, genreId: state.genreId, sort: state.sort });
          },
          filter: function (items) { return CC.applyFeedFilter(items, CC.settings.all()); },
          bindControls: function (c, reload) {
            Array.prototype.forEach.call(c.querySelectorAll('[data-genre]'), function (chip) {
              chip.addEventListener('click', function () {
                state.genreId = parseInt(chip.getAttribute('data-genre'), 10) || 0;
                setActive(c, 'genre', state.genreId);
                reload();
              });
            });
            Array.prototype.forEach.call(c.querySelectorAll('[data-sort]'), function (chip) {
              chip.addEventListener('click', function () {
                state.sort = chip.getAttribute('data-sort');
                setActive(c, 'sort', state.sort);
                reload();
              });
            });
          }
        });
      });
    }
  };

  function setActive(scope, attr, value) {
    Array.prototype.forEach.call(scope.querySelectorAll('[data-' + attr + ']'), function (chip) {
      chip.classList.toggle('is-active', String(chip.getAttribute('data-' + attr)) === String(value));
    });
  }
})();