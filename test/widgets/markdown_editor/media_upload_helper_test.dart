/// 媒体改名上传 helper:short-url 播放路径换算与标签生成。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/markdown_editor/media_upload_helper.dart';

void main() {
  group('site upload limits', () {
    test('reads max_attachment_size_kb as number or string', () {
      expect(
        mediaUploadLimitBytesFromSettings({'max_attachment_size_kb': 2048}),
        2 * 1024 * 1024,
      );
      expect(
        mediaUploadLimitBytesFromSettings({'max_attachment_size_kb': '5120'}),
        5 * 1024 * 1024,
      );
    });

    test('falls back only when site setting is unavailable or invalid', () {
      expect(
        mediaUploadLimitBytesFromSettings(null, fallbackBytes: 1234),
        1234,
      );
      expect(
        mediaUploadLimitBytesFromSettings(
          {'max_attachment_size_kb': 0},
          fallbackBytes: 4321,
        ),
        4321,
      );
      expect(
        mediaUploadLimitBytesFromSettings(
          {'max_attachment_size_kb': 1024},
          fallbackBytes: 4321,
        ),
        1024 * 1024,
      );
    });
  });

  test('upload:// 短链 → /uploads/short-url/<b62>.xz(去原扩展)', () {
    expect(
      mediaShortUrlToXzPath('upload://lwDn83PDeB3xOUoEeZI9v77qGJa.mp4'),
      '/uploads/short-url/lwDn83PDeB3xOUoEeZI9v77qGJa.xz',
    );
    expect(
      mediaShortUrlToXzPath('upload://abc'),
      '/uploads/short-url/abc.xz',
    );
    // 非短链兜底:仅换扩展
    expect(
      mediaShortUrlToXzPath('/uploads/default/original/1X/a.mp3'),
      '/uploads/default/original/1X/a.xz',
    );
  });

  test('audio 标签形态(脚本 makeTag 同款)', () {
    expect(
      buildMediaTag(
        isAudio: true,
        srcPath: '/uploads/short-url/abc.xz',
        mime: 'audio/mpeg',
      ),
      '<audio controls>\n'
      '  <source src="/uploads/short-url/abc.xz" type="audio/mpeg">\n'
      '</audio>',
    );
  });

  test('语音消息包 [wrap=voice] 壳', () {
    final tag = buildMediaTag(
      isAudio: true,
      srcPath: '/uploads/short-url/abc.xz',
      mime: 'audio/mp4',
      voice: true,
    );
    expect(tag, startsWith('[wrap=voice]\n<audio controls>'));
    expect(tag, endsWith('[/wrap]'));
  });

  test('video 标签带默认宽高', () {
    final tag = buildMediaTag(
      isAudio: false,
      srcPath: '/uploads/short-url/xyz.xz',
      mime: 'video/mp4',
    );
    expect(tag, contains('<video width="640" height="360" controls>'));
    expect(tag,
        contains('<source src="/uploads/short-url/xyz.xz" type="video/mp4">'));
  });
}
