import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart' show MealSource, MealType;
import 'package:knue_mate/meal_widget.dart';

/// 식단 위젯 규칙. Swift `resolveMealWidget`·Kotlin `MealWidgetProvider.resolve`의
/// 주석 표가 이 표와 같아야 한다.
void main() {
  // 2026-11-25 수, 26 목, 27 금, 28 토.
  DateTime d(int day, [int h = 0, int m = 0, int s = 0]) =>
      DateTime(2026, 11, day, h, m, s);

  Map<String, dynamic> meals(List<String> b, List<String> l, List<String> dn) =>
      {
        'meals': {'breakfast': b, 'lunch': l, 'dinner': dn},
      };

  final payload = mealWidgetPayloadJson(
    selected: MealSource.a,
    cached: {
      MealSource.a: {
        d(25): meals(['죽'], ['비빔밥', '미역국'], ['카레']),
        d(26): meals(['토스트'], ['라면'], []),
        d(27): meals([], [], []), // 평일인데 비어 있음
        d(28): meals([], [], []), // 토요일 — 운영 안 함
        // 29일은 캐시 없음
      },
      MealSource.b: {
        d(25): {
          // 옛 Firestore 문서처럼 한국어 키
          'meals': {'중식': ['돈가스'], '석식': ['국수']},
        },
        d(26): null,
      },
    },
  );

  MealWidgetText r(DateTime now, {String? source}) =>
      resolveMealWidget(payload, now, source: source)!;

  group('payload', () {
    final root = jsonDecode(payload) as Map<String, dynamic>;
    final sources = (root['sources'] as List).cast<Map<String, dynamic>>();

    test('운영하는 끼니만, 끝나는 시각과 함께', () {
      expect(sources[0]['meals'], [
        {'key': 'breakfast', 'label': '아침', 'end': '09:00'},
        {'key': 'lunch', 'label': '점심', 'end': '13:30'},
        {'key': 'dinner', 'label': '저녁', 'end': '19:00'},
      ]);
      // 교직원 식당은 조식이 없다.
      expect((sources[1]['meals'] as List).map((m) => m['key']),
          ['lunch', 'dinner']);
    });

    test('토·일 빈 날은 closed, 평일 빈 날은 빈 목록, 캐시 없는 날은 빠진다', () {
      final days = sources[0]['days'] as Map;
      expect(days['2026-11-28'], {'closed': true});
      expect(days['2026-11-27'], {'breakfast': [], 'lunch': [], 'dinner': []});
      expect(days.containsKey('2026-11-29'), isFalse);
      expect((sources[1]['days'] as Map).keys, ['2026-11-25']);
    });

    test('한국어 키도 읽는다', () {
      expect(mealItemsOf({'중식': [' 돈가스 ', '']}, MealType.lunch), ['돈가스']);
    });
  });

  group('resolveMealWidget — 위젯 기준 표', () {
    // | 지금 | 식당 | 머리글 | 메뉴 |
    test('아침 시간이면 오늘 아침', () {
      expect(r(d(25, 8)), (title: '기숙사 식당', time: '오늘 아침', menu: '· 죽'));
    });
    test('끝나는 분 00초까지는 그 끼니, 지나면 다음 끼니', () {
      expect(r(d(25, 9, 0, 0)).time, '오늘 아침');
      expect(r(d(25, 9, 0, 1)).time, '오늘 점심');
      expect(r(d(25, 9, 0, 1)).menu, '· 비빔밥\n· 미역국');
    });
    test('저녁이 끝나면 내일 첫 끼니', () {
      expect(r(d(25, 19, 30)), (title: '기숙사 식당', time: '내일 아침', menu: '· 토스트'));
    });
    test('그 끼니 메뉴만 비었으면 등록된 메뉴 없음', () {
      expect(r(d(26, 18)).menu, kMealWidgetNoMenu);
    });
    test('평일 하루가 비었으면 등록된 메뉴 없음', () {
      expect(r(d(26, 20)).menu, kMealWidgetNoMenu); // 내일(27) 아침
    });
    test('토·일 빈 날은 운영 안 함', () {
      expect(r(d(27, 20)).menu, mealWidgetClosedText(true));
      expect(r(d(28, 12)).menu, mealWidgetClosedText(false));
    });
    test('캐시가 없는 날은 앱을 열라고 한다', () {
      expect(r(d(28, 20)).menu, kMealWidgetNoData); // 내일(29)
    });
    test('교직원 식당은 아침이 없어 아침 시간에도 점심', () {
      expect(r(d(25, 8), source: 'b'),
          (title: '교직원 식당', time: '오늘 점심', menu: '· 돈가스'));
      expect(r(d(25, 18, 30), source: 'b').menu, '· 국수');
      expect(r(d(25, 19), source: 'b').time, '내일 점심');
    });
    test('JSON이 깨졌으면 null(위젯은 옛 키로)', () {
      expect(resolveMealWidget('{', d(25)), isNull);
      expect(resolveMealWidget('{"v":1,"sources":[]}', d(25)), isNull);
    });
  });
}
