import 'package:flutter/material.dart';

import 'user_preferences_page.dart';
import 'webview_page_legacy.dart' as legacy;

/// Compatibility facade around the existing in-app browser.
///
/// Discourse user preference URLs are handled natively; every other URL keeps
/// using the existing WebView implementation unchanged.
class WebViewPage extends legacy.WebViewPage {
  const WebViewPage({
    super.key,
    required super.url,
    super.title,
    super.injectCss,
  });

  static Future<T?> open<T extends Object?>(
    BuildContext context,
    String url, {
    String? title,
    String? injectCss,
  }) {
    final username = _preferencesUsername(url);
    if (username != null) {
      return Navigator.push<T>(
        context,
        MaterialPageRoute<T>(
          builder: (_) => UserPreferencesPage(username: username),
        ),
      );
    }

    return legacy.WebViewPage.open<T>(
      context,
      url,
      title: title,
      injectCss: injectCss,
    );
  }

  static String? _preferencesUsername(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (host != 'linux.do' && !host.endsWith('.linux.do')) {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.length < 3 ||
        segments[0] != 'u' ||
        segments[2] != 'preferences') {
      return null;
    }

    final username = Uri.decodeComponent(segments[1]).trim();
    return username.isEmpty ? null : username;
  }
}
