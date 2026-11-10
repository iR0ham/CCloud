/* Favorites and watch history libraries. */
(function () {
  function gridScreen(name, title, subtitle, getItems, opts) {
    opts = opts || {};
    CC.screens[name] = {
      render: function (container) {
        function paint() {
          var items = getItems();
          var headRight = items.length
            ? '<button class="btn btn-ghost focusable" data-clear type="button">' + CC.esc(opts.clearLabel || 'پاک‌کردن همه') + '</button>'
            : '';
          if (!items.length) {
            container.innerHTML = CC.ui.pageHead(title, subtitle) + CC.ui.emptyHTML(opts.emptyMsg || 'چیزی اینجا نیست', opts.emptyHint);
            CC.focus.first(container);
            return;
          }
          var cards = items.map(function (it, i) {
            var entry = opts.progress ? CC.history.entryFor(it) : null;
            return CC.ui.posterHTML(it, i, { progress: entry ? entry.progress : 0 });
          }).join('');
          container.innerHTML = CC.ui.pageHead(title, subtitle, headRight) + '<div class="feed-grid">' + cards + '</div>';
          CC.ui.bindPosters(container, items, function (item) { CC.nav.go('detail', { item: item, resume: !!opts.progress }); });
          var clear = container.querySelector('[data-clear]');
          if (clear) clear.addEventListener('click', function () {
            opts.clear();
            CC.ui.toast(opts.clearToast || 'پاک شد');
            paint();
          });
          CC.focus.first(container);
        }
        paint();
        if (opts.subscribe) opts.subscribe(function () {
          var cur = CC.nav.current();
          if (cur && cur.name === name) paint();
        });
      }
    };
  }

  gridScreen('favorites', 'علاقه‌مندی‌ها', 'فیلم‌ها و سریال‌های نشان‌شده',
    function () { return CC.favorites.entries().map(function (e) { return e.item; }); },
    {
      clearLabel: 'پاک‌کردن همه', emptyMsg: 'هنوز علاقه‌مندی ندارید',
      emptyHint: 'در صفحهٔ هر عنوان، دکمهٔ علاقه‌مندی را بزنید.',
      clear: function () { CC.favorites.clear(); }, clearToast: 'علاقه‌مندی‌ها پاک شد',
      subscribe: function (fn) { CC.favorites.onChange(fn); }
    });

  gridScreen('history', 'تاریخچهٔ تماشا', 'ادامهٔ آنچه دیده‌اید',
    function () { return CC.history.entries().map(function (e) { return e.item; }); },
    {
      progress: true, clearLabel: 'پاک‌کردن تاریخچه', emptyMsg: 'تاریخچه‌ای نیست',
      emptyHint: 'هرچه پخش کنید اینجا ثبت می‌شود.',
      clear: function () { CC.history.clear(); }, clearToast: 'تاریخچه پاک شد',
      subscribe: function (fn) { CC.history.onChange(fn); }
    });
})();