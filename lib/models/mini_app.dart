/// Discourse /apps/ directory entry. All app metadata is untrusted.
class MiniApp {
  const MiniApp({
    required this.id,
    required this.name,
    required this.url,
    this.description = '',
    this.iconUrl,
    this.ageRating,
  });

  final String id;
  final String name;
  final Uri url;
  final String description;
  final String? iconUrl;
  final int? ageRating;

  static MiniApp? tryParse(Object? raw, {required Uri site}) {
    if (raw is! Map) return null;
    final data = raw;
    // A site may return both a UUID and a human-readable slug.
    // Prefer the stable ID for deduplication while accepting either URL.
    final id =
        _string(data['id']) ?? _string(data['uuid']) ?? _string(data['slug']);
    final slug = _string(data['slug']);
    final uuid = _string(data['uuid']);
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      return null;
    }

    final identifiers = <String>{
      id,
      if (slug != null) slug,
      if (uuid != null) uuid,
    };

    final suppliedUrl = _string(data['url']) ?? _string(data['path']);
    final candidate = suppliedUrl == null
        ? site.resolve('/apps/${Uri.encodeComponent(id)}')
        : _resolveUntrustedUrl(site, suppliedUrl);
    if (candidate == null) return null;

    // A directory response cannot launch an arbitrary origin or a non-app path.
    // The app itself may navigate normally within the hosted web container.
    if (candidate.scheme != 'https' ||
        candidate.host.toLowerCase() != site.host.toLowerCase() ||
        candidate.port != site.port ||
        candidate.pathSegments.length < 2 ||
        candidate.pathSegments[0] != 'apps' ||
        !identifiers.contains(candidate.pathSegments[1])) {
      return null;
    }

    final icon =
        _string(data['icon_url']) ??
        _string(data['iconUrl']) ??
        _string(data['image_url']);
    final iconUri = icon == null ? null : _resolveUntrustedUrl(site, icon);
    final iconUrl = iconUri != null && iconUri.scheme == 'https'
        ? iconUri.toString()
        : null;
    final rawRating = data['age_rating'];
    return MiniApp(
      id: id,
      name: _string(data['name']) ?? _string(data['title']) ?? id,
      description:
          _string(data['description']) ?? _string(data['summary']) ?? '',
      url: candidate,
      iconUrl: iconUrl,
      ageRating: rawRating is int
          ? rawRating
          : int.tryParse(rawRating?.toString() ?? ''),
    );
  }

  // Uri.resolve percent-encodes lone '%' characters instead of rejecting them.
  // Validate untrusted URLs before resolution so malformed escapes cannot pass.
  static final _invalidPercentEscape = RegExp(r'%(?![0-9a-fA-F]{2})');

  static Uri? _resolveUntrustedUrl(Uri site, String value) {
    if (_invalidPercentEscape.hasMatch(value)) return null;
    try {
      return site.resolve(value);
    } on FormatException {
      return null;
    }
  }

  static String? _string(Object? value) {
    if (value is! String && value is! num) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

class MiniAppDirectory {
  const MiniAppDirectory({
    required this.apps,
    required this.page,
    required this.nextPage,
    required this.hasNext,
    required this.rawCount,
  });

  final List<MiniApp> apps;
  final int page;
  final int nextPage;
  final bool hasNext;

  /// Count before unsafe/malformed entries are filtered, for pagination.
  final int rawCount;

  /// The official directory is {apps,total,page,per_page}, zero-based.
  /// Accept a few older wrappers without assuming that all servers honor
  /// a client-provided per_page value.
  factory MiniAppDirectory.parse(
    Object? payload, {
    required Uri site,
    required int requestedPage,
  }) {
    if (requestedPage < 0) {
      throw const FormatException('Invalid mini app page');
    }

    Object? source = payload;
    final wrappers = <Map>[];
    // Some plugins wrap the same response in `data` or `result`.
    // Retain outer metadata: total/per_page may live outside the app rows.
    for (var depth = 0; depth < 3 && source is Map; depth++) {
      wrappers.add(source);
      final nested = source['data'] ?? source['result'];
      if (nested is Map || nested is List) {
        source = nested;
      } else {
        break;
      }
    }

    final List? rows = source is List
        ? source
        : source is Map
        ? _rows(source)
        : null;
    if (rows == null) {
      throw const FormatException('Unsupported mini app directory response');
    }

    final apps = <MiniApp>[];
    final ids = <String>{};
    for (final row in rows) {
      final app = MiniApp.tryParse(row, site: site);
      if (app != null && ids.add(app.id)) apps.add(app);
    }

    Object? field(String snake, String camel) {
      for (final wrapper in wrappers.reversed) {
        final pagination = wrapper['pagination'] is Map
            ? wrapper['pagination'] as Map
            : null;
        final meta = wrapper['meta'] is Map ? wrapper['meta'] as Map : null;
        final value = wrapper[snake] ??
            wrapper[camel] ??
            pagination?[snake] ??
            pagination?[camel] ??
            meta?[snake] ??
            meta?[camel];
        if (value != null) return value;
      }
      return null;
    }

    int? number(Object? value) {
      if (value is int) return value;
      if (value is num && value.isFinite && value == value.toInt()) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '');
    }

    bool? boolean(Object? value) {
      if (value is bool) return value;
      if (value == 'true' || value == 1) return true;
      if (value == 'false' || value == 0) return false;
      return null;
    }

    final reportedPage = number(field('page', 'currentPage'));
    final page = reportedPage != null && reportedPage >= 0
        ? reportedPage
        : requestedPage;
    final perPage = number(field('per_page', 'perPage'));
    final pageSize = perPage != null && perPage > 0 ? perPage : 24;
    final total = number(field('total', 'totalCount'));
    final next = number(field('next_page', 'nextPage'));
    // Advance by the requested page, not the echoed page: some endpoints
    // return one-based display page numbers.
    final nextPage = next != null && next > requestedPage
        ? next
        : requestedPage + 1;
    final explicitMore = boolean(field('has_next', 'hasNext')) ??
        boolean(field('has_more', 'hasMore'));
    final hasNext = rows.isNotEmpty &&
        (explicitMore ??
            (next != null
                ? next > requestedPage
                : total != null
                ? (requestedPage + 1) * pageSize < total
                : rows.length >= pageSize));

    return MiniAppDirectory(
      apps: List.unmodifiable(apps),
      page: page,
      nextPage: nextPage,
      hasNext: hasNext,
      rawCount: rows.length,
    );
  }

  static List? _rows(Map envelope) {
    for (final key in [
      'apps', 'applications', 'mini_apps', 'items', 'results', 'entries',
    ]) {
      if (envelope[key] is List) return envelope[key] as List;
    }
    // Real directories can be nested one level under a plugin envelope.
    for (final key in ['directory', 'apps', 'data', 'result']) {
      final nested = envelope[key];
      if (nested is Map) {
        final rows = _rows(nested);
        if (rows != null) return rows;
      }
    }
    return null;
  }
}
