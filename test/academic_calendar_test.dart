import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/academic_calendar.dart';

/// 학사일정 표의 한 행. 실제 페이지(2026-09-28)와 같은 구조다.
String _row(String title, int m, int d, [int? em, int? ed]) {
  String two(int v) => v.toString().padLeft(2, '0');
  final end = em == null
      ? ''
      : '<span class="end"><em class="text hyphen">-</em>'
          '<em class="text month">${two(em)}</em><em class="text dot">.</em>'
          '<em class="text days">${two(ed!)}</em></span>';
  return '<tr><td><span class="start"><em class="text month">${two(m)}</em>'
      '<em class="text dot">.</em><em class="text days">${two(d)}</em></span>'
      '$end</td><td><a href="./selectSchdleWebView.do?key=542&schdleNum=1" '
      'class="more_link">$title</a></td></tr>';
}

/// 이번 달 표 + 학년도 전체 표가 같이 있는 페이지.
String _page() => '''
<table><caption>2026년 09월 전체일정표 - 기간, 일정 순으로 안내합니다.</caption>
<tbody>${_row('추석 연휴 수업보강', 9, 21, 9, 23)}</tbody></table>
<table><caption>2026년 전체 일정표 - 학기, 월별, 기간, 일정 순으로 안내합니다.</caption>
<tbody>
${_row('제1학기 개강일', 3, 3)}
${_row('추석 연휴 수업보강', 9, 21, 9, 23)}
${_row('동계 계절학기', 12, 28, 1, 15)}
${_row('2026학년도 전기 학위수여식', 2, 18)}
</tbody></table>''';

void main() {
  group('academicYearOf', () {
    test('3월부터 새 학년도', () {
      expect(academicYearOf(2026, 3), 2026);
      expect(academicYearOf(2026, 12), 2026);
    });
    test('1~2월은 전 학년도', () {
      expect(academicYearOf(2027, 1), 2026);
      expect(academicYearOf(2027, 2), 2026);
    });
  });

  group('parseAcademicYearHtml', () {
    final events = parseAcademicYearHtml(_page(), 2026);
    DateTime startOf(String title) =>
        events.firstWhere((e) => e.title == title).startDate;

    test('1~2월 행은 이듬해다 — 예전엔 1년 어긋나게 읽었다', () {
      expect(startOf('2026학년도 전기 학위수여식'), DateTime(2027, 2, 18));
      expect(startOf('제1학기 개강일'), DateTime(2026, 3, 3));
    });

    test('해를 넘는 기간은 끝이 이듬해', () {
      final winter = events.firstWhere((e) => e.title == '동계 계절학기');
      expect(winter.startDate, DateTime(2026, 12, 28));
      expect(winter.endDate, DateTime(2027, 1, 15));
    });

    test('이번 달 표와 전체 표에 같이 있는 일정을 두 번 세지 않는다', () {
      expect(events.where((e) => e.title == '추석 연휴 수업보강').length, 1);
      expect(events.length, 4);
    });

    test('전체 표를 못 찾아도(화면이 바뀌어도) 행을 읽고 중복을 걷는다', () {
      final html = '<table><tbody>${_row('개강', 3, 3)}${_row('개강', 3, 3)}'
          '</tbody></table>';
      expect(parseAcademicYearHtml(html, 2026).length, 1);
    });

    test('일정이 없는 페이지(다음 학년도 미게시)는 빈 목록', () {
      expect(parseAcademicYearHtml('<html></html>', 2027), isEmpty);
    });

    test('학년도 전체를 받아 달별로 나눠 쓴다 — 2월 카드는 2027년 2월', () {
      final feb = scopeEventsToMonth(events, 2027, 2);
      expect(feb.map((e) => e.title), ['2026학년도 전기 학위수여식']);
    });
  });

  group('shouldClaimCalendarRefresh', () {
    final now = DateTime(2026, 9, 29, 12);

    test('하루 안에 받은 문서는 다시 안 받는다', () {
      expect(
        shouldClaimCalendarRefresh(
          fetchedAt: now.subtract(const Duration(hours: 23)),
          refreshingUntil: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('하루가 넘었으면 받는다', () {
      expect(
        shouldClaimCalendarRefresh(
          fetchedAt: now.subtract(const Duration(hours: 25)),
          refreshingUntil: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('다른 기기가 받는 중이면 기다린다', () {
      expect(
        shouldClaimCalendarRefresh(
          fetchedAt: null,
          refreshingUntil: now.add(const Duration(minutes: 5)),
          now: now,
        ),
        isFalse,
      );
    });

    test('받다가 멈춘 기기의 표시는 시간이 지나면 무시한다', () {
      expect(
        shouldClaimCalendarRefresh(
          fetchedAt: null,
          refreshingUntil: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
    });

    test('시계가 틀린 기기가 미래 시각을 적어도 영영 잠기지 않는다', () {
      final farFuture = now.add(const Duration(days: 30));
      expect(
        shouldClaimCalendarRefresh(
          fetchedAt: farFuture,
          refreshingUntil: farFuture,
          now: now,
        ),
        isTrue,
      );
    });
  });
}
