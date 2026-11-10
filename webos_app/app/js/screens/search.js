/* Search across the catalog. The text field opens the webOS system keyboard. */
(function () {
  CC.screens.search = {
    render: function (container, params) {
      params = params || {};
      container.innerHTML =
        CC.ui.pageHead('جست‌وجو', 'در کل کاتالوگ فیلم و سریال') +
        '<div class="search-bar">' +
          '<input id="search-input" class="search-input focusable" type="text" inputmode="search" autocomplete="off" ' +
            'placeholder="نام فیلم یا سریال…" value="' + CC.esc(params.query || '') + '" aria-label="جست‌وجو">' +
          '<button id="search-go" class="btn btn-primary focusable" type="button">جست‌وجو</button>' +
        '</div>' +
        '<div id="search-results" class="search-results"></div>';

      var input = container.querySelector('#search-input');
      var go = container.querySelector('#search-go');
      var results = container.querySelector('#search-results');
      var lastQuery = '';

      function run() {
        var q = CC.normalizeSearch(input.value);
        if (!q) { results.innerHTML = CC.ui.emptyHTML('چه چیزی می‌خواهید ببینید؟', 'نام فیلم یا سریال را وارد کنید و جست‌وجو را بزنید.'); return; }
        if (q === lastQuery) return;
        lastQuery = q;
        results.innerHTML = CC.ui.loadingHTML('در حال جست‌وجو…');
        CC.api.search(q).then(function (items) {
          if (!items.length) { results.innerHTML = CC.ui.emptyHTML('نتیجه‌ای پیدا نشد', 'عبارت دیگری را امتحان کنید.'); return; }
          results.innerHTML =
            '<p class="result-count">' + CC.faDigits(items.length) + ' نتیجه برای «' + CC.esc(q) + '»</p>' +
            '<div class="feed-grid">' + items.map(function (it, i) { return CC.ui.posterHTML(it, i); }).join('') + '</div>';
          CC.ui.bindPosters(results, items, function (item) { CC.nav.go('detail', { item: item }); });
        }).catch(function (err) {
          lastQuery = '';
          results.innerHTML = CC.ui.errorHTML(err && err.message);
          CC.ui.bindRetry(results, run);
        });
      }

      go.addEventListener('click', run);
      input.addEventListener('keydown', function (e) {
        if ((e.keyCode || e.which) === 13) { e.preventDefault(); run(); input.blur(); }
      });
      if (params.query) { run(); }
      else results.innerHTML = CC.ui.emptyHTML('چه چیزی می‌خواهید ببینید؟', 'نام فیلم یا سریال را وارد کنید و جست‌وجو را بزنید.');
    },
    focusFirst: function (container) {
      var input = container.querySelector('#search-input');
      if (input) input.focus();
    }
  };
})();