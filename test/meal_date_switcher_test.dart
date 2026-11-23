// 청람밥상 날짜 전환(2026-11-12). 다른 날로 넘기면 "오늘의 식단" 알약이 빠져
// 날짜 묶음이 짧아지고, 고정 높이 머리(240) 안에서 날짜 아래가 비었다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/meal_screen.dart';

void main() {
  group('mealDayBadge', () {
    final today = DateTime(2026, 11, 12, 23, 30);
    test('오늘·어제·내일', () {
      expect(mealDayBadge(DateTime(2026, 11, 12, 8), today), '오늘의 식단');
      expect(mealDayBadge(DateTime(2026, 11, 11), today), '어제의 식단');
      expect(mealDayBadge(DateTime(2026, 11, 13), today), '내일의 식단');
    });
    test('더 먼 날', () {
      expect(mealDayBadge(DateTime(2026, 11, 9), today), '3일 전 식단');
      expect(mealDayBadge(DateTime(2026, 11, 15), today), '3일 후 식단');
    });
    test('시각이 달라도 날짜로만 센다(자정 직전·직후)', () {
      expect(mealDayBadge(DateTime(2026, 11, 13, 0, 5), DateTime(2026, 11, 12, 23, 55)), '내일의 식단');
    });
  });

  Widget host(DateTime date, {VoidCallback? onToday}) => MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.blue,
          body: Center(
            child: MealDateSwitcher(
              date: date,
              isToday: DateUtils.isSameDay(date, DateTime.now()),
              onPrev: () {},
              onNext: () {},
              onToday: onToday,
              primaryColor: Colors.blue,
            ),
          ),
        ),
      );

  testWidgets('다른 날로 넘겨도 높이가 같다(날짜 아래가 비지 않는다)', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(host(now));
    final todayHeight = tester.getSize(find.byType(MealDateSwitcher)).height;

    for (final delta in [-1, 1, 5]) {
      await tester.pumpWidget(host(now.add(Duration(days: delta))));
      expect(tester.getSize(find.byType(MealDateSwitcher)).height, todayHeight, reason: '$delta일');
    }
  });

  testWidgets('다른 날엔 알약을 눌러 오늘로 돌아간다', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(host(DateTime.now().add(const Duration(days: 1)), onToday: () => tapped++));
    await tester.tap(find.text('내일의 식단'));
    expect(tapped, 1);
  });

  testWidgets('오늘 알약은 눌러도 아무 일 없다', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(host(DateTime.now(), onToday: () => tapped++));
    await tester.tap(find.text('오늘의 식단'));
    expect(tapped, 0);
  });

  // 교직원 식당 ⓘ 빨간 점(2026-11-12) — 거기 선택식 메뉴·가격이 있는 걸
  // 사람들이 잘 몰랐다.
  group('showStaffMenuInfoDot', () {
    test('교직원 식당이고 안내를 안 열어 봤으면 점', () {
      expect(showStaffMenuInfoDot(MealSource.b, seen: false), isTrue);
    });
    test('한 번 열어 봤으면 점 없음', () {
      expect(showStaffMenuInfoDot(MealSource.b, seen: true), isFalse);
    });
    test('기숙사 식당엔 점 없음', () {
      expect(showStaffMenuInfoDot(MealSource.a, seen: false), isFalse);
    });
  });
}
