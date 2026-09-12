import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/config/discourse_instance_runtime.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/utils/url_helper.dart';

void main() {
  setUp(() {
    DiscourseInstanceRuntime.reset();
    UrlHelper.debugSetOverrides(
      baseUri: '',
      cdnUrl: 'https://cdn.example.com',
      s3CdnUrl: 'https://cdn3.example.com',
      s3BaseUrl: '//uploads.example.com',
    );
  });

  tearDown(() {
    UrlHelper.debugClearOverrides();
    DiscourseInstanceRuntime.reset();
  });

  group('UrlHelper.resolveUrl', () {
    test('keeps internal page links on origin host', () {
      expect(
        UrlHelper.resolveUrl('/t/topic-slug/123'),
        'https://linux.do/t/topic-slug/123',
      );
    });

    test('keeps relative upload paths on origin host', () {
      expect(
        UrlHelper.resolveUrl('/uploads/short-url/test.pdf'),
        'https://linux.do/uploads/short-url/test.pdf',
      );
      expect(
        UrlHelper.resolveUrl('/uploads/default/optimized/1X/test_2_690x200.png'),
        'https://linux.do/uploads/default/optimized/1X/test_2_690x200.png',
      );
    });

    test('adds discourse baseUri for relative internal links', () {
      UrlHelper.debugSetOverrides(
        baseUri: '/forum',
        cdnUrl: 'https://cdn.example.com',
        s3CdnUrl: 'https://cdn3.example.com',
        s3BaseUrl: '//uploads.example.com',
      );

      expect(
        UrlHelper.resolveUrl('/t/topic-slug/123'),
        'https://linux.do/forum/t/topic-slug/123',
      );
      expect(
        UrlHelper.resolveUrl('/forum/t/topic-slug/123'),
        'https://linux.do/forum/t/topic-slug/123',
      );
      expect(
        UrlHelper.resolveUrl('/'),
        'https://linux.do/forum',
      );
    });

    test('uses active instance root before preload exposes baseUri', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'local-forum',
        baseUrl: 'http://forum.example.test/forum',
      );
      UrlHelper.debugClearOverrides();

      expect(
        UrlHelper.resolveUrl('/t/topic-slug/123'),
        'http://forum.example.test/forum/t/topic-slug/123',
      );
      expect(
        UrlHelper.resolveUrl('//forum.example.test/uploads/a.png'),
        'http://forum.example.test/uploads/a.png',
      );
    });

    test('does not rewrite protocol-relative S3 URL when not using CDN helper', () {
      expect(
        UrlHelper.resolveUrl('//uploads.example.com/original/1X/test.png'),
        'https://uploads.example.com/original/1X/test.png',
      );
    });
  });

  group('UrlHelper.resolveUrlWithCdn', () {
    test('uses CDN for relative media paths', () {
      expect(
        UrlHelper.resolveUrlWithCdn(
          '/uploads/default/optimized/1X/test_2_690x200.png',
        ),
        'https://cdn.example.com/uploads/default/optimized/1X/test_2_690x200.png',
      );
      expect(
        UrlHelper.resolveUrlWithCdn('/images/emoji/twitter/smile.png?v=12'),
        'https://cdn.example.com/images/emoji/twitter/smile.png?v=12',
      );
    });

    test('adds discourse baseUri for CDN relative media paths', () {
      UrlHelper.debugSetOverrides(
        baseUri: '/forum',
        cdnUrl: 'https://cdn.example.com',
        s3CdnUrl: 'https://cdn3.example.com',
        s3BaseUrl: '//uploads.example.com',
      );

      expect(
        UrlHelper.resolveUrlWithCdn('/images/emoji/twitter/smile.png?v=12'),
        'https://cdn.example.com/forum/images/emoji/twitter/smile.png?v=12',
      );
      expect(
        UrlHelper.resolveUrlWithCdn(
          '/forum/images/emoji/twitter/smile.png?v=12',
        ),
        'https://cdn.example.com/forum/images/emoji/twitter/smile.png?v=12',
      );
    });

    test('rewrites protocol-relative S3 URL to S3 CDN', () {
      expect(
        UrlHelper.resolveUrlWithCdn(
          '//uploads.example.com/original/1X/test.png',
        ),
        'https://cdn3.example.com/original/1X/test.png',
      );
    });
  });

  group('UrlHelper trust boundary', () {
    test('generic instance does not implicitly trust arbitrary subdomains', () {
      DiscourseInstanceRuntime.activate(
        instanceId: 'generic',
        baseUrl: 'https://forum.example.com',
      );
      UrlHelper.debugSetOverrides(
        baseUri: '',
        cdnUrl: null,
        s3CdnUrl: null,
        s3BaseUrl: null,
      );

      expect(
        UrlHelper.isTrustedImageHost(Uri.parse('https://forum.example.com/a')),
        isTrue,
      );
      expect(
        UrlHelper.isTrustedImageHost(
          Uri.parse('https://evil.forum.example.com/a'),
        ),
        isFalse,
      );
    });
  });

  group('ResolvedUploadUrl', () {
    test('uses full media URL for images', () {
      final resolved = ResolvedUploadUrl(
        url: '/uploads/default/original/1X/test.png',
        shortPath: '/uploads/short-url/test.png',
      );

      expect(
        resolved.mediaUrl(),
        'https://cdn.example.com/uploads/default/original/1X/test.png',
      );
    });

    test('uses short_path for attachment links', () {
      final resolved = ResolvedUploadUrl(
        url: '/uploads/default/original/1X/test.pdf',
        shortPath: '/uploads/short-url/test.pdf',
      );

      expect(
        resolved.linkUrl(secureUploads: false),
        '/uploads/short-url/test.pdf',
      );
    });

    test('uses full secure URL for secure attachment links', () {
      final resolved = ResolvedUploadUrl(
        url: '/secure-uploads/default/original/1X/test.pdf',
        shortPath: '/uploads/short-url/test.pdf',
      );

      expect(
        resolved.linkUrl(secureUploads: true),
        '/secure-uploads/default/original/1X/test.pdf',
      );
    });
  });
}
