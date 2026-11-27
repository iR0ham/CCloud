'use strict';

const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
// ccloud_service.js binds `var URL = require('url')` and then calls the LEGACY
// module functions `url.parse(target)` and `url.resolve(target, location)`. The
// sandbox must inject the whole module, not the WHATWG `URL` class: static
// `URL.parse` only exists on Node >= 22.1.0, while the runners pin Node 20
// (.github/workflows/ci.yml:160, build-webos.yml:45). If the service ever moves
// to WHATWG URL, both sides must change together.
const urlModule = require('node:url');

const ROOT = path.resolve(__dirname, '../..');
const SERVICE_PATH = path.join(
  ROOT,
  'webos_app/service/com.ccloud.tv.service/ccloud_service.js'
);
const NET_PATH = path.join(ROOT, 'webos_app/app/js/net.js');
const SERVICE_SOURCE = fs.readFileSync(SERVICE_PATH, 'utf8');
const NET_SOURCE = fs.readFileSync(NET_PATH, 'utf8');
const MAX_RESPONSE_BYTES = 8 * 1024 * 1024;
// Two of these chunks are exactly 8 MiB in UTF-8, but only 4 MiB in UTF-16
// code units. Reuse the same fixture for the service and direct-fetch paths.
const MULTIBYTE_UTF8_CHUNK = Buffer.from(
  'é'.repeat(MAX_RESPONSE_BYTES / 4),
  'utf8'
);

function loadService(httpsMock) {
  // Fail loudly rather than silently exercising the service's invalid-address
  // branch if the injected module ever stops providing the legacy API that
  // production calls. This guard is version-independent by design.
  for (const member of ['parse', 'resolve']) {
    if (typeof urlModule[member] !== 'function') {
      assert.fail(
        'test harness defect: the injected url module must expose the legacy ' +
          `url.${member}() used by ccloud_service.js`
      );
    }
  }
  const handlers = {};
  function Service() {}
  Service.prototype.register = function (name, handler) {
    handlers[name] = handler;
  };

  const context = {
    Buffer: Buffer,
    console: console,
    isFinite: isFinite,
    require: function (name) {
      if (name === 'webos-service') return Service;
      if (name === 'https') return httpsMock;
      if (name === 'http') return {};
      if (name === 'url') return urlModule;
      throw new Error('Unexpected service dependency: ' + name);
    }
  };
  vm.runInNewContext(SERVICE_SOURCE, context, { filename: SERVICE_PATH });
  return handlers;
}

function requestService(handlers, url) {
  return new Promise(function (resolve) {
    handlers.fetch({
      payload: { url: url },
      respond: resolve
    });
  });
}

function loadNet(options) {
  const context = {
    window: options.window || {},
    location: { hostname: options.hostname || 'example.test' },
    CC: {
      isWebOS: function () {
        return !!options.isWebOS;
      }
    },
    fetch: options.fetchImpl,
    TextDecoder: TextDecoder,
    Promise: Promise,
    Error: Error,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout
  };
  vm.runInNewContext(NET_SOURCE, context, { filename: NET_PATH });
  return context.CC.net;
}

function streamedBytesResponse(chunks) {
  const metrics = { reads: 0, cancels: 0, textCalls: 0 };
  const response = {
    ok: true,
    status: 200,
    headers: { 'content-type': 'text/plain; charset=utf-8' },
    body: {
      getReader: function () {
        return {
          read: function () {
            const value = chunks[metrics.reads];
            metrics.reads += 1;
            return Promise.resolve(
              value === undefined
                ? { done: true }
                : { done: false, value: value }
            );
          },
          cancel: function () {
            metrics.cancels += 1;
            return Promise.resolve();
          }
        };
      }
    },
    text: function () {
      metrics.textCalls += 1;
      throw new Error('streamed responses must not call text()');
    }
  };
  return { response: response, metrics: metrics };
}

function streamedResponse(text) {
  return streamedBytesResponse([Buffer.from(text, 'utf8')]).response;
}

test('service oversized response returns stable response-too-large code', async function () {
  const destroyed = [];
  const req = new EventEmitter();
  req.destroy = function () {
    destroyed.push('request');
  };
  const res = new EventEmitter();
  res.statusCode = 200;
  res.headers = { 'content-length': String(MAX_RESPONSE_BYTES + 1) };
  res.destroy = function () {
    destroyed.push('response');
  };

  const handlers = loadService({
    get: function (target, options, callback) {
      assert.equal(target, 'https://example.test/large');
      queueMicrotask(function () {
        callback(res);
      });
      return req;
    }
  });

  const result = await requestService(handlers, 'https://example.test/large');
  assert.equal(result.returnValue, false);
  assert.equal(result.errorCode, 'response-too-large');
  assert.deepEqual(destroyed, ['response', 'request']);
});

test('service unknown-length body over cap rejects, destroys streams, and responds once', async function () {
  const destroyed = [];
  const req = new EventEmitter();
  req.destroy = function () {
    destroyed.push('request');
  };
  const res = new EventEmitter();
  res.statusCode = 200;
  res.headers = {
    'content-type': 'text/plain; charset=utf-8',
    'transfer-encoding': 'chunked'
  };
  res.setEncoding = function (encoding) {
    assert.equal(encoding, 'utf8');
  };
  res.destroy = function () {
    destroyed.push('response');
  };

  const handlers = loadService({
    get: function (target, options, callback) {
      assert.equal(target, 'https://example.test/chunked-large');
      queueMicrotask(function () {
        callback(res);
        queueMicrotask(function () {
          const chunk = MULTIBYTE_UTF8_CHUNK.toString('utf8');
          res.emit('data', chunk);
          res.emit('data', chunk);
          res.emit('data', 'b');
          res.emit('end');
        });
      });
      return req;
    }
  });

  let responseCount = 0;
  const result = await new Promise(function (resolve) {
    handlers.fetch({
      payload: { url: 'https://example.test/chunked-large' },
      respond: function (value) {
        responseCount += 1;
        resolve(value);
      }
    });
  });

  assert.equal(result.returnValue, false);
  assert.equal(result.errorCode, 'response-too-large');
  assert.equal(Object.prototype.hasOwnProperty.call(result, 'body'), false);
  assert.deepEqual(destroyed, ['response', 'request']);
  assert.equal(responseCount, 1);

  res.emit('error', new Error('late response error'));
  req.emit('timeout');
  req.emit('error', new Error('late request error'));
  assert.equal(responseCount, 1);
});

test('service destroys stalled redirect response and request before next request', async function () {
  const events = [];
  let eventsAtNextRequest;

  const firstReq = new EventEmitter();
  firstReq.destroy = function () {
    events.push('redirect-request-destroy');
  };
  const firstRes = new EventEmitter();
  firstRes.statusCode = 302;
  firstRes.headers = { location: '/next' };
  firstRes.resume = function () {
    events.push('redirect-resume');
  };
  firstRes.destroy = function () {
    events.push('redirect-response-destroy');
  };

  const secondReq = new EventEmitter();
  secondReq.destroy = function () {
    events.push('next-request-destroy');
  };
  const secondRes = new EventEmitter();
  secondRes.statusCode = 200;
  secondRes.headers = { 'content-type': 'application/json' };
  secondRes.setEncoding = function () {};
  secondRes.destroy = function () {
    events.push('next-response-destroy');
  };

  const handlers = loadService({
    get: function (target, options, callback) {
      if (target === 'https://example.test/start') {
        queueMicrotask(function () {
          callback(firstRes);
        });
        return firstReq;
      }

      assert.equal(target, 'https://example.test/next');
      eventsAtNextRequest = events.slice();
      queueMicrotask(function () {
        callback(secondRes);
        queueMicrotask(function () {
          secondRes.emit('data', '{"ok":true}');
          secondRes.emit('end');
        });
      });
      return secondReq;
    }
  });

  let responseCount = 0;
  const result = await new Promise(function (resolve) {
    handlers.fetch({
      payload: { url: 'https://example.test/start' },
      respond: function (value) {
        responseCount += 1;
        resolve(value);
      }
    });
  });

  assert.equal(result.returnValue, true);
  assert.equal(result.body, '{"ok":true}');
  assert.deepEqual(eventsAtNextRequest, [
    'redirect-response-destroy',
    'redirect-request-destroy'
  ]);
  assert.equal(events.includes('redirect-resume'), false);
  assert.equal(responseCount, 1);

  firstRes.emit('error', new Error('late redirect response error'));
  firstReq.emit('timeout');
  assert.equal(responseCount, 1);
});

test('direct fetch oversized streamed body cancels at cap and never calls text', async function () {
  const chunks = [
    Buffer.alloc(MAX_RESPONSE_BYTES, 0x61),
    Buffer.from([0x62])
  ];
  let readCalls = 0;
  let cancelCalls = 0;
  let textCalls = 0;
  const response = {
    ok: true,
    status: 200,
    body: {
      getReader: function () {
        return {
          read: function () {
            const value = chunks[readCalls];
            readCalls += 1;
            return Promise.resolve(
              value === undefined
                ? { done: true }
                : { done: false, value: value }
            );
          },
          cancel: function () {
            cancelCalls += 1;
            return Promise.resolve();
          }
        };
      }
    },
    text: function () {
      textCalls += 1;
      return Promise.resolve('unbounded');
    }
  };

  const net = loadNet({
    fetchImpl: function () {
      return Promise.resolve(response);
    }
  });

  await assert.rejects(
    net.getText('https://example.test/large'),
    function (error) {
      return error && error.code === 'response-too-large';
    }
  );
  assert.equal(readCalls, 2);
  assert.equal(cancelCalls, 1);
  assert.equal(textCalls, 0);
});

test('direct fetch accepts exactly 8 MiB and rejects one byte over', async function () {
  const capChunk = Buffer.alloc(MAX_RESPONSE_BYTES, 0x61);

  const accepted = streamedBytesResponse([capChunk]);
  const acceptedNet = loadNet({
    fetchImpl: function () {
      return Promise.resolve(accepted.response);
    }
  });
  const acceptedText = await acceptedNet.getText('https://example.test/exact-cap');
  assert.equal(Buffer.byteLength(acceptedText, 'utf8'), MAX_RESPONSE_BYTES);
  assert.deepEqual(accepted.metrics, { reads: 2, cancels: 0, textCalls: 0 });

  const rejected = streamedBytesResponse([capChunk, Buffer.from([0x62])]);
  const rejectedNet = loadNet({
    fetchImpl: function () {
      return Promise.resolve(rejected.response);
    }
  });
  await assert.rejects(
    rejectedNet.getText('https://example.test/over-cap'),
    function (error) {
      return error && error.code === 'response-too-large';
    }
  );
  assert.deepEqual(rejected.metrics, { reads: 2, cancels: 1, textCalls: 0 });
});

test('direct fetch counts multibyte UTF-8 chunks by bytes', async function () {
  // The two multibyte chunks total exactly 8 MiB in UTF-8. Counting decoded
  // characters would stay below the cap and incorrectly accept the last byte.
  const streamed = streamedBytesResponse([
    MULTIBYTE_UTF8_CHUNK,
    MULTIBYTE_UTF8_CHUNK,
    Buffer.from([0x62])
  ]);
  const net = loadNet({
    fetchImpl: function () {
      return Promise.resolve(streamed.response);
    }
  });

  await assert.rejects(
    net.getText('https://example.test/multibyte-over-cap'),
    function (error) {
      return error && error.code === 'response-too-large';
    }
  );
  assert.deepEqual(streamed.metrics, { reads: 3, cancels: 1, textCalls: 0 });
});

test('luna response-too-large policy error suppresses direct fallback', async function () {
  let directCalls = 0;
  const windowMock = {
    webOS: {
      service: {
        request: function (target, options) {
          assert.equal(target, 'luna://com.ccloud.tv.service/');
          options.onSuccess({
            returnValue: false,
            errorCode: 'response-too-large',
            errorText: 'حجم پاسخ بیش از حد مجاز است'
          });
        }
      }
    }
  };
  const net = loadNet({
    window: windowMock,
    isWebOS: true,
    fetchImpl: function () {
      directCalls += 1;
      return Promise.resolve(streamedResponse('unexpected fallback'));
    }
  });

  await assert.rejects(
    net.getText('https://example.test/large'),
    function (error) {
      return error && error.code === 'response-too-large';
    }
  );
  assert.equal(directCalls, 0);
});

test('genuine luna service failure still falls back to bounded direct fetch', async function () {
  let directCalls = 0;
  const windowMock = {
    webOS: {
      service: {
        request: function (target, options) {
          options.onFailure({ errorText: 'سرویس شبکه در دسترس نیست' });
        }
      }
    }
  };
  const net = loadNet({
    window: windowMock,
    isWebOS: true,
    fetchImpl: function () {
      directCalls += 1;
      return Promise.resolve(streamedResponse('fallback'));
    }
  });

  assert.equal(
    await net.getText('https://example.test/data'),
    'fallback'
  );
  assert.equal(directCalls, 1);
});
