import 'dart:convert';

/// Decodes Discourse's outer `data-preloaded` JSON object without eagerly
/// materializing entries the native client never consumes.
///
/// The outer object usually stores each preload entry as another JSON string.
/// Using [jsonDecode] on the whole object allocates every inner raw string even
/// though startup only needs a small subset. This decoder walks the top-level
/// object once, decodes only retained entries, and keeps expensive secondary
/// payloads (topic tracking state / topic list) as raw strings for the existing
/// lazy paths.
class PreloadedDataDecoder {
  PreloadedDataDecoder._();

  static const Set<String> _eagerKeys = {
    'currentUser',
    'siteSettings',
    'site',
    'topicTrackingStateMeta',
    'customEmoji',
  };

  static const Set<String> _retainedKeys = {
    ..._eagerKeys,
    'topicTrackingStates',
    'topicList',
    'topic_list',
    'latest',
  };

  static Map<String, dynamic>? decode(
    String rawJson, {
    required bool htmlEntityEncoded,
  }) {
    final source = htmlEntityEncoded ? _decodeHtmlEntities(rawJson) : rawJson;

    try {
      return _decodeProjectedObject(source);
    } on FormatException {
      // Keep a compatibility fallback for unusual but valid JSON formatting.
      // The fast path is intentionally conservative: correctness wins over the
      // projection optimization if the lightweight scanner rejects a payload.
      return _decodeWithJsonDecoder(source);
    }
  }

  static Map<String, dynamic>? _decodeProjectedObject(String source) {
    var index = _skipWhitespace(source, 0);
    if (index >= source.length || source.codeUnitAt(index) != _leftBrace) {
      return null;
    }
    index++;

    final result = <String, dynamic>{};
    while (true) {
      index = _skipWhitespace(source, index);
      if (index >= source.length) {
        throw const FormatException('Unterminated JSON object');
      }
      if (source.codeUnitAt(index) == _rightBrace) {
        return result;
      }
      if (source.codeUnitAt(index) != _quote) {
        throw const FormatException('Expected JSON object key');
      }

      final keyEnd = _scanString(source, index);
      final key = jsonDecode(source.substring(index, keyEnd)) as String;
      index = _skipWhitespace(source, keyEnd);
      if (index >= source.length || source.codeUnitAt(index) != _colon) {
        throw const FormatException('Expected colon after JSON object key');
      }

      index = _skipWhitespace(source, index + 1);
      final valueStart = index;
      final valueEnd = _scanValue(source, valueStart);

      if (_retainedKeys.contains(key)) {
        dynamic value = jsonDecode(source.substring(valueStart, valueEnd));
        if (_eagerKeys.contains(key) && value is String) {
          try {
            value = jsonDecode(value);
          } catch (_) {
            // Match the previous implementation: an inner value that happens
            // to be a non-JSON string is preserved unchanged.
          }
        }
        result[key] = value;
      }

      index = _skipWhitespace(source, valueEnd);
      if (index >= source.length) {
        throw const FormatException('Unterminated JSON object');
      }
      final delimiter = source.codeUnitAt(index);
      if (delimiter == _comma) {
        index++;
        continue;
      }
      if (delimiter == _rightBrace) {
        return result;
      }
      throw const FormatException('Expected comma or end of JSON object');
    }
  }

  static Map<String, dynamic>? _decodeWithJsonDecoder(String source) {
    final decoded = jsonDecode(source);
    final Map<String, dynamic> outer;
    if (decoded is Map<String, dynamic>) {
      outer = decoded;
    } else if (decoded is Map) {
      outer = decoded.cast<String, dynamic>();
    } else {
      return null;
    }

    final result = <String, dynamic>{};
    for (final key in _retainedKeys) {
      if (!outer.containsKey(key)) continue;
      dynamic value = outer[key];
      if (_eagerKeys.contains(key) && value is String) {
        try {
          value = jsonDecode(value);
        } catch (_) {
          // Preserve the raw value for compatibility.
        }
      }
      result[key] = value;
    }
    return result;
  }

  static int _scanValue(String source, int start) {
    if (start >= source.length) {
      throw const FormatException('Missing JSON value');
    }

    final first = source.codeUnitAt(start);
    if (first == _quote) return _scanString(source, start);
    if (first == _leftBrace || first == _leftBracket) {
      return _scanComposite(source, start);
    }

    var index = start;
    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit == _comma || codeUnit == _rightBrace) break;
      index++;
    }
    if (index == start) {
      throw const FormatException('Missing JSON value');
    }
    return _trimTrailingWhitespace(source, start, index);
  }

  static int _scanString(String source, int start) {
    var index = start + 1;
    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit == _backslash) {
        index += 2;
        continue;
      }
      if (codeUnit == _quote) return index + 1;
      index++;
    }
    throw const FormatException('Unterminated JSON string');
  }

  static int _scanComposite(String source, int start) {
    final stack = <int>[
      source.codeUnitAt(start) == _leftBrace ? _rightBrace : _rightBracket,
    ];
    var index = start + 1;

    while (index < source.length) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit == _quote) {
        index = _scanString(source, index);
        continue;
      }
      if (codeUnit == _leftBrace) {
        stack.add(_rightBrace);
      } else if (codeUnit == _leftBracket) {
        stack.add(_rightBracket);
      } else if (codeUnit == _rightBrace || codeUnit == _rightBracket) {
        if (stack.isEmpty || stack.last != codeUnit) {
          throw const FormatException('Mismatched JSON delimiter');
        }
        stack.removeLast();
        if (stack.isEmpty) return index + 1;
      }
      index++;
    }
    throw const FormatException('Unterminated JSON composite value');
  }

  static int _skipWhitespace(String source, int index) {
    while (index < source.length && _isWhitespace(source.codeUnitAt(index))) {
      index++;
    }
    return index;
  }

  static int _trimTrailingWhitespace(String source, int start, int end) {
    var index = end;
    while (index > start && _isWhitespace(source.codeUnitAt(index - 1))) {
      index--;
    }
    return index;
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0a ||
      codeUnit == 0x0d;

  static String _decodeHtmlEntities(String rawJson) => rawJson
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'");

  static const int _quote = 0x22;
  static const int _backslash = 0x5c;
  static const int _leftBrace = 0x7b;
  static const int _rightBrace = 0x7d;
  static const int _leftBracket = 0x5b;
  static const int _rightBracket = 0x5d;
  static const int _colon = 0x3a;
  static const int _comma = 0x2c;
}
