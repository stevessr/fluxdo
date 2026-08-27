import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The default hosts list shown by the custom-hosts importer.
const String defaultCustomHostsUrl =
    'https://github.com/JimmyJLNU/FastHosts/raw/refs/heads/master/hosts';

/// Keep imports bounded so an accidentally selected large file cannot consume
/// an unbounded amount of memory in the app.
const int maxCustomHostsFileBytes = 8 * 1024 * 1024;

class CustomHostsParseResult {
  const CustomHostsParseResult({required this.hosts});

  final Map<String, List<String>> hosts;

  int get hostCount => hosts.length;

  int get addressCount =>
      hosts.values.fold<int>(0, (total, addresses) => total + addresses.length);
}

/// Downloads and parses hosts files in the same simple format used by the
/// operating system: `address hostname [alias ...]`, with blank lines and
/// comments ignored.
class CustomHostsService {
  CustomHostsService._();

  static const _downloadTimeout = Duration(seconds: 20);
  static const _maxHosts = 100000;
  static const _maxAddressesPerHost = 32;

  static Future<String> downloadFromUrl(String rawUrl) async {
    final uri = _parseHttpsUrl(rawUrl);
    final client = http.Client();
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['Accept'] = 'text/plain';
      final response = await client.send(request).timeout(_downloadTimeout);

      final finalUri = response.request?.url;
      if (finalUri != null && finalUri.scheme != 'https') {
        throw const FormatException('重定向后的地址必须使用 HTTPS');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('服务器返回 HTTP ${response.statusCode}');
      }

      final bytes = BytesBuilder(copy: false);
      var length = 0;
      await for (final chunk in response.stream) {
        length += chunk.length;
        if (length > maxCustomHostsFileBytes) {
          throw const FormatException('hosts 文件超过 8 MB');
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } on TimeoutException {
      throw const FormatException('下载 hosts 文件超时');
    } finally {
      client.close();
    }
  }

  static Future<String> readFile(String path) async {
    final file = File(path);
    final length = await file.length();
    if (length > maxCustomHostsFileBytes) {
      throw const FormatException('hosts 文件超过 8 MB');
    }
    return utf8.decode(await file.readAsBytes(), allowMalformed: true);
  }

  static String decodeBytes(Uint8List bytes) {
    if (bytes.length > maxCustomHostsFileBytes) {
      throw const FormatException('hosts 文件超过 8 MB');
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static CustomHostsParseResult parse(String content) {
    final hosts = <String, List<String>>{};
    var firstLine = true;

    for (var line in const LineSplitter().convert(content)) {
      if (firstLine) {
        line = line.replaceFirst('\uFEFF', '');
        firstLine = false;
      }

      final commentIndex = line.indexOf('#');
      if (commentIndex >= 0) {
        line = line.substring(0, commentIndex);
      }
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 2) continue;

      final address = normalizeIp(fields.first);
      if (address == null) continue;

      for (final rawHost in fields.skip(1)) {
        final host = normalizeHost(rawHost);
        if (host == null) continue;

        final addresses = hosts.putIfAbsent(host, () => <String>[]);
        if (!addresses.contains(address) &&
            addresses.length < _maxAddressesPerHost) {
          addresses.add(address);
        }
        if (hosts.length >= _maxHosts) break;
      }
      if (hosts.length >= _maxHosts) break;
    }

    final normalized = <String, List<String>>{
      for (final entry in hosts.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    return CustomHostsParseResult(
      hosts: Map<String, List<String>>.unmodifiable(normalized),
    );
  }

  /// Normalizes a decoded preference payload and drops malformed entries.
  static Map<String, List<String>> normalizeOverrides(
    Map<dynamic, dynamic> raw,
  ) {
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final host = normalizeHost(entry.key.toString());
      final values = entry.value;
      if (host == null || values is! List) continue;

      final addresses = <String>[];
      for (final value in values) {
        final address = normalizeIp(value.toString());
        if (address != null && !addresses.contains(address)) {
          addresses.add(address);
        }
        if (addresses.length >= _maxAddressesPerHost) break;
      }
      if (addresses.isNotEmpty) {
        result[host] = List<String>.unmodifiable(addresses);
      }
      if (result.length >= _maxHosts) break;
    }
    return Map<String, List<String>>.unmodifiable(result);
  }

  static String? normalizeHost(String raw) {
    var host = raw.trim().toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty || host.length > 253) return null;
    if (host.startsWith('.') ||
        host.contains('..') ||
        host.contains('/') ||
        host.contains('\\') ||
        host.contains(':') ||
        host.contains('*') ||
        host.contains('?') ||
        host.contains('[') ||
        host.contains(']')) {
      return null;
    }
    if (host.codeUnits.any((unit) => unit <= 0x20 || unit == 0x7f)) {
      return null;
    }
    return host;
  }

  static String? normalizeIp(String raw) {
    final address = InternetAddress.tryParse(raw.trim());
    return address?.address;
  }

  static Uri _parseHttpsUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('地址必须以 https:// 开头');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('地址不能包含用户名或密码');
    }
    return uri;
  }
}
