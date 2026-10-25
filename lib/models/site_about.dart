import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Discourse /about.json (the about object and its top-level users).
///
/// Read only fields exposed by the server. In particular, do not invent
/// all-time values for metrics which only exist as rolling-window counts.
class SiteAboutData {
  const SiteAboutData({
    required this.title,
    required this.description,
    required this.extendedDescription,
    required this.bannerUrl,
    required this.createdAt,
    required this.contactEmail,
    required this.stats,
    required this.users,
    required this.adminIds,
    required this.moderatorIds,
  });

  final String title;
  final String description;
  final String extendedDescription;
  final String bannerUrl;
  final DateTime? createdAt;
  final String contactEmail;
  final Map<String, dynamic> stats;
  final List<SiteAboutUser> users;
  final List<int> adminIds;
  final List<int> moderatorIds;

  factory SiteAboutData.fromJson(Map<String, dynamic> json) {
    final about = _object(json['about']);
    final rawUsers = json['users'];
    return SiteAboutData(
      title: _string(about['title']),
      description: _string(about['description']),
      extendedDescription: siteAboutHtmlToText(
        _string(about['extended_site_description']),
      ),
      bannerUrl: _string(about['banner_image']),
      createdAt: DateTime.tryParse(_string(about['site_creation_date'])),
      contactEmail: _string(about['contact_email']),
      stats: _object(about['stats']),
      users: rawUsers is List
          ? rawUsers
                .whereType<Map>()
                .map((item) => SiteAboutUser.fromJson(_object(item)))
                .where((user) => user.username.isNotEmpty)
                .toList(growable: false)
          : const [],
      adminIds: _ids(about['admin_ids']),
      moderatorIds: _ids(about['moderator_ids']),
    );
  }

  List<SiteAboutUser> get admins => _staff(adminIds);
  List<SiteAboutUser> get moderators => _staff(moderatorIds);

  List<SiteAboutUser> _staff(List<int> ids) {
    final usersById = {for (final user in users) user.id: user};
    return ids.map((id) => usersById[id]).whereType<SiteAboutUser>().toList();
  }

  /// period: count, last_day, 7_days, or 30_days.
  /// Absent numbers are unknown, not zero.
  int? stat(String metric, String period) {
    final suffix = period == 'count' ? 'count' : period;
    final value = stats[metric + '_' + suffix];
    return value is num ? value.toInt() : null;
  }

  static Map<String, dynamic> _object(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static String _string(dynamic value) => value is String ? value : '';

  static List<int> _ids(dynamic value) => value is List
      ? value.whereType<num>().map((value) => value.toInt()).toList()
      : const [];
}

class SiteAboutUser {
  const SiteAboutUser({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarTemplate,
    required this.title,
  });

  final int id;
  final String username;
  final String name;
  final String avatarTemplate;
  final String title;

  factory SiteAboutUser.fromJson(Map<String, dynamic> json) => SiteAboutUser(
    id: (json['id'] as num?)?.toInt() ?? 0,
    username: json['username'] as String? ?? '',
    name: json['name'] as String? ?? '',
    avatarTemplate: json['avatar_template'] as String? ?? '',
    title: json['title'] as String? ?? '',
  );

  String avatarPath({int size = 96}) =>
      avatarTemplate.replaceAll('{size}', '$size');
}

/// The site's extended description is HTML. Display its *text*, never raw
/// markup or script contents. Preserve the paragraph and <br> boundaries.
String siteAboutHtmlToText(String source) {
  if (source.isEmpty) return '';
  final root = html_parser.parseFragment(source);
  final buffer = StringBuffer();

  void visit(dom.Node node) {
    if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'script' || tag == 'style') return;
      if (tag == 'br') {
        buffer.writeln();
        return;
      }
      if (tag == 'p' || tag == 'div' || tag == 'li') {
        if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
          buffer.writeln();
        }
      }
      for (final child in node.nodes) {
        visit(child);
      }
      if (tag == 'p' || tag == 'div' || tag == 'li') {
        buffer.writeln();
      }
    } else if (node is dom.Text) {
      buffer.write(node.text);
    } else {
      for (final child in node.nodes) {
        visit(child);
      }
    }
  }

  for (final node in root.nodes) {
    visit(node);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
