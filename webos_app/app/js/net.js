/* Network transport. On a packaged webOS app, requests go through the bundled
 * Node service (luna://com.ccloud.tv.service/fetch) to avoid browser CORS. In a
 * desktop browser they go through the local dev proxy. */
(function () {
  var SERVICE = 'luna://com.ccloud.tv.service/';

  function lunaFetch(url) {
    return new Promise(function (resolve, reject) {
      var settled = false;
      var timer = setTimeout(function () {
        if (!settled) { settled = true; reject(new Error('پاسخ سرور دیر رسید')); }
      }, 25000);
      function finish(fn, arg) {
        if (settled) return;
        settled = true; clearTimeout(timer); fn(arg);
      }
      function handle(resp) {
        if (!resp || resp.returnValue === false) {
          finish(reject, new Error((resp && resp.errorText) || 'اتصال به سرور برقرار نشد'));
          return;
        }
        var code = resp.statusCode || 0;
        if (code && (code < 200 || code >= 300)) {
          finish(reject, new Error('خطای سرور (کد ' + code + ')'));
          return;
        }
        finish(resolve, resp.body || '');
      }
      try {
        if (window.webOS && window.webOS.service && window.webOS.service.request) {
          window.webOS.service.request(SERVICE, {
            method: 'fetch',
            parameters: { url: url },
            onSuccess: handle,
            onFailure: function (err) {
              finish(reject, new Error((err && err.errorText) || 'سرویس شبکه در دسترس نیست'));
            }
          });
        } else if (window.PalmServiceBridge) {
          var bridge = new window.PalmServiceBridge();
          bridge.onservicecallback = function (msg) {
            var resp;
            try { resp = JSON.parse(msg); } catch (e) { resp = null; }
            handle(resp);
          };
          bridge.call(SERVICE, JSON.stringify({ method: 'fetch', parameters: { url: url } }));
        } else {
          finish(reject, new Error('سرویس شبکه در دسترس نیست'));
        }
      } catch (e) {
        finish(reject, e);
      }
    });
  }

  function proxyFetch(url) {
    return fetch('/devproxy?u=' + encodeURIComponent(url), { cache: 'no-cache' })
      .then(function (r) {
        if (!r.ok) throw new Error('خطای سرور (کد ' + r.status + ')');
        return r.text();
      });
  }

  function directFetch(url) {
    return fetch(url, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error('خطای سرور (کد ' + r.status + ')');
      return r.text();
    });
  }

  CC.net = {
    getText: function (url) {
      var hasLuna = !!(window.webOS && window.webOS.service && window.webOS.service.request) || !!window.PalmServiceBridge;
      if (CC.isWebOS() && hasLuna) {
        return lunaFetch(url).catch(function () { return directFetch(url); });
      }
      var localDev = /^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname);
      if (localDev) return proxyFetch(url);
      return directFetch(url);
    },
    getJson: function (url) {
      return CC.net.getText(url).then(function (text) {
        var trimmed = String(text).replace(/^\uFEFF/, '').trim();
        if (!trimmed) throw new Error('پاسخ خالی از سرور');
        if (trimmed.charAt(0) === '<') throw new Error('خطای سرور (کد 502)');
        try { return JSON.parse(trimmed); }
        catch (e) { throw new Error('داده‌های دریافتی نامعتبر بود'); }
      });
    }
  };
})();