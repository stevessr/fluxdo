// SDK-only regression runner: dart run test/contract_test.dart.
// Deliberately has no package:test or Flutter dependency.
import 'dart:convert';

import 'package:fluxdo_plugin_contract/fluxdo_plugin_contract.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void rejects<T extends Object>(void Function() action) {
  try {
    action();
  } catch (error) {
    if (error is T) return;
    rethrow;
  }
  throw StateError('Expected $T');
}

Map<String, dynamic> status(String id) => {
  'id': id,
  'name': 'Untrusted display name',
  'package': androidPluginCatalog[id]!.packageName,
  'installed': true,
  'compatible': true,
  'reason': 'ready',
  'version': '0.1.0',
};

void main() {
  final cases = <String, void Function()>{
    'catalog is immutable and separates native from Flutter': () {
      check(androidPluginCatalog.length == 6, 'Missing module');
      check(
        !androidPluginCatalog['sticker']!.hasNativeActivity,
        'Wrong transport',
      );
      rejects<UnsupportedError>(() => androidPluginCatalog.clear());
      rejects<UnsupportedError>(
        () => androidPluginCatalog['network']!.operations.clear(),
      );
    },
    'every declared native operation has a supported payload': () {
      for (final plugin in androidPluginCatalog.values) {
        if (plugin.runtime != PluginRuntime.native) continue;
        for (final operation in plugin.operations) {
          final payload = operation == 'network.lookup'
              ? <String, dynamic>{'hostname': 'linux.do'}
              : <String, dynamic>{};
          final encoded = AndroidPluginContract.encodeInvocation(
            plugin.id,
            operation,
            payload,
          );
          check(jsonDecode(encoded) is Map<String, dynamic>, 'Invalid request');
        }
      }
    },
    'unknown module, transport and undeclared operation fail closed': () {
      for (final id in ['unknown', 'sticker']) {
        rejects<ArgumentError>(
          () =>
              AndroidPluginContract.encodeInvocation(id, 'device.snapshot', {}),
        );
      }
      rejects<ArgumentError>(
        () => AndroidPluginContract.encodeInvocation(
          'network',
          'device.snapshot',
          {},
        ),
      );
    },
    'credentials and arbitrary arguments cannot cross invocation boundary': () {
      for (final field in ['cookie', 'token', 'password', 'accountSlot']) {
        rejects<FormatException>(
          () => AndroidPluginContract.encodeInvocation(
            'deviceinfo',
            'device.snapshot',
            {field: 'secret'},
          ),
        );
        rejects<FormatException>(
          () => AndroidPluginContract.encodeInvocation(
            'network',
            'network.lookup',
            {'hostname': 'linux.do', field: 'secret'},
          ),
        );
      }
    },
    'DNS hostname is normalized and validates every label': () {
      final value = jsonDecode(
        AndroidPluginContract.encodeInvocation('network', 'network.lookup', {
          'hostname': ' Linux.DO. ',
        }),
      ) as Map<String, dynamic>;
      check(value['hostname'] == 'Linux.DO.', 'Normalization changed identity');
      for (final host in [
        '',
        '.a',
        'a..b',
        '-a.com',
        'a-.com',
        'https://linux.do',
        'a/b',
        'a b',
        'a\nb',
        'a..',
        'exa_mple.com',
        'localhost:443',
        '${'a' * 64}.com',
        '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 63}',
      ]) {
        rejects<FormatException>(
          () => AndroidPluginContract.encodeInvocation(
            'network',
            'network.lookup',
            {'hostname': host},
          ),
        );
      }
      for (final value in [null, 7, true, <String>[]]) {
        rejects<FormatException>(
          () => AndroidPluginContract.encodeInvocation(
            'network',
            'network.lookup',
            {'hostname': value},
          ),
        );
      }
    },
    'empty native calls reject structured or extra payload fields': () {
      for (final plugin in androidPluginCatalog.values) {
        if (plugin.runtime != PluginRuntime.native) continue;
        for (final operation in plugin.operations) {
          if (operation == 'network.lookup') continue;
          for (final payload in <Map<String, dynamic>>[
            {'x': null},
            {'hostname': 'linux.do'},
            {'credentials': {'token': 'must-not-cross'}},
          ]) {
            rejects<FormatException>(
              () => AndroidPluginContract.encodeInvocation(
                plugin.id,
                operation,
                payload,
              ),
            );
          }
        }
      }
    },
    'response requires a non-null valid JSON object': () {
      for (final raw in [
        null,
        '',
        '[]',
        'null',
        'true',
        '42',
        '"ok"',
        '{',
        '{} trailing',
      ]) {
        rejects<FormatException>(
          () => AndroidPluginContract.decodeResponse(raw),
        );
      }
      final result = AndroidPluginContract.decodeResponse('{"available":true}');
      check(result['available'] == true, 'Response lost');
      rejects<UnsupportedError>(result.clear);
    },
    'response byte limit accepts the boundary and rejects multibyte overflow':
        () {
          final exact = jsonEncode({'v': 'x' * (pluginMaxJsonBytes - 8)});
          check(
            utf8.encode(exact).length == pluginMaxJsonBytes,
            'Bad boundary fixture',
          );
          AndroidPluginContract.decodeResponse(exact);
          rejects<FormatException>(
            () => AndroidPluginContract.decodeResponse('$exact '),
          );
          final multibyte = jsonEncode({'v': '汉' * 3000});
          check(multibyte.length < pluginMaxJsonBytes, 'Bad UTF-8 fixture');
          rejects<FormatException>(
            () => AndroidPluginContract.decodeResponse(multibyte),
          );
        },
    'account launches use only guest or an opaque partition': () {
      for (final id in ['cdk', 'ldc']) {
        check(
          AndroidPluginContract.launchPayload(id, {})['accountSlot'] == 'guest',
          'Guest default lost',
        );
        final payload = AndroidPluginContract.launchPayload(id, {
          'accountSlot': 'a' * 64,
        });
        check(payload['accountSlot'] == 'a' * 64, 'Partition changed');
        rejects<UnsupportedError>(payload.clear);
        for (final slot in ['', 'alice', 'A' * 64, 'a' * 63, 12]) {
          rejects<FormatException>(
            () =>
                AndroidPluginContract.launchPayload(id, {'accountSlot': slot}),
          );
        }
        rejects<FormatException>(
          () => AndroidPluginContract.launchPayload(id, {'cookie': 'secret'}),
        );
      }
    },
    'reward handoff only accepts a bounded public identity': () {
      final recipient = AndroidPluginContract.launchPayload('ldc_reward', {
        'username': ' Alice ',
        'userId': 42,
      });
      check(
        recipient['username'] == 'Alice' && recipient['userId'] == 42,
        'Identity changed',
      );
      for (final id in [null, 0, -1, 1.5, '42', 0x20000000000000]) {
        rejects<FormatException>(
          () => AndroidPluginContract.launchPayload('ldc_reward', {
            'username': 'alice',
            'userId': id,
          }),
        );
      }
      for (final name in ['', ' ', 'a' * 65, 'a\nb', 'a\u0000b']) {
        rejects<FormatException>(
          () => AndroidPluginContract.launchPayload('ldc_reward', {
            'username': name,
            'userId': 1,
          }),
        );
      }
      for (final key in ['token', 'amount', 'password']) {
        rejects<FormatException>(
          () => AndroidPluginContract.launchPayload('ldc_reward', {
            'username': 'alice',
            'userId': 1,
            key: 'secret',
          }),
        );
      }
    },
    'non-launchable modules cannot open arbitrary activities': () {
      for (final id in ['deviceinfo', 'network', 'sticker', 'unknown']) {
        rejects<ArgumentError>(
          () => AndroidPluginContract.launchPayload(id, {}),
        );
      }
    },
    'status identity comes from catalog with strict typed readiness': () {
      final valid = AndroidOptionalPlugin.fromMap(status('network'));
      check(
        valid.name == androidPluginCatalog['network']!.name && valid.compatible,
        'Untrusted name or lost readiness',
      );
      for (final patch in <Map<String, dynamic>>[
        {'id': 'unknown'},
        {'package': 'other.app'},
        {'installed': 'true'},
        {'compatible': 1},
        {'version': 1},
        {'reason': null},
        {'installed': false},
        {'reason': 'future_protocol'},
      ]) {
        rejects<FormatException>(
          () => AndroidOptionalPlugin.fromMap({...status('network'), ...patch}),
        );
      }
      final future = AndroidOptionalPlugin.fromMap({
        ...status('network'),
        'compatible': false,
        'reason': 'future_protocol',
      });
      check(
        !future.compatible && future.reason == 'future_protocol',
        'Future reason activated plugin',
      );
    },
    'status collection rejects duplicates and malformed rows': () {
      for (final items in <List<dynamic>>[
        [status('network'), status('network')],
        [status('network'), null],
        ['network'],
      ]) {
        rejects<FormatException>(() => AndroidOptionalPlugin.parseList(items));
      }
      final all = AndroidOptionalPlugin.parseList(
        androidPluginCatalog.keys.map(status),
      );
      check(all.length == 6, 'Status dropped');
      rejects<UnsupportedError>(all.clear);
    },
  };
  for (final entry in cases.entries) {
    entry.value();
    print('PASS ${entry.key}');
  }
  print('${cases.length} plugin contract scenarios passed');
}
