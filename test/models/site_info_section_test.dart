import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/site_info_section.dart';

void main() {
  test('official site info URLs map to one of four workspace states', () {
    expect(SiteInfoSection.fromPath('/about'), SiteInfoSection.about);
    expect(SiteInfoSection.fromPath('/guidelines/'), SiteInfoSection.guidelines);
    expect(SiteInfoSection.fromPath('/tos'), SiteInfoSection.terms);
    expect(SiteInfoSection.fromPath('/tos/'), SiteInfoSection.terms);
    expect(SiteInfoSection.fromPath('/privacy/'), SiteInfoSection.privacy);
    expect(SiteInfoSection.fromPath('/PRIVACY'), SiteInfoSection.privacy);
    expect(SiteInfoSection.fromPath('/t/example/12'), isNull);
    expect(SiteInfoSection.fromPath('/about.json'), isNull);
    expect(SiteInfoSection.fromPath('/other/about'), isNull);
  });
}
