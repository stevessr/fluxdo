import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/credential_store_service.dart';
import 'package:fluxdo/services/storage/secret_store.dart';

void main() {
  group('CredentialStoreService 多账户凭证', () {
    late CredentialStoreService store;

    setUp(() {
      store = CredentialStoreService.forTesting(InMemorySecretStore());
    });

    test('不同账号密码互不覆盖，默认返回最近保存账号', () async {
      await store.save('alice', 'alice-password', accountId: 'alice');
      await store.save('bob', 'bob-password', accountId: 'bob');

      final alice = await store.load(accountId: 'alice');
      final bob = await store.load(accountId: 'bob');
      final recent = await store.load();

      expect(alice.username, 'alice');
      expect(alice.password, 'alice-password');
      expect(bob.username, 'bob');
      expect(bob.password, 'bob-password');
      expect(recent.username, 'bob');
      expect(recent.password, 'bob-password');
    });

    test('账号标识大小写不敏感并按真实 username 合并旧别名槽', () async {
      await store.save(
        'Alice@Example.com',
        'old-password',
        accountId: 'Alice@Example.com',
      );
      await store.save('Alice@Example.com', 'new-password', accountId: 'Alice');

      final credentials = await store.list();
      expect(credentials, hasLength(1));
      expect(credentials.single.accountId, 'Alice');
      expect(credentials.single.identifier, 'Alice@Example.com');
      expect(credentials.single.password, 'new-password');

      final byUsername = await store.load(accountId: 'alice');
      final byIdentifier = await store.load(accountId: 'alice@example.com');
      expect(byUsername.password, 'new-password');
      expect(byIdentifier.password, 'new-password');
    });

    test('清除单个账号不会影响其他账号', () async {
      await store.save('alice', 'alice-password', accountId: 'alice');
      await store.save('bob', 'bob-password', accountId: 'bob');

      await store.clear(accountId: 'ALICE');

      expect(await store.hasCredentials(accountId: 'alice'), isFalse);
      expect(await store.hasCredentials(accountId: 'bob'), isTrue);
      expect(await store.list(), hasLength(1));
    });

    test('清除全部账号会删除索引和所有密码', () async {
      await store.save('alice', 'alice-password', accountId: 'alice');
      await store.save('bob', 'bob-password', accountId: 'bob');

      await store.clear();

      expect(await store.hasCredentials(), isFalse);
      expect(await store.list(), isEmpty);
    });
  });
}
