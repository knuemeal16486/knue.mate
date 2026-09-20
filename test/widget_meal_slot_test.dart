import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

/// 홈 위젯이 "지금 어떤 끼니를 보여줄지" 고르는 규칙.
///
/// 예전엔 위젯이 시간대를 따로 하드코딩했는데 실제 운영 시간
/// (mealTimeRangeFor)과 어긋나 있었다. 특히 학생회관 저녁은 18:30까지인데
/// 위젯은 18:00에 이미 "내일 점심"으로 넘어가 **아직 파는 저녁을 숨겼다.**
///
/// 운영 시간
///   기숙사(a):   아침 07:30~09:00 / 점심 11:30~13:30 / 저녁 17:30~19:00
///   학생회관(b): 아침 없음        / 점심 11:00~14:00 / 저녁 17:00~18:30
DateTime _at(int h, int m) => DateTime(2026, 9, 21, h, m);

void main() {
  group('기숙사(a)', () {
    const src = MealSource.a;

    test('이른 새벽엔 오늘 아침', () {
      final s = widgetMealSlot(src, _at(6, 0));
      expect(s.type, MealType.breakfast);
      expect(s.isTomorrow, isFalse);
    });

    test('아침 시간 중엔 아침', () {
      expect(widgetMealSlot(src, _at(8, 0)).type, MealType.breakfast);
    });

    test('아침이 끝나는 09:00 정각까지는 아침', () {
      expect(widgetMealSlot(src, _at(9, 0)).type, MealType.breakfast);
    });

    test('09:01엔 점심으로 넘어간다', () {
      expect(widgetMealSlot(src, _at(9, 1)).type, MealType.lunch);
    });

    test('점심이 끝나는 13:30까지는 점심', () {
      expect(widgetMealSlot(src, _at(13, 30)).type, MealType.lunch);
    });

    test('13:31엔 저녁', () {
      expect(widgetMealSlot(src, _at(13, 31)).type, MealType.dinner);
    });

    test('저녁이 끝나는 19:00까지는 저녁', () {
      final s = widgetMealSlot(src, _at(19, 0));
      expect(s.type, MealType.dinner);
      expect(s.isTomorrow, isFalse);
    });

    test('19:01엔 내일 아침', () {
      final s = widgetMealSlot(src, _at(19, 1));
      expect(s.type, MealType.breakfast);
      expect(s.isTomorrow, isTrue);
    });
  });

  group('학생회관(b) — 조식 미운영', () {
    const src = MealSource.b;

    test('아침엔 아침이 아니라 오늘 점심을 보여준다', () {
      // 이 식당은 조식을 안 하므로 아침을 띄우면 안 된다.
      final s = widgetMealSlot(src, _at(8, 0));
      expect(s.type, MealType.lunch);
      expect(s.isTomorrow, isFalse);
    });

    test('점심이 끝나는 14:00까지는 점심', () {
      expect(widgetMealSlot(src, _at(14, 0)).type, MealType.lunch);
    });

    test('14:01엔 저녁', () {
      expect(widgetMealSlot(src, _at(14, 1)).type, MealType.dinner);
    });

    test('18:00~18:30엔 아직 저녁이다 (예전 버그)', () {
      // 예전 위젯은 18시에 "내일 점심"으로 넘어가 저녁을 숨겼다.
      for (final m in [0, 15, 30]) {
        final s = widgetMealSlot(src, _at(18, m));
        expect(s.type, MealType.dinner, reason: '18:$m');
        expect(s.isTomorrow, isFalse, reason: '18:$m');
      }
    });

    test('18:31엔 내일 점심', () {
      final s = widgetMealSlot(src, _at(18, 31));
      expect(s.type, MealType.lunch);
      expect(s.isTomorrow, isTrue);
    });
  });

  group('가져올 날짜가 보여줄 끼니와 항상 일치한다', () {
    test('하루를 1분 단위로 훑어도 어긋나지 않는다', () {
      // 라벨은 "오늘 저녁"인데 내일 메뉴를 받아오는 식의 어긋남을 막는다.
      for (final src in MealSource.values) {
        for (var minute = 0; minute < 24 * 60; minute++) {
          final now = DateTime(2026, 9, 21).add(Duration(minutes: minute));
          final slot = widgetMealSlot(src, now);
          final target = getWidgetTargetDateAt(src, now);
          final targetIsTomorrow = target.day != now.day;
          expect(
            targetIsTomorrow,
            slot.isTomorrow,
            reason: '$src ${now.hour}:${now.minute} — '
                '라벨(${slot.isTomorrow ? "내일" : "오늘"})과 '
                '받아올 날짜가 어긋남',
          );
        }
      }
    });
  });
}
