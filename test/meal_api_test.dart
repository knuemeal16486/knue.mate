// 학교 식단 API(rssDietInfoList.do) 파서. 정보전산원이 2026-10-02에 알려 준
// 주의점을 실제 응답 모양 그대로 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/meal_api.dart';

/// 2026-10-02에 받은 실제 응답과 같은 모양(앞뒤 공백·\r·&amp;·"정보 없음").
String _xml({

  String start = '20260928',
  String end = '20261004',
  List<String> items = const [],
}) =>
    '''<?xml version='1.0' encoding='UTF-8' ?>

<rss version="2.0">
    <channel>
        <title><![CDATA[RSS - 식단표 ]]></title>
        <period>
            <StartDate><![CDATA[ $start ]]></StartDate>
            <EndDate><![CDATA[ $end ]]></EndDate>
        </period>
${items.join('\n')}
    </channel>
</rss>''';

String _item(String site, String date, String morn, String lunch, String dinner) => '''
            <item>
                <siteSe><![CDATA[ $site ]]></siteSe>
                <stdde><![CDATA[ $date ]]></stdde>
                <mornDiet><![CDATA[ $morn ]]></mornDiet>
                <lunchDiet><![CDATA[ $lunch ]]></lunchDiet>
                <dinnrDiet><![CDATA[ $dinner ]]></dinnrDiet>
            </item>''';

void main() {
  group('dietApiUri — 보내기 전에 값을 검사한다', () {
    test('식당·날짜를 주소로 만든다', () {
      expect(
        dietApiUri('one', DateTime(2026, 10, 2)).toString(),
        'https://www.knue.ac.kr/rssDietInfoList.do?siteSe=one&stdde=20261002',
      );
      expect(dietApiUri('cafe', DateTime(2026, 1, 5)).queryParameters['stdde'], '20260105');
    });

    test('모르는 식당 값은 보내지 않는다', () {
      expect(() => dietApiUri('pot', DateTime(2026, 10, 2)), throwsArgumentError);
    });

    test('말이 안 되는 날짜는 보내지 않는다', () {
      expect(() => dietApiUri('one', DateTime(1970, 1, 1)), throwsArgumentError);
    });

    test('앱의 식당과 API 값이 맞는다(a=사도교육원식당, b=교직원식당)', () {
      expect(dietSiteSeOf(MealSource.a), 'one');
      expect(dietSiteSeOf(MealSource.b), 'cafe');
    });
  });

  group('dietLines', () {
    test('끼니 머리글을 떼고 줄마다 나눈다(줄 끝 \\r 포함)', () {
      expect(dietLines(' 조식 : 백미밥\r\n근대된장국\r\n김치 '), ['백미밥', '근대된장국', '김치']);
    });

    test('CDATA 안에 남은 &amp;를 푼다', () {
      expect(dietLines('중식 : 야채스틱&amp;쌈장\r\n씨리얼&amp;우유'), ['야채스틱&쌈장', '씨리얼&우유']);
    });

    test('"정보 없음"은 빈 목록', () {
      expect(dietLines(' 조식 : 정보 없음 '), isEmpty);
    });

    test('"석박지"처럼 석으로 시작하는 메뉴를 머리글로 지우지 않는다', () {
      expect(dietLines('석식 : 석박지\r\n백미밥'), ['석박지', '백미밥']);
    });

    test('대괄호 안내 문구는 메뉴로 세지 않는다', () {
      expect(dietLines('중식 : 백미밥\r\n[알레르기 정보]'), ['백미밥']);
    });
  });

  group('parseDietWeek', () {
    final week = _xml(items: [
      _item('사도교육원', '20260928', '조식 : 백미밥\r\n김치', '중식 : 오므라이스', '석식 : 참치찌개'),
      _item('사도교육원', '20261004', '조식 : 모닝빵&amp;딸기잼', '중식 : 정보 없음', '석식 : 정보 없음'),
    ]);

    test('한 주치를 날짜별로 읽는다(값 앞뒤 공백 제거)', () {
      final w = parseDietWeek(week, siteSe: 'one', requested: DateTime(2026, 10, 2))!;
      expect(w.start, DateTime(2026, 9, 28));
      expect(w.end, DateTime(2026, 10, 4));
      expect(w.mealsOn(DateTime(2026, 9, 28))['breakfast'], ['백미밥', '김치']);
      expect(w.mealsOn(DateTime(2026, 10, 4))['breakfast'], ['모닝빵&딸기잼']);
      expect(w.mealsOn(DateTime(2026, 10, 4))['lunch'], isEmpty);
    });

    test('그 주에 항목이 없는 날은 빈 끼니', () {
      final w = parseDietWeek(week, siteSe: 'one', requested: DateTime(2026, 10, 2))!;
      expect(w.mealsOn(DateTime(2026, 10, 1)).values.every((l) => l.isEmpty), isTrue);
    });

    test('요청한 날짜가 응답 범위 밖이면 버린다 — 다른 주 메뉴를 믿지 않는다', () {
      expect(parseDietWeek(week, siteSe: 'one', requested: DateTime(2026, 10, 5)), isNull);
    });

    test('다른 식당의 응답이면 버린다', () {
      expect(parseDietWeek(week, siteSe: 'cafe', requested: DateTime(2026, 10, 2)), isNull);
      final cafe = _xml(items: [_item('교직원식당', '20260928', '조식 : 정보 없음', '중식 : 카레', '석식 : 우동')]);
      expect(parseDietWeek(cafe, siteSe: 'cafe', requested: DateTime(2026, 9, 28)), isNotNull);
    });

    test('200이어도 식단 XML이 아니면 버린다(오류 응답이 일정하지 않다)', () {
      expect(parseDietWeek('<html><body>오류</body></html>', siteSe: 'one', requested: DateTime(2026, 10, 2)), isNull);
      expect(parseDietWeek(_xml(), siteSe: 'one', requested: DateTime(2026, 10, 2)), isNull);
      expect(
        parseDietWeek(_xml(start: '2026', end: 'x'), siteSe: 'one', requested: DateTime(2026, 10, 2)),
        isNull,
      );
    });
  });

  group('isPastMealDate', () {
    final now = DateTime(2026, 10, 2, 9);
    test('어제까지는 지난 날짜 — 다시 묻지 않는다', () {
      expect(isPastMealDate(DateTime(2026, 10, 1, 23), now), isTrue);
    });
    test('오늘과 이후는 갱신 대상', () {
      expect(isPastMealDate(DateTime(2026, 10, 2), now), isFalse);
      expect(isPastMealDate(DateTime(2026, 10, 3), now), isFalse);
    });
  });

  group('mealCacheIsFinal — 언제 다시 확인하지 않아도 되는가', () {
    final now = DateTime(2026, 10, 2, 9);
    final withMenu = {
      'meals': {'breakfast': <String>[], 'lunch': ['백미밥'], 'dinner': <String>[]},
    };
    final empty = {
      'meals': {'breakfast': <String>[], 'lunch': <String>[], 'dinner': <String>[]},
    };

    test('메뉴가 있는 지난 날짜는 그대로 쓴다', () {
      expect(mealCacheIsFinal(withMenu, DateTime(2026, 10, 1), now), isTrue);
    });

    test('비어 있는 지난 날짜는 다시 확인한다 — 미리 열어 봐서 빈 값이 굳지 않게', () {
      expect(mealCacheIsFinal(empty, DateTime(2026, 10, 1), now), isFalse);
    });

    test('오늘·내일은 메뉴가 있어도 갱신 대상(변경 반영)', () {
      expect(mealCacheIsFinal(withMenu, DateTime(2026, 10, 2), now), isFalse);
      expect(mealCacheIsFinal(withMenu, DateTime(2026, 10, 3), now), isFalse);
    });
  });

  test('월요일 계산', () {
    expect(dietMondayOf(DateTime(2026, 10, 2, 15)), DateTime(2026, 9, 28));
    expect(dietMondayOf(DateTime(2026, 10, 4)), DateTime(2026, 9, 28));
    expect(dietMondayOf(DateTime(2026, 9, 28)), DateTime(2026, 9, 28));
  });
}
