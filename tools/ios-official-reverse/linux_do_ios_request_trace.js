'use strict';

/*
 * LINUX DO 官方 iOS 客户端请求构造追踪器。
 *
 * 目标：在 TLS / HTTP3 加密前观察 Foundation URLRequest，定位设备型号
 * 元数据真实位于 query、header 还是 body。脚本不绕过 SSL Pin、不伪造
 * App Attest，并默认打码 Cookie / Token / Assertion 等认证值。
 */

if (!ObjC.available) {
  throw new Error('当前进程没有 Objective-C runtime');
}

const TARGET_HOST = 'ios.linux.do';
const INTERESTING_RE =
  /(ios[_-]?device[_-]?name|via[_-]?ios[_-]?app|device|model|machine|hardware|platform|attest|integrity)/i;
const SENSITIVE_RE =
  /(authorization|cookie|csrf|token|secret|password|assertion|attestation|key[_-]?id|signature|credential)/i;
const MAX_BODY = 24 * 1024;
const seen = new Set();

function toStringSafe(value) {
  if (!value) return null;
  try {
    return new ObjC.Object(value).toString();
  } catch (_) {
    try {
      return value.toString();
    } catch (_) {
      return null;
    }
  }
}

function redact(name, value) {
  const key = String(name || '');
  const text = value == null ? '' : String(value);
  if (SENSITIVE_RE.test(key)) return `<redacted:${text.length}>`;
  return text.length > 1024
    ? `${text.slice(0, 1024)}…<${text.length}>`
    : text;
}

function nsDataToUtf8(value) {
  if (!value) return null;
  try {
    const data = new ObjC.Object(value);
    const length = Number(data.length());
    if (!length) return '';
    return Memory.readUtf8String(data.bytes(), Math.min(length, MAX_BODY));
  } catch (_) {
    return null;
  }
}

function dictionaryToObject(value) {
  const result = {};
  if (!value) return result;
  try {
    const dict = new ObjC.Object(value);
    const keys = dict.allKeys();
    for (let i = 0; i < Number(keys.count()); i++) {
      const keyObj = keys.objectAtIndex_(i);
      const key = keyObj.toString();
      const valObj = dict.objectForKey_(keyObj);
      result[key] = redact(key, valObj ? valObj.toString() : '');
    }
  } catch (_) {}
  return result;
}

function decodeComponent(value) {
  try {
    return decodeURIComponent(String(value || '').replace(/\\+/g, ' '));
  } catch (_) {
    return String(value || '');
  }
}

function parsePairs(text) {
  const pairs = [];
  for (const part of String(text || '').split('&')) {
    if (!part) continue;
    const separator = part.indexOf('=');
    const rawKey = separator >= 0 ? part.slice(0, separator) : part;
    const rawValue = separator >= 0 ? part.slice(separator + 1) : '';
    pairs.push([decodeComponent(rawKey), decodeComponent(rawValue)]);
  }
  return pairs;
}

function parseUrl(url) {
  const text = String(url || '');
  const match = text.match(
    /^([a-z][a-z0-9+.-]*):\\/\\/([^/?#]+)([^?#]*)(?:\\?([^#]*))?/i,
  );
  if (!match) return {host: '', path: text, query: {}, safeUrl: text};

  const authority = match[2] || '';
  const host = authority.replace(/:\\d+$/, '');
  const path = match[3] || '/';
  const query = {};
  for (const [key, value] of parsePairs(match[4] || '')) {
    query[key] = redact(key, value);
  }

  return {
    host,
    path,
    query,
    safeUrl: `${match[1]}://${authority}${path}`,
  };
}

function collectJsonPaths(value, path, output) {
  if (value == null) return;
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      collectJsonPaths(item, `${path}[${index}]`, output));
    return;
  }
  if (typeof value !== 'object') return;

  for (const [key, child] of Object.entries(value)) {
    const childPath = path ? `${path}.${key}` : key;
    if (INTERESTING_RE.test(key)) {
      output.push({path: childPath, value: redact(key, child)});
    }
    collectJsonPaths(child, childPath, output);
  }
}

function sanitizeTextBody(body) {
  return body.slice(0, MAX_BODY).replace(
    /(["']?)(authorization|cookie|csrf[^"'=:,\s]*|token[^"'=:,\s]*|secret[^"'=:,\s]*|password[^"'=:,\s]*|assertion[^"'=:,\s]*|attestation[^"'=:,\s]*|key[_-]?id|signature|credential)(\1)\s*[:=]\s*(["'])(.*?)\4/gi,
    '$1$2$3:"<redacted>"',
  );
}

function analyzeBody(text, contentType) {
  const interesting = [];
  if (text == null) return {kind: 'none', interesting};
  const body = text.trim();
  if (!body) return {kind: 'empty', interesting};

  if (/json/i.test(contentType || '') || body.startsWith('{') || body.startsWith('[')) {
    try {
      collectJsonPaths(JSON.parse(body), '', interesting);
      return {kind: 'json', interesting, preview: sanitizeTextBody(body)};
    } catch (_) {}
  }

  if (/x-www-form-urlencoded/i.test(contentType || '') || body.includes('=')) {
    const preview = [];
    for (const [key, value] of parsePairs(body)) {
      if (INTERESTING_RE.test(key)) {
        interesting.push({path: key, value: redact(key, value)});
      }
      preview.push(
        `${encodeURIComponent(key)}=${encodeURIComponent(redact(key, value))}`,
      );
    }
    return {
      kind: 'form',
      interesting,
      preview: preview.join('&').slice(0, MAX_BODY),
    };
  }

  if (INTERESTING_RE.test(body)) {
    interesting.push({
      path: '<raw-body-match>',
      value: sanitizeTextBody(body),
    });
  }
  return {kind: 'raw', interesting, preview: sanitizeTextBody(body)};
}

function printInteresting(prefix, object) {
  for (const [key, value] of Object.entries(object || {})) {
    if (INTERESTING_RE.test(key)) {
      console.log(`  ${prefix}.${key} = ${redact(key, value)}`);
    }
  }
}

function inspectRequest(value, source, explicitBodyValue) {
  if (!value) return;
  let request;
  try {
    request = new ObjC.Object(value);
  } catch (_) {
    return;
  }

  let url = null;
  try {
    url = request.URL().absoluteString().toString();
  } catch (_) {}
  if (!url) return;

  const parsed = parseUrl(url);
  if (parsed.host.toLowerCase() !== TARGET_HOST) return;

  let method = 'GET';
  try {
    method = request.HTTPMethod().toString();
  } catch (_) {}

  let headers = {};
  try {
    headers = dictionaryToObject(request.allHTTPHeaderFields());
  } catch (_) {}

  let body = nsDataToUtf8(explicitBodyValue);
  if (body == null) {
    try {
      body = nsDataToUtf8(request.HTTPBody());
    } catch (_) {}
  }

  const dedupe = `${method} ${url}\n${body || ''}`.slice(0, 4096);
  if (seen.has(dedupe)) return;
  seen.add(dedupe);
  if (seen.size > 512) seen.clear();

  const contentType = headers['Content-Type'] || headers['content-type'] || '';
  const bodyInfo = analyzeBody(body, contentType);

  console.log('\n============================================================');
  console.log(`[linuxdo-ios-trace] ${source}: ${method} ${parsed.path}`);
  console.log(`URL: ${parsed.safeUrl}`);
  printInteresting('query', parsed.query);
  printInteresting('header', headers);

  for (const item of bodyInfo.interesting) {
    console.log(`  body.${item.path} = ${item.value}`);
  }

  const found =
    Object.keys(parsed.query).some(key => INTERESTING_RE.test(key)) ||
    Object.keys(headers).some(key => INTERESTING_RE.test(key)) ||
    bodyInfo.interesting.length > 0;

  console.log(`body-kind: ${bodyInfo.kind}`);
  if (!found) {
    console.log(
      '  [!] 本请求未出现 device/model/ios/attest/integrity 相关字段名',
    );
  }
  if (bodyInfo.preview) {
    console.log(`body-preview: ${bodyInfo.preview}`);
  }
}

function hook(className, selector, callback) {
  const cls = ObjC.classes[className];
  if (!cls || !cls[selector]) return false;
  Interceptor.attach(cls[selector].implementation, {
    onEnter(args) {
      try {
        callback.call(this, args);
      } catch (error) {
        console.log(
          `[linuxdo-ios-trace] hook ${className} ${selector} error: ${error}`,
        );
      }
    },
  });
  console.log(`[linuxdo-ios-trace] hooked ${className} ${selector}`);
  return true;
}

const requestSelectors = [
  '- dataTaskWithRequest:',
  '- dataTaskWithRequest:completionHandler:',
  '- uploadTaskWithStreamedRequest:',
];

for (const selector of requestSelectors) {
  hook('NSURLSession', selector, args =>
    inspectRequest(args[2], `NSURLSession ${selector}`));
}

const uploadDataSelectors = [
  '- uploadTaskWithRequest:fromData:',
  '- uploadTaskWithRequest:fromData:completionHandler:',
];

for (const selector of uploadDataSelectors) {
  hook('NSURLSession', selector, args =>
    inspectRequest(args[2], `NSURLSession ${selector}`, args[3]));
}

for (const className of ['NSURLSessionTask', '__NSCFURLSessionTask']) {
  hook(className, '- resume', function(args) {
    try {
      const task = new ObjC.Object(args[0]);
      const request = task.originalRequest ? task.originalRequest() : null;
      inspectRequest(request, `${className} resume`);
    } catch (_) {}
  });
}

hook('NSMutableURLRequest', '- setValue:forHTTPHeaderField:', args => {
  const value = toStringSafe(args[2]);
  const field = toStringSafe(args[3]);
  if (field && INTERESTING_RE.test(field)) {
    console.log(
      `[linuxdo-ios-trace] header-set ${field} = ${redact(field, value)}`,
    );
  }
});

hook('NSMutableURLRequest', '- addValue:forHTTPHeaderField:', args => {
  const value = toStringSafe(args[2]);
  const field = toStringSafe(args[3]);
  if (field && INTERESTING_RE.test(field)) {
    console.log(
      `[linuxdo-ios-trace] header-add ${field} = ${redact(field, value)}`,
    );
  }
});

// App Attest 只记录调用和长度，不输出 keyId / assertion。
if (ObjC.classes.DCAppAttestService) {
  hook(
    'DCAppAttestService',
    '- generateAssertion:clientDataHash:completionHandler:',
    args => {
      const keyId = toStringSafe(args[2]) || '';
      let hashLength = -1;
      try {
        hashLength = Number(new ObjC.Object(args[3]).length());
      } catch (_) {}
      console.log(
        `[linuxdo-ios-trace] AppAttest generateAssertion keyId=<redacted:${keyId.length}> clientDataHashBytes=${hashLength}`,
      );
    },
  );

  hook(
    'DCAppAttestService',
    '- attestKey:clientDataHash:completionHandler:',
    args => {
      const keyId = toStringSafe(args[2]) || '';
      let hashLength = -1;
      try {
        hashLength = Number(new ObjC.Object(args[3]).length());
      } catch (_) {}
      console.log(
        `[linuxdo-ios-trace] AppAttest attestKey keyId=<redacted:${keyId.length}> clientDataHashBytes=${hashLength}`,
      );
    },
  );
}

console.log(
  `[linuxdo-ios-trace] ready; target host = ${TARGET_HOST}`,
);
