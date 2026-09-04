import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/account_runtime_pool.dart';

CanonicalCookie _cookie(String name, String value, {DateTime? expiresAt}) {
  return CanonicalCookie(
    name: name,
    value: value,
    domain: 'linux.do',
    path: '/',
    expiresAt: expiresAt,
    secure: true,
    httpOnly: name == '_t',
    hostOnly: true,
    persistent: expiresAt != null,
    originUrl: 'https://linux.do/',
  );
}

void main() {
  final pool = AccountRuntimePool.instance;

  setUp(pool.resetForTest);
  tearDown(pool.resetForTest);

  test('不同账号 runtime 相互隔离且按 token 精确命中', () {
    final now = DateTime.utc(2026, 9, 3, 12);
    pool.save(
      username: 'Alice',
      cookies: [
        _cookie('_t', 'alice-token'),
        _cookie('theme', 'dark'),
        _cookie('cf_clearance', 'device-token'),
      ],
      sessionToken: 'alice-token',
      csrfToken: 'alice-csrf',
      capturedAt: now,
      validatedAt: now,
    );
    pool.save(
      username: 'Bob',
      cookies: [_cookie('_t', 'bob-token')],
      sessionToken: 'bob-token',
      csrfToken: 'bob-csrf',
      capturedAt: now.add(const Duration(seconds: 1)),
      validatedAt: now.add(const Duration(seconds: 1)),
    );

    final lookupNow = now.add(const Duration(seconds: 1));
    final alice = pool.findMatching('alice', 'alice-token', now: lookupNow);
    final bob = pool.findMatching('BOB', 'bob-token', now: lookupNow);

    expect(alice, isNotNull);
    expect(bob, isNotNull);
    expect(alice!.csrfToken, 'alice-csrf');
    expect(bob!.csrfToken, 'bob-csrf');
    expect(alice.cookies.any((cookie) => cookie.name == 'theme'), isTrue);
    expect(
      alice.cookies.any((cookie) => cookie.name == 'cf_clearance'),
      isFalse,
    );
    expect(pool.findMatching('Alice', 'bob-token', now: lookupNow), isNull);
  });

  test('只有短窗口内允许复用服务端校验结果', () {
    final now = DateTime.utc(2026, 9, 3, 12);
    pool.save(
      username: 'Alice',
      cookies: [_cookie('_t', 'alice-token')],
      sessionToken: 'alice-token',
      capturedAt: now,
      validatedAt: now,
    );

    final runtime = pool.findMatching('Alice', 'alice-token', now: now)!;
    expect(
      runtime.canReuseValidation(
        now: now.add(const Duration(minutes: 1, seconds: 59)),
      ),
      isTrue,
    );
    expect(
      runtime.canReuseValidation(
        now: now.add(const Duration(minutes: 2, seconds: 1)),
      ),
      isFalse,
    );
  });

  test('过旧 runtime 会被淘汰而不是绕过持久化快照', () {
    final now = DateTime.utc(2026, 9, 3, 12);
    pool.save(
      username: 'Alice',
      cookies: [_cookie('_t', 'alice-token')],
      sessionToken: 'alice-token',
      capturedAt: now,
      validatedAt: now,
    );

    expect(
      pool.findMatching(
        'Alice',
        'alice-token',
        now: now.add(const Duration(minutes: 31)),
      ),
      isNull,
    );
    expect(pool.lengthForTest, 0);
  });

  test('没有匹配 _t 的状态不会进入 runtime pool', () {
    final now = DateTime.utc(2026, 9, 3, 12);
    pool.save(
      username: 'Alice',
      cookies: [_cookie('_t', 'different-token')],
      sessionToken: 'alice-token',
      capturedAt: now,
      validatedAt: now,
    );

    expect(pool.lengthForTest, 0);
  });
}
