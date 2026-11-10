import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/navigation/nav_entry_registry.dart';

void main() {
  test('site information is a single navigation entry', () {
    final ids = NavEntryRegistry.buildAll()
        .map((entry) => entry.id)
        .where((id) => id.startsWith('site_'))
        .toList();

    expect(ids, ['site_about']);
  });

  test('old policy shortcuts still resolve to the unified entry', () {
    for (final legacyId in [
      'site_guidelines',
      'site_terms',
      'site_privacy',
    ]) {
      expect(NavEntryRegistry.canonicalId(legacyId), 'site_about');
      expect(NavEntryRegistry.byId(legacyId)?.id, 'site_about');
    }
    expect(NavEntryRegistry.canonicalId('birthdays'), 'anniversaries');
    expect(NavEntryRegistry.canonicalId('site_about'), 'site_about');
  });
}
