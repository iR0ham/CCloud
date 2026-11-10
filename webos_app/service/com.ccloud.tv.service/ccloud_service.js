/* CCloud network proxy — runs as a webOS Node.js service so the web app can
 * reach the catalog API and live-TV dataset without browser CORS restrictions. */
var Service = require('webos-service');
var https = require('https');
var http = require('http');
var URL = require('url');

var service = new Service('com.ccloud.tv.service');

function fetchUrl(target, redirects, done) {
  var parsed;
  try {
    parsed = URL.parse(target);
  } catch (e) {
    done({ returnValue: false, errorText: 'آدرس نامعتبر بود' });
    return;
  }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    done({ returnValue: false, errorText: 'پروتکل پشتیبانی نمی‌شود' });
    return;
  }
  var lib = parsed.protocol === 'https:' ? https : http;
  var req = lib.get(target, {
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'Cache-Control': 'no-cache',
      'User-Agent': 'CCloudTV/1.0 (webOS)'
    },
    timeout: 20000
  }, function (res) {
    var status = res.statusCode || 0;
    if (status >= 300 && status < 400 && res.headers.location && redirects < 5) {
      res.resume();
      var next = URL.resolve(target, res.headers.location);
      fetchUrl(next, redirects + 1, done);
      return;
    }
    var chunks = [];
    res.setEncoding('utf8');
    res.on('data', function (c) { chunks.push(c); });
    res.on('end', function () {
      done({
        returnValue: true,
        statusCode: status,
        contentType: res.headers['content-type'] || '',
        body: chunks.join('')
      });
    });
  });
  req.on('timeout', function () {
    req.abort();
    done({ returnValue: false, errorText: 'پاسخ سرور دیر رسید' });
  });
  req.on('error', function (err) {
    done({ returnValue: false, errorText: 'اتصال به سرور برقرار نشد', detail: String(err && err.message || err) });
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