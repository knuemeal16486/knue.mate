import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  group('isMealEndingSoon / mealEndingSoonNow', () {
    // 사도교육원 식당(a) 점심: 11:30 ~ 13:30
    test('종료 10분 전이면 true', () {
      final now = DateTime(2026, 9, 18, 13, 20);
      expect(isMealEndingSoon(MealType.lunch, MealSource.a, now), isTrue);
    });

    test('종료 정각이면 아직 true(경계 포함)', () {
      final now = DateTime(2026, 9, 18, 13, 30);
      expect(isMealEndingSoon(MealType.lunch, MealSource.a, now), isTrue);
    });

    test('종료 11분 전이면 아직 false', () {
      final now = DateTime(2026, 9, 18, 13, 19);
      expect(isMealEndingSoon(MealType.lunch, MealSource.a, now), isFalse);
    });

    test('종료 1분 후면 false', () {
      final now = DateTime(2026, 9, 18, 13, 31);
      expect(isMealEndingSoon(MealType.lunch, MealSource.a, now), isFalse);
    });

    test('아침 시간대엔 점심이 안 걸린다', () {
      final now = DateTime(2026, 9, 18, 8, 0);
      expect(isMealEndingSoon(MealType.lunch, MealSource.a, now), isFalse);
    });

    // 교직원 식당(b)은 조식을 운영하지 않는다 — mealTimeRangeFor가 null을
    // 돌려주는 경로가 크래시 없이 false로 처리되는지 확인.
    test('조식 미운영 식당은 아침 시간이어도 항상 false', () {
      final now = DateTime(2026, 9, 18, 8, 0);
      expect(isMealEndingSoon(MealType.breakfast, MealSource.b, now), isFalse);
    });

    test('mealEndingSoonNow는 곧 끝나는 끼니를 하나 찾아서 돌려준다', () {
      // 사도 저녁: 17:30 ~ 19:00
      final now = DateTime(2026, 9, 18, 18, 55);
      expect(mealEndingSoonNow(MealSource.a, now), MealType.dinner);
    });

    test('아무 끼니도 곧 끝나지 않으면 null', () {
      final now = DateTime(2026, 9, 18, 15, 0); // 점심과 저녁 사이
      expect(mealEndingSoonNow(MealSource.a, now), isNull);
    });
  });
}
