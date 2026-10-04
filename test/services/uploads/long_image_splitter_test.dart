import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/uploads/long_image_splitter.dart';

void main() {
  group('LongImageSplitter', () {
    test('只有高度至少为宽度三倍才符合长图要求', () {
      expect(const LongImageInfo(width: 1000, height: 2999).isEligible, isFalse);
      expect(const LongImageInfo(width: 1000, height: 3000).isEligible, isTrue);
    });

    test('推荐切片数量只是建议，不替代用户选择', () {
      final count = LongImageSplitter.recommendedPartCount(
        width: 1080,
        height: 12000,
      );

      expect(count, greaterThan(2));
    });

    test('严格使用用户指定的切片数量', () {
      final plan = LongImageSplitter.planForCount(
        width: 1080,
        height: 12000,
        partCount: 5,
      );

      expect(plan.partCount, 5);
      expect(plan.starts.first, 0);
      expect(plan.starts.last + plan.partHeight, 12000);
    });

    test('相邻切片约有百分之十重叠且完整覆盖原图', () {
      final plan = LongImageSplitter.planForCount(
        width: 1080,
        height: 12000,
        partCount: 6,
      );

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

    test('少于两片会被拒绝', () {
      expect(
        () => LongImageSplitter.planForCount(
          width: 1000,
          height: 4000,
          partCount: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
