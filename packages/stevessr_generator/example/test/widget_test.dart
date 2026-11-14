import 'package:flutter_test/flutter_test.dart';
import 'package:stevessr_generator/stevessr_generator.dart';

void main() {
  test('generator package exposes a normalized default model', () {
    final params = StevessrRenderParams.defaults().normalized();
    expect(params.width, 1254);
    expect(params.height, 1254);
  });
}
