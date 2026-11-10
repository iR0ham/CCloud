/* Paginated poster grid used by browse / country / search feeds. */
(function () {
  CC.renderFeed = function (container, opts) {
    var page = 0, items = [], loading = false, done = false, started = false;
    var filter = opts.filter || function (x) { return x; };
    var onOpen = opts.onOpen || function (item) { CC.nav.go('detail', { item: item }); };

    container.innerHTML =
      CC.ui.pageHead(opts.title, opts.subtitle, opts.headRight || '') +
      (opts.controls || '') +
      '<div class="feed-grid" id="feed-grid"></div>' +
      '<div class="feed-foot" id="feed-foot"></div>';

    var grid = container.querySelector('#feed-grid');
    var foot = container.querySelector('#feed-foot');

    function paint() {
      grid.innerHTML = items.map(function (it, i) { return CC.ui.posterHTML(it, i, opts.cardOpts || {}); }).join('');
      CC.ui.bindPosters(grid, items, onOpen);
      if (opts.afterPaint) opts.afterPaint(grid, items);
      foot.innerHTML = done
        ? (items.length ? '<p class="feed-end">— پایان فهرست —</p>' : '')
        : '<button class="btn btn-ghost focusable" id="feed-more" type="button">' + (loading ? 'در حال بارگذاری…' : 'نمایش بیشتر') + '</button>';
      var more = foot.querySelector('#feed-more');
      if (more) { more.disabled = loading; more.addEventListener('click', loadMore); }
      if (!items.length && done) {
        grid.innerHTML = CC.ui.emptyHTML(opts.emptyMsg || 'موردی پیدا نشد');
      }
    }

    function loadMore() {
      if (loading || done) return;
      loading = true;
      if (items.length) paint();
      else grid.innerHTML = CC.ui.loadingHTML(opts.loadingMsg || 'در حال دریافت…');
      opts.load(page).then(function (raw) {
        var batch = filter(raw || []);
        // de-dupe against existing
        var seen = {};
        items.forEach(function (it) { seen[it.type + ':' + it.id] = true; });
        batch.forEach(function (it) { var k = it.type + ':' + it.id; if (!seen[k]) { seen[k] = true; items.push(it); } });
        if (!raw || raw.length === 0) done = true;
        else page += 1;
        if (opts.singlePage) done = true;
        loading = false;
        paint();
        if (!started) { started = true; CC.focus.first(container); }
      }).catch(function (err) {
        loading = false;
        if (!items.length) {
          grid.innerHTML = CC.ui.errorHTML(err && err.message);
          CC.ui.bindRetry(grid, function () { done = false; loadMore(); });
          foot.innerHTML = '';
          CC.focus.first(container);
        } else {
          done = true; paint();
          CC.ui.toast(err && err.message ? err.message : 'خطا در بارگذاری');
        }
      });
    }

    if (opts.bindControls) opts.bindControls(container, function reload() { page = 0; items = []; done = false; started = false; loadMore(); });
    loadMore();
    return { reload: function () { page = 0; items = []; done = false; started = false; loadMore(); } };
  };
})();