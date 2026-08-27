import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_service.dart';

void main() {
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
