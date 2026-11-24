/* CCloud network proxy — runs as a webOS Node.js service so the web app can
 * reach the catalog API and live-TV dataset without browser CORS restrictions. */
var Service = require('webos-service');
var https = require('https');
var http = require('http');
var URL = require('url');

var service = new Service('com.ccloud.tv.service');

var MAX_RESPONSE_BYTES = 8 * 1024 * 1024;

function fetchUrl(target, redirects, done, completion) {
  completion = completion || { finished: false };
  function finish(result) {
    if (completion.finished) return;
    completion.finished = true;
    done(result);
  }
  if (completion.finished) return;

  var parsed;
  try {
    parsed = URL.parse(target);
  } catch (e) {
    finish({ returnValue: false, errorText: 'آدرس نامعتبر بود' });
    return;
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    finish({ returnValue: false, errorText: 'پروتکل پشتیبانی نمی‌شود' });
    return;
  }
  var lib = parsed.protocol === 'https:' ? https : http;
  var active = true;
  var req = lib.get(target, {
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'Cache-Control': 'no-cache',
      'User-Agent': 'CCloudTV/1.0 (webOS)'
    },
    timeout: 20000
  }, function (res) {
    if (!active || completion.finished) {
      res.resume();
      return;
    }
    var status = res.statusCode || 0;
    res.on('error', function (err) {
      if (!active || completion.finished) return;
      finish({ returnValue: false, errorText: 'اتصال به سرور برقرار نشد', detail: String(err && err.message || err) });
    });
    if (status >= 300 && status < 400 && res.headers.location && redirects < 5) {
      active = false;
      res.resume();
      var next = URL.resolve(target, res.headers.location);
      fetchUrl(next, redirects + 1, done, completion);
      return;
    }

    var contentLength = Number(res.headers['content-length']);
    if (isFinite(contentLength) && contentLength > MAX_RESPONSE_BYTES) {
      finish({ returnValue: false, errorText: 'حجم پاسخ بیش از حد مجاز است' });
      res.destroy();
      req.destroy();
      return;
    }

    var chunks = [];
    var receivedBytes = 0;
    res.setEncoding('utf8');
    res.on('data', function (c) {
      if (!active || completion.finished) return;
      receivedBytes += Buffer.byteLength(c, 'utf8');
      if (receivedBytes > MAX_RESPONSE_BYTES) {
        chunks.length = 0;
        finish({ returnValue: false, errorText: 'حجم پاسخ بیش از حد مجاز است' });
        res.destroy();
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    res.on('end', function () {
      if (!active || completion.finished) return;
      finish({
        returnValue: true,
        statusCode: status,
        contentType: res.headers['content-type'] || '',
        body: chunks.join('')
      });
    });
  });
  req.on('timeout', function () {
    if (!active || completion.finished) return;
    finish({ returnValue: false, errorText: 'پاسخ سرور دیر رسید' });
    req.abort();
  });
  req.on('error', function (err) {
    if (!active || completion.finished) return;
    finish({ returnValue: false, errorText: 'اتصال به سرور برقرار نشد', detail: String(err && err.message || err) });
  });
}

service.register('fetch', function (message) {
  var url = message.payload && message.payload.url;
  if (!url || typeof url !== 'string') {
    message.respond({ returnValue: false, errorText: 'پارامتر url لازم است' });
    return;
  }
  fetchUrl(url, 0, function (result) {
    message.respond(result);
  });
});

service.register('ping', function (message) {
  message.respond({ returnValue: true, pong: true });
});