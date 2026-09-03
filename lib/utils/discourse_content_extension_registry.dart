import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// How an extension participates in cooked HTML preprocessing.
enum DiscourseContentExtensionMode {
  /// The downstream native parser already understands this subtree. Matching a
  /// native extension also marks the whole subtree as owned, so generic unknown
  /// interactive detection must not rewrite controls nested inside it.
  native,

  /// The extension rewrites its DOM subtree into markup understood by the
  /// native parser.
  transform,
}

typedef DiscourseContentExtensionMatcher = bool Function(dom.Element element);
typedef DiscourseContentExtensionTransform = void Function(
  dom.Element element,
  DiscourseContentExtensionContext context,
);

class DiscourseContentExtensionContext {
  const DiscourseContentExtensionContext({
    this.postId,
    this.postNumber,
  });

  final int? postId;
  final int? postNumber;
}

/// One cooked-content extension adapter.
///
/// Plugin/site-specific integrations should prefer [transform] adapters that
/// convert their DOM into the stable core vocabulary already understood by
/// `fluxdo_render` (paragraph/link/callout/details/etc.). This keeps plugin churn
/// out of the submodule's sealed Node ABI.
class DiscourseContentExtension {
  const DiscourseContentExtension({
    required this.id,
    required this.matcher,
    this.mode = DiscourseContentExtensionMode.native,
    this.priority = 0,
    this.transform,
  }) : assert(
         mode != DiscourseContentExtensionMode.transform || transform != null,
         'transform extensions require a transform callback',
       );

  final String id;
  final DiscourseContentExtensionMatcher matcher;
  final DiscourseContentExtensionMode mode;
  final int priority;
  final DiscourseContentExtensionTransform? transform;
}

/// Registry placed before `ParagraphParser`.
///
/// The existing renderer deliberately falls back unknown block elements to
/// `textContent`; that is safe for prose but dangerous for plugin widgets because
/// controls silently become inert text. This registry gives site/plugin adapters
/// a stable interception point and makes truly unknown interactive roots degrade
/// visibly instead of pretending to work.
class DiscourseContentExtensionRegistry {
  DiscourseContentExtensionRegistry._()
    : _extensions = <DiscourseContentExtension>[..._coreExtensions];

  static final DiscourseContentExtensionRegistry instance =
      DiscourseContentExtensionRegistry._();

  final List<DiscourseContentExtension> _extensions;
  int _revision = 0;

  /// Changes whenever a runtime adapter is registered/unregistered. Parse caches
  /// include this value so an adapter change cannot reuse stale BlockNode trees.
  int get revision => _revision;

  List<String> get registeredExtensionIds => List.unmodifiable(
    _sortedExtensions().map((extension) => extension.id),
  );

  void register(DiscourseContentExtension extension) {
    final index = _extensions.indexWhere((item) => item.id == extension.id);
    if (index >= 0) {
      if (_coreExtensionIds.contains(extension.id)) {
        throw ArgumentError.value(
          extension.id,
          'extension.id',
          'core extension ids cannot be replaced',
        );
      }
      _extensions[index] = extension;
    } else {
      _extensions.add(extension);
    }
    _revision++;
  }

  bool unregister(String id) {
    if (_coreExtensionIds.contains(id)) return false;
    final removed = _extensions.removeWhere((item) => item.id == id);
    if (removed == 0) return false;
    _revision++;
    return true;
  }

  /// Run all registered adapters and then convert still-unknown interactive
  /// roots into an explicit warning callout. Pure layout/prose containers are
  /// untouched and continue through the normal parser fallback path.
  String preprocess(
    String html, {
    DiscourseContentExtensionContext context =
        const DiscourseContentExtensionContext(),
  }) {
    if (html.isEmpty) return html;
    final fragment = html_parser.parseFragment(html);
    final roots = List<dom.Element>.of(fragment.children);
    for (final root in roots) {
      _visit(root, context);
    }
    return fragment.innerHtml;
  }

  void _visit(
    dom.Element element,
    DiscourseContentExtensionContext context,
  ) {
    final extension = _match(element);
    if (extension != null) {
      if (extension.mode == DiscourseContentExtensionMode.transform) {
        extension.transform!(element, context);
      }
      // A registered extension owns its subtree. This is important for poll /
      // policy widgets whose descendants can themselves look interactive.
      return;
    }

    if (_looksInteractive(element)) {
      _replaceWithUnsupportedFallback(element);
      return;
    }

    // Snapshot because transforms/replacements mutate the live DOM tree.
    for (final child in List<dom.Element>.of(element.children)) {
      _visit(child, context);
    }
  }

  DiscourseContentExtension? _match(dom.Element element) {
    for (final extension in _sortedExtensions()) {
      if (extension.matcher(element)) return extension;
    }
    return null;
  }

  List<DiscourseContentExtension> _sortedExtensions() {
    final sorted = List<DiscourseContentExtension>.of(_extensions);
    sorted.sort((a, b) => b.priority.compareTo(a.priority));
    return sorted;
  }

  static bool _hasClass(dom.Element element, String className) =>
      element.classes.contains(className);

  /// Conservative by design: only mark elements that clearly require a browser
  /// event/controller. Ordinary `data-*` used for styling/metadata is not enough
  /// by itself, avoiding false positives on normal Discourse cooked markup.
  static bool _looksInteractive(dom.Element element) {
    final tag = element.localName?.toLowerCase();
    if (const {'button', 'input', 'select', 'textarea', 'form'}.contains(tag)) {
      return true;
    }
    final attrs = element.attributes;
    if (attrs.containsKey('onclick') ||
        attrs.containsKey('onchange') ||
        attrs.containsKey('onsubmit') ||
        attrs.containsKey('data-action') ||
        attrs.containsKey('data-controller') ||
        attrs['data-interactive'] == 'true') {
      return true;
    }
    return false;
  }

  static String? _bestFallbackHref(dom.Element element) {
    for (final key in const ['data-url', 'data-href', 'href']) {
      final value = element.attributes[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    for (final link in element.querySelectorAll('a[href]')) {
      final value = link.attributes['href']?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static void _replaceWithUnsupportedFallback(dom.Element element) {
    final parent = element.parentNode;
    if (parent == null) return;

    final originalText = element.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final href = _bestFallbackHref(element);

    // fluxdo_render recognizes textual `[!WARNING]` blockquotes as CalloutNode.
    // Building DOM instead of interpolating HTML also avoids escaping/injection
    // mistakes when plugin markup contains user-provided text.
    final fallback = dom.Element.tag('blockquote')
      ..classes.add('fluxdo-unsupported-interactive')
      ..attributes['data-fxd-extension-fallback'] = 'web';
    fallback.append(
      dom.Element.tag('p')
        ..text = '[!WARNING] Interactive content requires the web version.',
    );
    if (originalText.isNotEmpty) {
      fallback.append(
        dom.Element.tag('p')
          ..text = originalText.length <= 280
              ? originalText
              : '${originalText.substring(0, 280)}…',
      );
    }
    if (href != null) {
      final paragraph = dom.Element.tag('p');
      paragraph.append(
        dom.Element.tag('a')
          ..attributes['href'] = href
          ..text = 'Open interactive content',
      );
      fallback.append(paragraph);
    }

    parent.insertBefore(fallback, element);
    element.remove();
  }

  static final List<DiscourseContentExtension> _coreExtensions = [
    DiscourseContentExtension(
      id: 'core-local-date',
      priority: 100,
      matcher: (element) =>
          element.localName == 'span' &&
          _hasClass(element, 'discourse-local-date'),
    ),
    DiscourseContentExtension(
      id: 'core-poll',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' && _hasClass(element, 'poll'),
    ),
    DiscourseContentExtension(
      id: 'core-policy',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' && _hasClass(element, 'policy'),
    ),
    DiscourseContentExtension(
      id: 'core-chat-transcript',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' && _hasClass(element, 'chat-transcript'),
    ),
    DiscourseContentExtension(
      id: 'core-details',
      priority: 100,
      matcher: (element) => element.localName == 'details',
    ),
    DiscourseContentExtension(
      id: 'core-iframe',
      priority: 100,
      matcher: (element) => element.localName == 'iframe',
    ),
    DiscourseContentExtension(
      id: 'core-video',
      priority: 100,
      matcher: (element) =>
          element.localName == 'video' ||
          (element.localName == 'div' &&
              (_hasClass(element, 'lazy-video-container') ||
                  _hasClass(element, 'video-placeholder-container') ||
                  _hasClass(element, 'video-container') ||
                  _hasClass(element, 'video-onebox'))),
    ),
    DiscourseContentExtension(
      id: 'core-audio',
      priority: 100,
      matcher: (element) => element.localName == 'audio',
    ),
    DiscourseContentExtension(
      id: 'core-onebox',
      priority: 100,
      matcher: (element) =>
          element.localName == 'aside' &&
          (_hasClass(element, 'onebox') ||
              element.classes.any((value) => value.endsWith('-onebox'))),
    ),
    DiscourseContentExtension(
      id: 'core-image-grid',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' && _hasClass(element, 'd-image-grid'),
    ),
    DiscourseContentExtension(
      id: 'core-spoiler',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' &&
          (_hasClass(element, 'spoiler') || _hasClass(element, 'spoiled')),
    ),
    DiscourseContentExtension(
      id: 'core-math',
      priority: 100,
      matcher: (element) =>
          element.localName == 'div' && _hasClass(element, 'math'),
    ),
  ];

  static final Set<String> _coreExtensionIds =
      _coreExtensions.map((extension) => extension.id).toSet();
}
