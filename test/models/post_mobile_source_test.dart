import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('Post mobile source', () {
    test('parses top-level mobile_source fields and prefers model label', () {
      final post = Post.fromJson({
        'id': 14,
        'username': 'tester',
        'mobile_source_platform': 'android',
        'mobile_source_brand': 'Xiaomi',
        'mobile_source_model': '24129PN74C',
      });

      expect(post.mobileSourcePlatform, 'android');
      expect(post.mobileSourceBrand, 'Xiaomi');
      expect(post.mobileSourceModel, '24129PN74C');
      expect(post.mobileSourceLabel, '24129PN74C');
    });

    test('accepts nested mobile_source as a forward-compatible fallback', () {
      final post = Post.fromJson({
        'id': 15,
        'username': 'tester',
        'mobile_source': {
          'platform': 'ios',
          'brand': 'Apple',
          'model': 'iPhone17,2',
        },
      });

      expect(post.mobileSourcePlatform, 'ios');
      expect(post.mobileSourceBrand, 'Apple');
      expect(post.mobileSourceModel, 'iPhone17,2');
      expect(post.mobileSourceLabel, 'iPhone17,2');
    });

    test('falls back from model to brand then platform', () {
      final brandOnly = Post.fromJson({
        'id': 16,
        'username': 'tester',
        'mobile_source_platform': 'android',
        'mobile_source_brand': 'Redmi',
      });
      final platformOnly = Post.fromJson({
        'id': 17,
        'username': 'tester',
        'mobile_source_platform': 'ios',
      });

      expect(brandOnly.mobileSourceLabel, 'Redmi');
      expect(platformOnly.mobileSourceLabel, 'iOS');
    });
  });
}
