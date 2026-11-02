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
    final data = Map<String, dynamic>.from(raw);
    final id =
        _string(data['slug']) ?? _string(data['id']) ?? _string(data['uuid']);
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      return null;
    }

    final suppliedUrl = _string(data['url']) ?? _string(data['path']);
    final candidate = suppliedUrl == null
        ? site.resolve('/apps/${Uri.encodeComponent(id)}')
        : site.resolve(suppliedUrl);
    // A directory response cannot launch an arbitrary origin or a non-app path.
    // The app itself may navigate normally within the hosted web container.
    if (candidate.scheme != 'https' ||
        candidate.host.toLowerCase() != site.host.toLowerCase() ||
        candidate.port != site.port ||
        candidate.pathSegments.length < 2 ||
        candidate.pathSegments[0] != 'apps' ||
        candidate.pathSegments[1] != id) {
      return null;
    }

    final icon =
        _string(data['icon_url']) ??
        _string(data['iconUrl']) ??
        _string(data['image_url']);
    final iconUri = icon == null ? null : site.resolve(icon);
    final iconUrl =
        iconUri != null &&
            (iconUri.scheme == 'https' || iconUri.scheme == 'http')
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
    required this.hasNext,
  });

  final List<MiniApp> apps;
  final int page;
  final bool hasNext;

  /// Supports both legacy arrays and {apps,total,page,per_page} responses.
  /// The server may fix per_page to 24 and use zero-based pages.
  factory MiniAppDirectory.parse(
    Object? payload, {
    required Uri site,
    required int requestedPage,
  }) {
    Object? source = payload;
    if (source is Map && source['data'] is Map) {
      source = source['data'];
    }
    final Map<dynamic, dynamic>? envelope = source is Map ? source : null;
    final rows = source is List
        ? source
        : envelope?['apps'] is List
        ? envelope!['apps'] as List
        : null;
    if (rows == null) {
      throw const FormatException('Unsupported mini app directory response');
    }
    final apps = rows
        .map((entry) => MiniApp.tryParse(entry, site: site))
        .whereType<MiniApp>()
        .toList(growable: false);
    int? number(Object? value) =>
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    final page = number(envelope?['page']) ?? requestedPage;
    final perPage = number(envelope?['per_page']) ?? 24;
    final total = number(envelope?['total']);
    return MiniAppDirectory(
      apps: apps,
      page: page,
      hasNext: total == null
          ? rows.length >= perPage && perPage > 0
          : (page + 1) * perPage < total,
    );
  }
}
