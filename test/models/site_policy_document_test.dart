import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_policy_document.dart';

void main() {
  test('uses the actual cooked main content rather than the Discourse nav', () {
    final page = SitePolicyDocument.fromHtml('''
      <div itemscope itemtype="http://schema.org/WebPage">
        <ul class="nav-pills"><li><a href="/about">About</a></li></ul>
        <div itemprop="mainContentOfPage">
          <p>Policy preamble.</p>
          <h2 id="important-terms">Important terms</h2>
          <p>These are <strong>important</strong>.</p>
          <h2 id="content-rules">Content rules</h2>
          <ol><li>No spam</li><li>Be friendly</li></ol>
        </div>
      </div>
    ''');

    expect(page.sections, hasLength(3));
    expect(page.sections[0].html, contains('Policy preamble'));
    expect(page.sections[0].html, isNot(contains('/about')));
    expect(page.sections[1].heading, 'Important terms');
    expect(page.sections[2].heading, 'Content rules');
    expect(page.anchors, {'important-terms': 1, 'content-rules': 2});
    expect(page.text, contains('<strong>important</strong>'));
    expect(page.text, contains('<ol>'));
  });

  test('retains heading anchors nested inside h2', () {
    final page = SitePolicyDocument.fromHtml('''
      <div itemprop="mainContentOfPage">
        <h2><a id="privacy-rights"></a>Your privacy</h2>
        <p>Text</p>
      </div>
    ''');
    expect(page.anchors['privacy-rights'], 0);
  });

  test('strips active content and javascript links', () {
    final page = SitePolicyDocument.fromHtml('''
      <div itemprop="mainContentOfPage">
        <script>alert(1)</script>
        <h2 id="first">Policy</h2>
        <p onclick="alert(2)">
          <a href="javascript:alert(3)">bad link</a>
          <a href="https://linux.do/about">good link</a>
        </p>
      </div>
    ''');
    expect(page.text, isNot(contains('<script')));
    expect(page.text, isNot(contains('onclick=')));
    expect(page.text, isNot(contains('javascript:')));
    expect(page.text, contains('https://linux.do/about'));
  });

  test('does not show a challenge or unrelated page as legal text', () {
    expect(
      () => SitePolicyDocument.fromHtml(
        '<html><body>Cloudflare challenge</body></html>',
      ),
      throwsFormatException,
    );
    expect(
      () => SitePolicyDocument.fromHtml(
        '<div itemprop="mainContentOfPage"></div>',
      ),
      throwsFormatException,
    );
  });

  test('keeps server provided text and list formatting', () {
    final page = SitePolicyDocument.fromHtml('''
      <div itemprop="mainContentOfPage">
        <h1 id="basic">基本信息</h1>
        <ul><li>社区名称：LINUX DO</li><li>成立时间：2024-01-17</li></ul>
        <blockquote>共建社区。</blockquote>
      </div>
    ''');
    expect(page.sections.single.heading, '基本信息');
    expect(page.text, contains('2024-01-17'));
    expect(page.text, contains('blockquote'));
  });
}
