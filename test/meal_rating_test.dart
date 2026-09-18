import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/meal_rating.dart';

void main() {
  group('MealRatingSummary.fromDocs distribution', () {
    test('0.5 단계별 투표 수를 정확히 센다', () {
      final summary = MealRatingSummary.fromDocs([
        {'rating': 4.5},
        {'rating': 4.5},
        {'rating': 3.0},
        {'rating': 5.0},
      ]);

      expect(summary.count, 4);
      expect(summary.distribution[4.5], 2);
      expect(summary.distribution[3.0], 1);
      expect(summary.distribution[5.0], 1);
      // 투표가 없는 단계는 0으로 채워져 있어야 UI에서 따로 null 체크 안 해도 된다.
      expect(summary.distribution[0.5], 0);
      expect(summary.distribution.length, 10);
    });

    test('빈 목록이면 10단계 전부 0인 분포를 돌려준다', () {
      final summary = MealRatingSummary.fromDocs([]);
      expect(summary.distribution.values.every((v) => v == 0), isTrue);
      expect(summary.distribution.length, 10);
    });

    test('0.5 단위가 아닌 값(오염된 데이터)도 가장 가까운 단계로 묶는다', () {
      final summary = MealRatingSummary.fromDocs([
        {'rating': 3.7}, // *2=7.4 -> 반올림 7 -> /2 = 3.5
        {'rating': 0.1}, // 0.5 미만 -> 0.5로 clamp
        {'rating': 5.4}, // 5.0 초과 -> 5.0으로 clamp
      ]);
      expect(summary.distribution[3.5], 1);
      expect(summary.distribution[0.5], 1);
      expect(summary.distribution[5.0], 1);
    });

    test('maxDistributionCount는 가장 많이 나온 표 수를 반환한다', () {
      final summary = MealRatingSummary.fromDocs([
        {'rating': 4.5},
        {'rating': 4.5},
        {'rating': 4.5},
        {'rating': 3.0},
      ]);
      expect(summary.maxDistributionCount, 3);
    });

    test('MealRatingSummary.empty도 10단계가 전부 0으로 채워져 있다', () {
      expect(MealRatingSummary.empty.distribution.length, 10);
      expect(
        MealRatingSummary.empty.distribution.values.every((v) => v == 0),
        isTrue,
      );
    });
  });
}
