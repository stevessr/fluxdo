import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful add-account login resets account-scoped state before reload', () {
    final source = File(
      'lib/pages/account_manage_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _addAccount() async');
    final end = source.indexOf('\n  @override\n  Widget build', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final addAccount = source.substring(start, end);
    final complete = addAccount.indexOf(
      'await _manager.completeNewLogin(success: success);',
    );
    final successGuard = addAccount.indexOf('if (success)', complete);
    final reset = addAccount.indexOf(
      'await AppStateRefresher.resetForAccountSwitch(',
      successGuard,
    );
    final reload = addAccount.indexOf('await _reload();', reset);

    expect(complete, greaterThanOrEqualTo(0));
    expect(successGuard, greaterThan(complete));
    expect(reset, greaterThan(successGuard));
    expect(reload, greaterThan(reset));
  });
}
