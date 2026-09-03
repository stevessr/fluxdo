import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo_render/fluxdo_render.dart';
import 'package:fluxdo/utils/discourse_content_extension_registry.dart';

void main() {
  final registry = DiscourseContentExtensionRegistry.instance;

  test('known native poll owns interactive descendants', () {
    const html = '''
<div class="poll" data-poll-name="poll">
  <button data-action="vote">Vote</button>
</div>
''';

    final processed = registry.preprocess(html);

    expect(processed, contains('class="poll"'));
    expect(processed, contains('data-action="vote"'));
    expect(processed, isNot(contains('fluxdo-unsupported-interactive')));

    final nodes = DiscourseExtensionParagraphParser().parse(html);
    expect(nodes.whereType<PollNode>(), hasLength(1));
  });

  test('unknown interactive root becomes explicit web fallback callout', () {
    const html = '''
<form data-controller="lottery" data-url="/t/example/42">
  <p>Join the lottery</p>
  <button type="submit">Join</button>
</form>
''';

    final processed = registry.preprocess(html);

    expect(processed, contains('fluxdo-unsupported-interactive'));
    expect(
      processed,
      contains('Interactive content requires the web version.'),
    );
    expect(processed, contains('href="/t/example/42"'));
    expect(processed, isNot(contains('<form')));

    final nodes = DiscourseExtensionParagraphParser().parse(html);
    expect(nodes.whereType<CalloutNode>(), hasLength(1));
  });

  test('runtime transform adapter overrides generic interactive fallback', () {
    const extensionId = 'test-custom-widget';
    final beforeRevision = registry.revision;
    registry.register(
      DiscourseContentExtension(
        id: extensionId,
        priority: 1000,
        mode: DiscourseContentExtensionMode.transform,
        matcher: (element) => element.classes.contains('custom-widget'),
        transform: (element, context) {
          element.classes.remove('custom-widget');
          element.innerHtml = '<p><a href="/custom">Native adapter</a></p>';
        },
      ),
    );
    addTearDown(() => registry.unregister(extensionId));

    expect(registry.revision, greaterThan(beforeRevision));

    const html = '''
<div class="custom-widget" data-controller="custom">
  <button>Old control</button>
</div>
''';
    final processed = registry.preprocess(html);

    expect(processed, contains('Native adapter'));
    expect(processed, contains('href="/custom"'));
    expect(processed, isNot(contains('fluxdo-unsupported-interactive')));

    final revisionBeforeRemoval = registry.revision;
    expect(registry.unregister(extensionId), isTrue);
    expect(registry.revision, greaterThan(revisionBeforeRemoval));
    expect(registry.unregister(extensionId), isFalse);
  });

  test('core extension ids cannot be replaced or removed', () {
    expect(registry.unregister('core-poll'), isFalse);
    expect(
      () => registry.register(
        DiscourseContentExtension(
          id: 'core-poll',
          matcher: (_) => false,
        ),
      ),
      throwsArgumentError,
    );
  });
}
