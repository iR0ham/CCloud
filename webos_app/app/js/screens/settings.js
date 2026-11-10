/* Settings: appearance, font scale, playback, content hiding, data management. */
(function () {
  CC.screens.settings = {
    render: function (container) {
      var s = CC.settings.all();
      container.innerHTML =
        CC.ui.pageHead('تنظیمات', 'شخصی‌سازی CCloud') +
        '<div class="settings">' +
          section('ظاهر',
            chipRow('حالت ظاهر', 'appearance', CC.settings.appearanceOptions, s.appearance) +
            stepperRow('اندازهٔ قلم', 'fontScale', s.fontScale)) +
          section('پخش',
            chipRow('کیفیت ترجیحی', 'preferredQuality', CC.settings.qualityOptions, s.preferredQuality) +
            toggleRow('پخش خودکار بهترین کیفیت', 'autoPlayBest', s.autoPlayBest) +
            toggleRow('پخش خودکار قسمت بعدی', 'autoPlayNextEpisode', s.autoPlayNextEpisode)) +
          section('نمایش محتوا',
            toggleRow('پنهان‌سازی محتوای منطقه‌ای', 'hideRegionalOrigins', s.hideRegionalOrigins, 'فیلم‌ها و سریال‌های کشورهای منطقه و ژانرهای مرتبط را در فیدها نشان نده.') +
            toggleRow('پنهان‌سازی انیمه', 'hideAnime', s.hideAnime, 'انیمه‌های ژاپنی را در فیدها نشان نده.')) +
          section('داده‌ها',
            actionRow('پاک‌کردن علاقه‌مندی‌ها', 'clear-fav', CC.faDigits(CC.favorites.count()) + ' مورد') +
            actionRow('پاک‌کردن تاریخچه', 'clear-hist', CC.faDigits(CC.history.entries().length) + ' مورد') +
            actionRow('بازنشانی تنظیمات', 'reset', 'بازگشت به پیش‌فرض')) +
          section('درباره',
            '<div class="about-row"><span>نسخه</span><span class="about-val">' + CC.faDigits('1.0.0') + ' · webOS</span></div>' +
            '<div class="about-row"><span>میزبان فعال</span><span class="about-val" id="about-host">' + CC.esc(CC.api.activeHost) + '</span></div>' +
            '<p class="about-note">پورت غیررسمی CCloud برای تلویزیون‌های LG webOS. همان کاتالوگ و منابع نسخهٔ اندروید.</p>') +
        '</div>';

      // chips
      Array.prototype.forEach.call(container.querySelectorAll('[data-chipset]'), function (group) {
        var key = group.getAttribute('data-chipset');
        Array.prototype.forEach.call(group.querySelectorAll('[data-val]'), function (chip) {
          chip.addEventListener('click', function () {
            CC.settings.set(key, chip.getAttribute('data-val'));
            Array.prototype.forEach.call(group.querySelectorAll('[data-val]'), function (c) { c.classList.toggle('is-active', c === chip); });
          });
        });
      });

      // toggles
      Array.prototype.forEach.call(container.querySelectorAll('[data-toggle]'), function (row) {
        var key = row.getAttribute('data-toggle');
        row.addEventListener('click', function () {
          var v = !CC.settings.get(key);
          CC.settings.set(key, v);
          row.classList.toggle('is-on', v);
          row.querySelector('.toggle-state').textContent = v ? 'روشن' : 'خاموش';
        });
      });

      // font scale stepper
      var fsVal = container.querySelector('[data-fs-val]');
      function setFs(v) {
        v = Math.round(CC.clamp(v, 0.85, 1.3) * 100) / 100;
        CC.settings.set('fontScale', v);
        if (fsVal) fsVal.textContent = CC.faDigits(Math.round(v * 100)) + '٪';
      }
      var minus = container.querySelector('[data-fs-minus]');
      var plus = container.querySelector('[data-fs-plus]');
      if (minus) minus.addEventListener('click', function () { setFs(CC.settings.get('fontScale') - 0.05); });
      if (plus) plus.addEventListener('click', function () { setFs(CC.settings.get('fontScale') + 0.05); });

      // actions
      bind(container, 'clear-fav', function () { CC.favorites.clear(); CC.ui.toast('علاقه‌مندی‌ها پاک شد'); refreshCounts(); });
      bind(container, 'clear-hist', function () { CC.history.clear(); CC.ui.toast('تاریخچه پاک شد'); refreshCounts(); });
      bind(container, 'reset', function () { CC.settings.reset(); CC.ui.toast('تنظیمات بازنشانی شد'); CC.nav.replace('settings'); });

      function refreshCounts() {
        var f = container.querySelector('[data-count="clear-fav"]'); if (f) f.textContent = CC.faDigits(CC.favorites.count()) + ' مورد';
        var h = container.querySelector('[data-count="clear-hist"]'); if (h) h.textContent = CC.faDigits(CC.history.entries().length) + ' مورد';
      }
    },
    focusFirst: function (container) { CC.focus.first(container); }
  };

  function bind(scope, action, fn) {
    var el = scope.querySelector('[data-action="' + action + '"]');
    if (el) el.addEventListener('click', fn);
  }
  function section(title, inner) {
    return '<section class="settings-section"><h2 class="section-title">' + CC.esc(title) + '</h2>' + inner + '</section>';
  }
  function chipRow(label, key, options, active) {
    return '<div class="setting-row setting-row-stack"><span class="setting-label">' + CC.esc(label) + '</span>' +
      '<div class="chips" data-chipset="' + key + '">' + options.map(function (o) {
        return '<button class="chip focusable' + (String(o.key) === String(active) ? ' is-active' : '') + '" data-val="' + CC.esc(o.key) + '" type="button">' + CC.esc(o.title) + '</button>';
      }).join('') + '</div></div>';
  }
  function toggleRow(label, key, on, hint) {
    return '<button class="setting-row setting-toggle focusable' + (on ? ' is-on' : '') + '" data-toggle="' + key + '" type="button">' +
      '<span class="setting-text"><span class="setting-label">' + CC.esc(label) + '</span>' +
        (hint ? '<span class="setting-hint">' + CC.esc(hint) + '</span>' : '') + '</span>' +
      '<span class="toggle-pill"><i></i></span><span class="toggle-state">' + (on ? 'روشن' : 'خاموش') + '</span></button>';
  }
  function stepperRow(label, key, value) {
    return '<div class="setting-row"><span class="setting-label">' + CC.esc(label) + '</span>' +
      '<span class="stepper">' +
        '<button class="step-btn focusable" data-fs-minus type="button" aria-label="کوچک‌تر">−</button>' +
        '<span class="step-val" data-fs-val>' + CC.faDigits(Math.round(value * 100)) + '٪' + '</span>' +
        '<button class="step-btn focusable" data-fs-plus type="button" aria-label="بزرگ‌تر">+</button>' +
      '</span></div>';
  }
  function actionRow(label, action, count) {
    return '<button class="setting-row setting-action focusable" data-action="' + action + '" type="button">' +
      '<span class="setting-label">' + CC.esc(label) + '</span>' +
      '<span class="setting-count" data-count="' + action + '">' + CC.esc(count) + '</span></button>';
  }
})();