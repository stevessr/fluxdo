import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/uploads/long_image_splitter.dart';

void main() {
  group('LongImageSplitter.plan', () {
    test('普通图片不切割', () {
      final plan = LongImageSplitter.plan(width: 1000, height: 2500);

      expect(plan.shouldSplit, isFalse);
      expect(plan.starts, [0]);
      expect(plan.partHeight, 2500);
    });

    test('高度达到三倍时开始切割', () {
      final plan = LongImageSplitter.plan(width: 1000, height: 3000);

      expect(plan.shouldSplit, isTrue);
      expect(plan.partCount, 2);
      expect(plan.starts.first, 0);
      expect(plan.starts.last + plan.partHeight, 3000);
    });

    test('相邻切片约有百分之十重叠且完整覆盖原图', () {
      final plan = LongImageSplitter.plan(width: 1080, height: 12000);

      expect(plan.shouldSplit, isTrue);
      expect(plan.starts.first, 0);
      expect(plan.starts.last + plan.partHeight, 12000);

      for (var i = 1; i < plan.starts.length; i++) {
        final overlap =
            plan.starts[i - 1] + plan.partHeight - plan.starts[i];
        final overlapRatio = overlap / plan.partHeight;
        expect(overlapRatio, closeTo(0.10, 0.01));
        expect(plan.starts[i], greaterThan(plan.starts[i - 1]));
      }
    });

    test('切片高度不会超过目标宽高比', () {
      final plan = LongImageSplitter.plan(width: 900, height: 9000);

      expect(plan.partHeight, lessThanOrEqualTo(1800));
      expect(plan.partCount, greaterThan(1));
    });
  });
}
