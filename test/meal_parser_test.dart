// 식단 파싱 회귀 테스트. 네트워크를 타지 않는다.
//
// pot.knue.ac.kr(교직원 식당)은 "이번 주" 한 주치만 싣는데, 예전 파서는 요일
// div만 보고 골랐다. 그래서 다른 주의 날짜를 물으면 이번 주 같은 요일 메뉴를
// 그대로 돌려줬고, 그 값이 공용 Firestore에 굳어 2주 내내 틀린 메뉴가 나갔다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/constants.dart';

/// pot 페이지의 하루치 구조를 줄여 옮긴 것.
/// 실제 표 두 개(교직원 식당, 기숙사 식당) 중 첫 번째만 읽는다.
String potDay(String id, DateTime shown, String lunch) {
  final d = '${shown.year}년 '
      '${shown.month.toString().padLeft(2, '0')}월 '
      '${shown.day.toString().padLeft(2, '0')}일';
  return '''
<div id="$id">
  <p>교직원 식당 ( $d )</p>
  <table class="tbl_4"><tbody>
    <tr><th>아침</th><td></td></tr>
    <tr><th>점심</th><td>$lunch</td></tr>
    <tr><th>저녁</th><td>백미밥
콩나물국</td></tr>
  </tbody></table>
  <table class="tbl_4" summary="기숙사 식당 식단을 제공합니다."><tbody>
    <tr><th>아침</th><td></td></tr>
    <tr><th>점심</th><td></td></tr>
    <tr><th>저녁</th><td></td></tr>
  </tbody></table>
</div>''';
}

void main() {
  // 페이지가 항상 "이번 주"를 싣는다는 성질에 걸린 동작이라, 고정 날짜를
  // 박으면 다음 주에 테스트가 깨진다. 실행 시점 기준으로 만든다.
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final wed = monday.add(const Duration(days: 2));
  final thu = monday.add(const Duration(days: 3));

  group('교직원 식당(pot) 파싱', () {
    test('이번 주 날짜는 그 날 메뉴를 읽는다', () {
      final html = potDay('wed_list', wed, '카레라이스\n미소된장국');
      final meals = parseCafeHtml(html, wed)['meals'] as Map;
      expect(meals['lunch'], ['카레라이스', '미소된장국']);
      expect(meals['dinner'], ['백미밥', '콩나물국']);
      expect(meals['breakfast'], isEmpty, reason: '교직원 식당은 조식 미운영');
    });

    test('다른 주 날짜에는 이번 주 메뉴를 주지 않는다', () {
      // 이것이 실제로 났던 사고다. 8/31에 9/16을 물었더니 9/2 메뉴가 돌아왔다.
      final html = potDay('wed_list', wed, '카레라이스\n미소된장국');
      final nextWed = wed.add(const Duration(days: 7));
      final meals = parseCafeHtml(html, nextWed)['meals'] as Map;
      expect(meals['lunch'], isEmpty);
      expect(meals['dinner'], isEmpty);

      final prevWed = wed.subtract(const Duration(days: 7));
      final old = parseCafeHtml(html, prevWed)['meals'] as Map;
      expect(old['lunch'], isEmpty);
    });

    test('페이지가 밝힌 날짜가 다르면 버린다', () {
      // 같은 주 안이어도, 페이지가 다른 날짜를 싣고 있으면 믿지 않는다.
      final html = potDay('thu_list', thu.subtract(const Duration(days: 7)),
          '짜장덮밥');
      final meals = parseCafeHtml(html, thu)['meals'] as Map;
      expect(meals['lunch'], isEmpty);
    });

    test('끼니 머리글과 대괄호 주석은 메뉴로 세지 않는다', () {
      final html = potDay('wed_list', wed,
          '백미밥\n[11:30~13:00]\n중식\n석박지');
      final meals = parseCafeHtml(html, wed)['meals'] as Map;
      expect(meals['lunch'], ['백미밥', '석박지'],
          reason: '"석박지"는 메뉴이고 "중식"은 머리글이다');
    });
  });

  group('기숙사 식당(www) 파싱', () {
    // 이쪽은 표 머리글에 날짜가 붙어 있어 원래부터 날짜로 골라 왔다.
    String sadoWeek(DateTime monday) {
      final th = [
        for (var i = 0; i < 7; i++)
          '<th data-day="$i"><span>'
              '${monday.add(Duration(days: i)).month.toString().padLeft(2, '0')}/'
              '${monday.add(Duration(days: i)).day.toString().padLeft(2, '0')}'
              '</span></th>'
      ].join();
      String row(String menu) => '<tr>${[
            for (var i = 0; i < 7; i++)
              '<td data-day="$i"><ul class="menu_list"><li>'
                  '${i == 2 ? menu : "다른날"}</li></ul></td>'
          ].join()}</tr>';
      return '<table class="p-calendar-list"><thead><tr>$th</tr></thead>'
          '<tbody>${row("백미밥\n북엇국")}${row("참치마요덮밥")}${row("들깨미역국")}'
          '</tbody></table>';
    }

    test('요청한 날짜의 칸을 읽는다', () {
      final meals = parseSadoHtml(sadoWeek(monday), wed)['meals'] as Map;
      expect(meals['breakfast'], ['백미밥', '북엇국']);
      expect(meals['lunch'], ['참치마요덮밥']);
    });

    test('표에 없는 날짜는 빈 값을 준다', () {
      final meals = parseSadoHtml(sadoWeek(monday),
          monday.add(const Duration(days: 30)))['meals'] as Map;
      expect(meals['breakfast'], isEmpty);
    });
  });
}
