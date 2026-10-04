import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat UI uses predictive-back-aware modal wrappers', () {
    final roots = <Directory>[
      Directory('lib/pages/chat'),
      Directory('lib/widgets/chat'),
    ];
    final forbidden = <RegExp>[
      RegExp(r'\\bshowModalBottomSheet(?:<[^>]+>)?\\s*\\('),
      RegExp(r'\\bshowDialog(?:<[^>]+>)?\\s*\\('),
      RegExp(r'\\bshowGeneralDialog(?:<[^>]+>)?\\s*\\('),
    ];

    final violations = <String>[];
    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final pattern in forbidden) {
          if (pattern.hasMatch(source)) {
            violations.add('${entity.path}: ${pattern.pattern}');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Chat modals must use showAppBottomSheet/showAppDialog so Android '
          'predictive back can drive the top-most route.',
    );
  });
}
