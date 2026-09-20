import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart';

void main() {
  group('scopeEventsToMonth', () {
    CalendarEvent ev(String title, DateTime start, DateTime end) =>
        CalendarEvent(startDate: start, endDate: end, title: title);

    test('학교 페이지가 전 학년도 일정을 한 번에 줘도 요청한 달만 남는다', () {
      final events = [
        ev('1월 일정', DateTime(2026, 1, 15), DateTime(2026, 1, 15)),
        ev('9월 일정', DateTime(2026, 9, 10), DateTime(2026, 9, 10)),
        ev('12월 일정', DateTime(2026, 12, 25), DateTime(2026, 12, 25)),
      ];
      final scoped = scopeEventsToMonth(events, 2026, 9);
      expect(scoped.map((e) => e.title), ['9월 일정']);
    });

    test('달 경계에 걸친 일정은 양쪽 달 모두에 남는다', () {
      final boundary = ev(
        '수강신청 변경',
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 4),
      );
      expect(scopeEventsToMonth([boundary], 2026, 8), [boundary]);
      expect(scopeEventsToMonth([boundary], 2026, 9), [boundary]);
      expect(scopeEventsToMonth([boundary], 2026, 10), isEmpty);
    });

    test('해당 달에 일정이 없으면 빈 목록', () {
      final events = [ev('1월 일정', DateTime(2026, 1, 1), DateTime(2026, 1, 1))];
      expect(scopeEventsToMonth(events, 2026, 9), isEmpty);
    });

    test('12월 요청도 해 넘김 없이 정상 처리된다', () {
      final events = [
        ev('12월 일정', DateTime(2026, 12, 20), DateTime(2026, 12, 20)),
        ev('1월 일정', DateTime(2027, 1, 3), DateTime(2027, 1, 3)),
      ];
      expect(
        scopeEventsToMonth(events, 2026, 12).map((e) => e.title),
        ['12월 일정'],
      );
    });
  });

  group('dedupeCalendarEvents', () {
    CalendarEvent ev(String title, DateTime start, DateTime end) =>
        CalendarEvent(startDate: start, endDate: end, title: title);

    test('제목·기간이 모두 같으면 하나만 남는다', () {
      final s = DateTime(2026, 9, 10);
      final e = DateTime(2026, 9, 14);
      final events = [ev('중간고사', s, e), ev('중간고사', s, e), ev('중간고사', s, e)];
      expect(dedupeCalendarEvents(events).length, 1);
    });

    test('앞선 것이 남고 순서는 그대로다', () {
      final events = [
        ev('개강', DateTime(2026, 9, 1), DateTime(2026, 9, 1)),
        ev('수강정정', DateTime(2026, 9, 3), DateTime(2026, 9, 5)),
        ev('개강', DateTime(2026, 9, 1), DateTime(2026, 9, 1)),
      ];
      expect(dedupeCalendarEvents(events).map((e) => e.title), [
        '개강',
        '수강정정',
      ]);
    });

    test('제목이 같아도 기간이 다르면 다른 일정이다', () {
      // "중간고사"처럼 학기마다 되풀이되는 이름을 제목만 보고 지우면
      // 2학기 일정이 통째로 사라진다.
      final events = [
        ev('중간고사', DateTime(2026, 4, 20), DateTime(2026, 4, 24)),
        ev('중간고사', DateTime(2026, 10, 19), DateTime(2026, 10, 23)),
      ];
      expect(dedupeCalendarEvents(events).length, 2);
    });

    test('제목 앞뒤 공백 차이는 같은 일정으로 본다', () {
      final s = DateTime(2026, 9, 10);
      final e = DateTime(2026, 9, 10);
      expect(dedupeCalendarEvents([ev(' 개강 ', s, e), ev('개강', s, e)]).length, 1);
    });

    test('홈 카드 3칸이 같은 일정으로 채워지지 않는다', () {
      // 이게 실제로 났던 버그다: 중복을 안 걷어내고 take(3)을 해서 같은
      // 일정만 세 줄 뜨고 정작 다음 일정이 밀려났다.
      final dup = ev('추석 연휴', DateTime(2026, 9, 24), DateTime(2026, 9, 26));
      final events = [
        dup,
        dup,
        dup,
        ev('개천절', DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
      ];
      final top3 = dedupeCalendarEvents(events).take(3).map((e) => e.title);
      expect(top3, ['추석 연휴', '개천절']);
    });

    test('빈 목록은 빈 목록', () {
      expect(dedupeCalendarEvents([]), isEmpty);
    });
  });

  group('upcomingAcademicEvents', () {
    CalendarEvent ev(String title, DateTime start, [DateTime? end]) =>
        CalendarEvent(startDate: start, endDate: end ?? start, title: title);

    test('오늘 끝나는 일정은 아직 남는다', () {
      final now = DateTime(2026, 9, 20, 14, 0);
      final today = ev('오늘까지', DateTime(2026, 9, 18), DateTime(2026, 9, 20));
      expect(upcomingAcademicEvents([today], now), [today]);
    });

    test('어제 끝난 일정은 빠진다', () {
      final now = DateTime(2026, 9, 20, 14, 0);
      final past = ev('어제까지', DateTime(2026, 9, 18), DateTime(2026, 9, 19));
      expect(upcomingAcademicEvents([past], now), isEmpty);
    });

    test('시작이 이른 순으로 3개까지', () {
      final now = DateTime(2026, 9, 1);
      final events = [
        ev('넷', DateTime(2026, 9, 25)),
        ev('하나', DateTime(2026, 9, 5)),
        ev('셋', DateTime(2026, 9, 20)),
        ev('둘', DateTime(2026, 9, 10)),
      ];
      expect(upcomingAcademicEvents(events, now).map((e) => e.title), [
        '하나',
        '둘',
        '셋',
      ]);
    });

    test('월말에도 다음 달 일정으로 카드가 찬다', () {
      // 이게 실제 버그였다: 이번 달만 넘기면 9/28에 9월 일정이 다 지나
      // "다가오는 일정 없음"이 떴다. 매달 말 되풀이되던 증상.
      final now = DateTime(2026, 9, 28);
      final september = [ev('추석', DateTime(2026, 9, 24), DateTime(2026, 9, 26))];
      final october = [
        ev('개천절', DateTime(2026, 10, 3)),
        ev('중간고사', DateTime(2026, 10, 19), DateTime(2026, 10, 23)),
      ];
      expect(
        upcomingAcademicEvents([...september, ...october], now).map(
          (e) => e.title,
        ),
        ['개천절', '중간고사'],
      );
    });

    test('달 경계에 걸친 일정이 두 달에서 와도 한 번만 센다', () {
      // scopeEventsToMonth가 8/31~9/4 같은 일정을 양쪽 달에 모두 남기므로
      // 두 달을 합치면 반드시 중복이 생긴다.
      final now = DateTime(2026, 8, 30);
      final boundary = ev('수강정정', DateTime(2026, 8, 31), DateTime(2026, 9, 4));
      final merged = [boundary, boundary];
      expect(upcomingAcademicEvents(merged, now).length, 1);
    });

    test('남은 일정이 없으면 빈 목록', () {
      final now = DateTime(2026, 12, 31);
      expect(
        upcomingAcademicEvents([ev('옛날', DateTime(2026, 1, 1))], now),
        isEmpty,
      );
    });
  });

  test('KNUE 표준 게시판 HTML 파싱', () {
    const html = '''
<table class="bbs_list"><tbody>
<tr>
  <td class="ta_c">1234</td>
  <td class="ta_l"><a href="selectBbsNttView.do?nttNo=98765">2026학년도 장학금 신청 안내</a><img src="new.gif" alt="새글"></td>
  <td>교무처</td>
  <td class="ta_c">2026-07-15</td>
</tr>
</tbody></table>''';
    // 주의: 원본 파서(_parseHtmlStatic)는 파라미터 키로 'baseUrl'이 아닌 'url'을 사용한다
    // (lib/notice_service.dart의 _fetchBoard가 compute(parseHtml, {..., 'url': url})로 호출).
    final notices = KnueScraper.parseHtml({
      'html': html,
      'group': 'MAIN',
      'category': '학사공지',
      'url': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807',
    });
    expect(notices, isNotEmpty);
    expect(notices.first.title, contains('장학금'));
    expect(notices.first.category, '학사공지');
    expect(notices.first.group, 'MAIN');
    // 날짜는 게시판마다 다른 원본 표기와 무관하게 "yyyy-MM-dd"로 정규화된다.
    expect(notices.first.date, '2026-07-15');
    expect(notices.first.author, '교무처');
    expect(
      notices.first.link,
      'https://www.knue.ac.kr/www/selectBbsNttView.do?nttNo=98765',
    );
  });

  test('새글 표시가 제목에서 제거된다', () {
    const html = '''
<table><tbody>
<tr>
  <td class="ta_c">1</td>
  <td class="ta_l"><a href="view.do?id=1">[새글] 채용 공고 안내</a></td>
  <td>총무처</td>
  <td class="ta_c">2026.07.16</td>
</tr>
</tbody></table>''';
    final notices = KnueScraper.parseHtml({
      'html': html,
      'group': 'MAIN',
      'category': '채용공고',
      'url': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=27&key=808',
    });
    expect(notices, isNotEmpty);
    expect(notices.first.title, '채용 공고 안내');
  });

  test('행이 없으면 빈 리스트를 반환한다', () {
    final notices = KnueScraper.parseHtml({
      'html': '<table><tbody></tbody></table>',
      'group': 'MAIN',
      'category': '학사공지',
      'url': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807',
    });
    expect(notices, isEmpty);
  });

  test('boardGroups 필수 그룹 포함 확인 (MAIN/ANNEX/LIFE/DEPT/GRAD)', () {
    final scraper = KnueScraper();
    expect(scraper.boardGroups.keys,
        containsAll(['MAIN', 'ANNEX', 'LIFE', 'DEPT', 'GRAD']));
  });
}
