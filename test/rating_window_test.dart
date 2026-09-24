// 별점을 **새로** 남길 수 있는 시간 판정.
//
// 예전엔 이 판단이 meal_screen.dart 안에 식당·끼니별 시간표를 통째로 다시
// 적어 놓은 채 들어 있었다. 그래서 주석은 "종료 후 30분"이라고 적혀 있는데
// 코드는 1시간을 쓰고 있어도 아무도 몰랐다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

void main() {
  // 사도교육원 식당(a) 점심: 11:30 ~ 13:30
  final today = DateTime(2026, 9, 24);

  group('isRatingOpen — 여유 시간', () {
    test('배식 중이면 연다', () {
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 12, 30),
          today,
        ),
        isTrue,
      );
    });

    test('종료 30분 뒤까지 연다', () {
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 14, 0),
          today,
        ),
        isTrue,
      );
    });

    test('종료 31분 뒤엔 닫는다', () {
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 14, 1),
          today,
        ),
        isFalse,
      );
    });

    test('여유는 30분이다 — 1시간이 아니다', () {
      // 예전 코드가 실제로 쓰던 값. 이게 열려 있으면 되돌아간 것이다.
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 14, 30),
          today,
        ),
        isFalse,
      );
      expect(kRatingGracePeriod, const Duration(minutes: 30));
    });

    test('배식 시작 전엔 닫혀 있다', () {
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 11, 29),
          today,
        ),
        isFalse,
      );
    });

    test('시작 정각은 연다(경계 포함)', () {
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 11, 30),
          today,
        ),
        isTrue,
      );
    });
  });

  group('isRatingOpen — 날짜와 식당', () {
    test('오늘이 아니면 닫는다', () {
      // 배식 중인 시각이어도 어제 식단이면 못 남긴다.
      expect(
        isRatingOpen(
          MealType.lunch,
          MealSource.a,
          DateTime(2026, 9, 24, 12, 30),
          DateTime(2026, 9, 23),
        ),
        isFalse,
      );
    });

    test('교직원 식당 아침은 운영하지 않아 언제나 닫혀 있다', () {
      for (final hour in [7, 8, 9, 12, 18]) {
        expect(
          isRatingOpen(
            MealType.breakfast,
            MealSource.b,
            DateTime(2026, 9, 24, hour),
            today,
          ),
          isFalse,
          reason: '$hour시',
        );
      }
    });

    test('식당마다 시간이 다르다 — 교직원 저녁은 17:00~18:30', () {
      // 사도교육원 저녁(17:30~19:00)과 끝나는 시각이 다르다.
      expect(
        isRatingOpen(
          MealType.dinner,
          MealSource.b,
          DateTime(2026, 9, 24, 19, 0),
          today,
        ),
        isTrue, // 18:30 + 30분 = 19:00
      );
      expect(
        isRatingOpen(
          MealType.dinner,
          MealSource.b,
          DateTime(2026, 9, 24, 19, 1),
          today,
        ),
        isFalse,
      );
      expect(
        isRatingOpen(
          MealType.dinner,
          MealSource.a,
          DateTime(2026, 9, 24, 19, 1),
          today,
        ),
        isTrue, // 19:00 + 30분 = 19:30
      );
    });
  });

  group('isRatingOpen과 "식사하셨나요?" 팝업이 어긋나지 않는다', () {
    test('팝업이 뜨는 구간에서는 언제나 평가할 수 있다', () {
      // 팝업은 종료 10분 전부터 종료까지 뜬다. 그때 눌렀는데 "지금은 못
      // 남긴다"고 하면 팝업이 거짓말을 하는 셈이다.
      for (final source in MealSource.values) {
        for (final type in MealType.values) {
          for (var m = 0; m < 24 * 60; m++) {
            final now = DateTime(2026, 9, 24, 0, m);
            if (!isMealEndingSoon(type, source, now)) continue;
            expect(
              isRatingOpen(type, source, now, today),
              isTrue,
              reason: '$source $type ${now.hour}:${now.minute}',
            );
          }
        }
      }
    });
  });

  group('mealServiceWindow', () {
    test('문자열 시간표를 그 날짜의 시각으로 푼다', () {
      final w = mealServiceWindow(MealType.lunch, MealSource.a, today)!;
      expect(w.start, DateTime(2026, 9, 24, 11, 30));
      expect(w.end, DateTime(2026, 9, 24, 13, 30));
    });

    test('운영하지 않는 끼니는 null', () {
      expect(
        mealServiceWindow(MealType.breakfast, MealSource.b, today),
        isNull,
      );
    });

    test('statusFor와 같은 경계를 쓴다', () {
      final w = mealServiceWindow(MealType.lunch, MealSource.a, today)!;
      expect(
        statusFor(MealType.lunch, w.start, today, source: MealSource.a),
        ServeStatus.open,
      );
      expect(
        statusFor(MealType.lunch, w.end, today, source: MealSource.a),
        ServeStatus.open,
      );
      expect(
        statusFor(
          MealType.lunch,
          w.end.add(const Duration(minutes: 1)),
          today,
          source: MealSource.a,
        ),
        ServeStatus.closed,
      );
    });
  });
}
