/* Network transport. On a packaged webOS app, requests go through the bundled
 * Node service (luna://com.ccloud.tv.service/fetch) to avoid browser CORS. In a
 * desktop browser they go through the local dev proxy. */
(function () {
  var SERVICE = 'luna://com.ccloud.tv.service/';
  var MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
  var ERROR_RESPONSE_TOO_LARGE = 'response-too-large';

  function lunaError(resp, fallback) {
    var error = new Error((resp && resp.errorText) || fallback);
    if (resp && resp.errorCode) error.code = resp.errorCode;
    return error;
  }

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
          finish(reject, lunaError(resp, 'اتصال به سرور برقرار نشد'));
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
              finish(reject, lunaError(err, 'سرویس شبکه در دسترس نیست'));
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

  function responseTooLargeError() {
    var error = new Error('حجم پاسخ بیش از حد مجاز است');
    error.code = ERROR_RESPONSE_TOO_LARGE;
    return error;
  }

  function readBoundedText(response) {
    if (response.body === null) return Promise.resolve('');
    if (!response.body || typeof response.body.getReader !== 'function') {
      throw new Error('خواندن پاسخ شبکه پشتیبانی نمی‌شود');
    }

    var reader = response.body.getReader();
    var decoder = new TextDecoder('utf-8');
    var chunks = [];
    var receivedBytes = 0;
    return new Promise(function (resolve, reject) {
      function rejectWith(error) {
        chunks.length = 0;
        reject(error);
      }
      function read() {
        reader.read().then(function (result) {
          if (result.done) {
            resolve(chunks.join('') + decoder.decode());
            return;
          }
          receivedBytes += result.value.byteLength;
          if (receivedBytes > MAX_RESPONSE_BYTES) {
            var error = responseTooLargeError();
            try {
              Promise.resolve(reader.cancel()).catch(function () {});
            } catch (cancelError) {
              // The policy error still wins if cancellation itself fails.
            }
            rejectWith(error);
            return;
          }
          chunks.push(decoder.decode(result.value, { stream: true }));
          read();
        }).catch(rejectWith);
      }
      read();
    });
  }

  function directFetch(url) {
    return fetch(url, { cache: 'no-cache' }).then(function (r) {
      if (!r.ok) throw new Error('خطای سرور (کد ' + r.status + ')');
      return readBoundedText(r);
    });
  }

  CC.net = {
    getText: function (url) {
      var hasLuna = !!(window.webOS && window.webOS.service && window.webOS.service.request) || !!window.PalmServiceBridge;
      if (CC.isWebOS() && hasLuna) {
        return lunaFetch(url).catch(function (error) {
          if (error && error.code === ERROR_RESPONSE_TOO_LARGE) throw error;
          return directFetch(url);
        });
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