import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Forum-owned policy pages rendered by Discourse StaticController.
/// These pages have HTML (not JSON) responses even for AJAX requests.
enum SitePolicyKind {
  guidelines('guidelines'),
  terms('tos'),
  privacy('privacy');

  const SitePolicyKind(this.path);

  final String path;
}

class SitePolicySection {
  const SitePolicySection({
    required this.html,
    this.heading,
    this.anchor,
  });

  final String html;
  final String? heading;
  final String? anchor;
}

class SitePolicyDocument {
  const SitePolicyDocument({
    required this.sections,
    required this.anchors,
  });

  final List<SitePolicySection> sections;

  /// Heading IDs are supplied by Discourse. Never generate a different slug
  /// based on translated heading text; the original #links must still work.
  final Map<String, int> anchors;

  String get text => sections.map((section) => section.html).join();

  /// Parses the Discourse static/show HTML fragment, extracting only the cooked
  /// topic body. A 200 response can be a Cloudflare challenge or login page,
  /// so accepting arbitrary HTML would misleadingly show the wrong document.
  factory SitePolicyDocument.fromHtml(String source) {
    final document = html_parser.parse(source);
    final content = document.querySelector('[itemprop="mainContentOfPage"]');
    if (content == null) {
      throw const FormatException('Discourse policy content not found');
    }

    // Cooked posts are already sanitized server-side, but also remove active
    // elements and non-HTTP links before handing the HTML to FluxdoRender.
    for (final element in content.querySelectorAll(
      'script, style, iframe, object, embed, form, noscript',
    )) {
      element.remove();
    }
    for (final element in content.querySelectorAll('*')) {
      for (final key in element.attributes.keys.toList()) {
        if (key.toLowerCase().startsWith('on')) {
          element.attributes.remove(key);
        }
      }
      final href = element.attributes['href'];
      if (href != null && !_allowedLink(href)) {
        element.attributes.remove('href');
      }
      final src = element.attributes['src'];
      if (src != null && !_allowedImage(src)) {
        element.attributes.remove('src');
      }
    }

    final parts = <SitePolicySection>[];
    final anchors = <String, int>{};
    final buffer = StringBuffer();
    String? heading;
    String? anchor;

    void flush() {
      final html = buffer.toString().trim();
      if (html.isNotEmpty) {
        final index = parts.length;
        parts.add(SitePolicySection(
          html: html,
          heading: heading,
          anchor: anchor,
        ));
        if (anchor != null && anchor!.isNotEmpty) {
          anchors.putIfAbsent(anchor!, () => index);
        }
      }
      buffer.clear();
    }

    for (final node in content.nodes) {
      if (node is dom.Element && _headingTags.contains(node.localName)) {
        flush();
        heading = node.text.trim();
        anchor = node.id;
        if (anchor == null || anchor!.isEmpty) {
          anchor = node.querySelector('[id]')?.id;
        }
        if (anchor == null || anchor!.isEmpty) {
          anchor = node.querySelector('a[name]')?.attributes['name'];
        }
      }
      buffer.write(node.outerHtml);
    }
    flush();

    if (parts.isEmpty) {
      throw const FormatException('Empty Discourse policy page');
    }
    return SitePolicyDocument(sections: parts, anchors: anchors);
  }

  static const _headingTags = {
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  };

  static bool _allowedLink(String link) {
    final value = link.trim();
    if (value.startsWith('#') || value.startsWith('/')) {
      return !value.startsWith('///');
    }
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' ||
            uri.scheme == 'http' ||
            uri.scheme == 'mailto');
  }

  static bool _allowedImage(String src) {
    final value = src.trim();
    if (value.startsWith('/')) return true;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http');
  }
}
