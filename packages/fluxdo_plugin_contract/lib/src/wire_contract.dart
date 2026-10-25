import 'dart:convert';

import 'catalog.g.dart';
import 'plugin_definition.dart';

/// v1 wire policy. No Flutter objects, account credentials or filesystem paths
/// belong in these messages. Transport and UI stay in the host application.
abstract final class AndroidPluginContract {
  static PluginDefinition _nativePlugin(String id) {
    final spec = androidPluginCatalog[id];
    if (spec == null || spec.runtime != PluginRuntime.native) {
      throw ArgumentError.value(id, 'id', 'Unknown native plugin');
    }
    return spec;
  }

  static String encodeInvocation(
    String id,
    String operation,
    Map<String, dynamic> payload,
  ) {
    final spec = _nativePlugin(id);
    if (!spec.operations.contains(operation)) {
      throw ArgumentError.value(
        operation,
        'operation',
        'Operation is not declared',
      );
    }
    final Map<String, dynamic> normalized;
    if (operation == 'network.lookup') {
      _keys(payload, const {'hostname'});
      final input = payload['hostname'];
      if (input is! String) {
        throw const FormatException('DNS lookup requires a hostname');
      }
      final hostname = input.trim();
      final labels =
          (hostname.endsWith('.')
                  ? hostname.substring(0, hostname.length - 1)
                  : hostname)
              .split('.');
      final label = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$');
      if (hostname.isEmpty ||
          hostname.length > 253 ||
          labels.any((value) => !label.hasMatch(value))) {
        throw const FormatException('Invalid DNS hostname');
      }
      normalized = {'hostname': hostname};
    } else {
      _keys(payload, const {});
      normalized = const {};
    }
    final encoded = jsonEncode(normalized);
    _checkSize(encoded);
    return encoded;
  }

  static Map<String, dynamic> decodeResponse(String? raw) {
    if (raw == null) {
      throw const FormatException('Plugin did not return a response');
    }
    _checkSize(raw);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Plugin response must be a JSON object');
    }
    return Map.unmodifiable(decoded);
  }

  static Map<String, dynamic> launchPayload(
    String id,
    Map<String, dynamic> payload,
  ) {
    final spec = _nativePlugin(id);
    if (!spec.hasNativeActivity) {
      throw ArgumentError.value(id, 'id', 'Plugin has no native activity');
    }
    if (id == 'cdk' || id == 'ldc') {
      _keys(payload, const {'accountSlot'});
      final slot = payload['accountSlot'] ?? 'guest';
      if (slot is! String ||
          (slot != 'guest' && !RegExp(r'^[0-9a-f]{64}$').hasMatch(slot))) {
        throw const FormatException('Invalid opaque account slot');
      }
      return Map.unmodifiable({'accountSlot': slot});
    }
    if (id == 'ldc_reward') {
      _keys(payload, const {'username', 'userId'});
      final input = payload['username'];
      final userId = payload['userId'];
      final username = input is String ? input.trim() : '';
      if (username.isEmpty ||
          username.length > 64 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(username) ||
          userId is! int ||
          userId <= 0 ||
          userId > 0x1fffffffffffff) {
        throw const FormatException('Invalid public reward recipient');
      }
      return Map.unmodifiable({'username': username, 'userId': userId});
    }
    throw ArgumentError.value(
      id,
      'id',
      'Launch contract has not been implemented',
    );
  }

  static void _keys(Map<String, dynamic> payload, Set<String> allowed) {
    if (payload.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException(
        'Undeclared fields cannot cross the plugin boundary',
      );
    }
  }

  static void _checkSize(String raw) {
    if (utf8.encode(raw).length > pluginMaxJsonBytes) {
      throw const FormatException('Plugin JSON exceeds the UTF-8 byte limit');
    }
  }
}
