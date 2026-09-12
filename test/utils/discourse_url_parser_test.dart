import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/discourse_url_parser.dart';

void main() {
  group('平行视界左栏链接解析', () {
    test('解析分类 ID', () {
      expect(DiscourseUrlParser.parseCategory('/c/develop/42')?.categoryId, 42);
      expect(DiscourseUrlParser.parseCategory('/c/42')?.categoryId, 42);
    });

    test('解析并解码标签', () {
      expect(DiscourseUrlParser.parseTag('/tag/flutter'), 'flutter');
      expect(DiscourseUrlParser.parseTag('/tag/%E4%B8%AD%E6%96%87'), '中文');
    });

    test('只把真正的站点根路径识别为首页', () {
      expect(DiscourseUrlParser.isHomepage('/'), isTrue);
      expect(DiscourseUrlParser.isHomepage('https://linux.do/'), isTrue);
      expect(DiscourseUrlParser.isHomepage('/latest'), isFalse);
    });

    test('解析标题中的绝对 URL', () {
      final result = DiscourseUrlParser.parseTitleUrl(
        ' https://example.com/article?id=42#comments ',
      );

      expect(result?.url, 'https://example.com/article?id=42#comments');
      expect(result?.uri.host, 'example.com');
    });

    test('标题包含其它文字或非 HTTP(S) 协议时不解析', () {
      expect(
        DiscourseUrlParser.parseTitleUrl('看这篇 https://example.com/article'),
        isNull,
      );
      expect(
        DiscourseUrlParser.parseTitleUrl('mailto:user@example.com'),
        isNull,
      );
      expect(DiscourseUrlParser.parseTitleUrl('https://'), isNull);
    });

    test('空白标题与相对路径不触发精选链接', () {
      expect(DiscourseUrlParser.parseTitleUrl(''), isNull);
      expect(DiscourseUrlParser.parseTitleUrl('   '), isNull);
      // 相对路径没有 host，不能当精选链接
      expect(DiscourseUrlParser.parseTitleUrl('/t/topic/123'), isNull);
      // javascript: 等危险协议必须拦下
      expect(
        DiscourseUrlParser.parseTitleUrl('javascript:alert(1)'),
        isNull,
      );
    });

    test('协议大小写不敏感，且保留原始 URL 形态', () {
      final upper = DiscourseUrlParser.parseTitleUrl('HTTPS://Example.com/A');
      expect(upper, isNotNull);
      // url 保留用户原文（仅 trim），交给服务端规范化
      expect(upper?.url, 'HTTPS://Example.com/A');
      // Uri 会把 host 规范化为小写（路径保留原大小写）
      expect(upper?.uri.host, 'example.com');
      expect(upper?.uri.path, '/A');

      expect(DiscourseUrlParser.parseTitleUrl('http://example.com'), isNotNull);
    });

    test('协议相对 URL 补齐为 https（对齐官方 isAbsoluteUrl）', () {
      final result = DiscourseUrlParser.parseTitleUrl('//example.com/a');

      expect(result, isNotNull);
      // 原文保留，便于与标题比对
      expect(result?.url, '//example.com/a');
      // 对外使用的才是补齐后的绝对 URL
      expect(result?.absoluteUrl, 'https://example.com/a');
    });

    test('absoluteUrl 对已带协议的 URL 保持可用', () {
      final result = DiscourseUrlParser.parseTitleUrl(
        'https://example.com/a?b=1',
      );

      expect(result?.absoluteUrl, 'https://example.com/a?b=1');
    });
  });

  group('站内插件链接解析', () {
    test('解析徽章 ID 和 slug，并把 Discourse 的 - 占位符归一化', () {
      final placeholder = DiscourseUrlParser.parseBadge(
        'https://linux.do/badges/128/-',
      );
      expect(placeholder?.badgeId, 128);
      expect(placeholder?.slug, isNull);

      final named = DiscourseUrlParser.parseBadge('/badges/42/great-reader');
      expect(named?.badgeId, 42);
      expect(named?.slug, 'great-reader');

      expect(DiscourseUrlParser.parseBadge('/badges/not-a-number/-'), isNull);
    });

    test('解析 cakeday 类型和已原生支持的过滤器', () {
      final birthday = DiscourseUrlParser.parseCakeday(
        '/cakeday/birthdays/today',
      );
      expect(birthday?.birthdays, isTrue);
      expect(birthday?.filter, 'today');

      final anniversary = DiscourseUrlParser.parseCakeday(
        'https://linux.do/cakeday/anniversaries/upcoming',
      );
      expect(anniversary?.birthdays, isFalse);
      expect(anniversary?.filter, 'upcoming');

      // 官方 all 路由还包含 month query/月切换；未完整原生化前不误拦截。
      expect(
        DiscourseUrlParser.parseCakeday('/cakeday/anniversaries/all'),
        isNull,
      );
      expect(DiscourseUrlParser.parseCakeday('/cakeday/nope/today'), isNull);
    });

    test('识别 discourse-events 近期活动页面', () {
      expect(DiscourseUrlParser.isUpcomingEvents('/upcoming-events'), isTrue);
      expect(
        DiscourseUrlParser.isUpcomingEvents(
          'https://linux.do/upcoming-events/month/2026/8/31',
        ),
        isTrue,
      );
      expect(DiscourseUrlParser.isUpcomingEvents('/latest'), isFalse);
    });
  });
}