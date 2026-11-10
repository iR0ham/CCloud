/* Local development server: serves the web app and proxies remote JSON so the
 * app can be tested in a desktop browser (the TV uses the bundled Node service
 * instead). No external dependencies. */
var http = require('http');
var https = require('https');
var fs = require('fs');
var path = require('path');
var URL = require('url');

var ROOT = path.join(__dirname, 'app');
var PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;

var MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ico': 'image/x-icon'
};

function proxy(target, res) {
  var parsed;
  try { parsed = URL.parse(target); } catch (e) { res.writeHead(400); res.end('bad url'); return; }
  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    res.writeHead(400); res.end('bad protocol'); return;
  }
  var lib = parsed.protocol === 'https:' ? https : http;
  var req = lib.get(target, {
    headers: {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': 'CCloudTV/1.0 (dev)',
      'Cache-Control': 'no-cache'
    },
    timeout: 25000
  }, function (up) {
    res.writeHead(up.statusCode || 502, {
      'Content-Type': up.headers['content-type'] || 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-cache'
    });
    up.pipe(res);
  });
  req.on('timeout', function () { req.abort(); if (!res.headersSent) { res.writeHead(504); } res.end('timeout'); });
  req.on('error', function (err) { if (!res.headersSent) { res.writeHead(502); } res.end('proxy error: ' + err.message); });
}

function serveStatic(reqUrl, res) {
  var pathname = decodeURIComponent(URL.parse(reqUrl).pathname);
  if (pathname === '/') pathname = '/index.html';
  var filePath = path.normalize(path.join(ROOT, pathname));
  if (filePath.indexOf(ROOT) !== 0) { res.writeHead(403); res.end('forbidden'); return; }
  fs.stat(filePath, function (err, stat) {
    if (err || !stat.isFile()) {
      // SPA fallback
      filePath = path.join(ROOT, 'index.html');
    }
    var ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    fs.createReadStream(filePath).pipe(res);
  });
}

http.createServer(function (req, res) {
  var parsed = URL.parse(req.url, true);
  if (parsed.pathname === '/devproxy') {
    var target = parsed.query.u;
    if (!target) { res.writeHead(400); res.end('missing u'); return; }
    proxy(target, res);
    return;
  }
  serveStatic(req.url, res);
}).listen(PORT, function () {
  console.log('CCloud webOS dev server → http://localhost:' + PORT);
});