// 공지 파싱 회귀 테스트. 네트워크를 타지 않고, 학교 게시판에서 실제로 받아온
// 형태를 줄여 넣은 HTML로 검증한다.
// (살아 있는 게시판 점검은 test/notice_healthcheck.dart — 수동 실행)
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart';

List parse(String html, {String url = 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=25'}) =>
    KnueScraper.parseHtml({
      'html': html,
      'group': 'MAIN',
      'category': '대학소식',
      'url': url,
    });

/// KNUE 게시판 한 행: [번호, 제목, 첨부, 조회, 등록일]
String row(String title, String attach, String views, String date) =>
    '<tr><td>3968</td><td class="p-subject">'
    '<a href="/www/selectBbsNttView.do?nttNo=1">$title</a></td>'
    '<td>$attach</td><td>$views</td><td>$date</td></tr>';

void main() {
  group('게시판 표 파싱', () {
    test('제목 속 날짜를 게시일로 읽지 않는다', () {
      // 실제 사례: "제42권 제6호(2026.11.30.발간예정) 논문투고 안내".
      // 앞에서부터 날짜를 찾으면 미래 날짜가 되어 전체 목록 맨 위에 박혔다.
      final n = parse('<table><tbody>${row(
        '[교원교육] 제42권 제6호(2026.11.30.발간예정) 논문투고 안내',
        '',
        '117',
        '2026-09-07',
      )}</tbody></table>');
      expect(n.single.date, '2026-09-07');
    });

    test('첨부파일 칸을 작성자로 쓰지 않는다', () {
      final n = parse('<table><tbody>'
          '${row('재정위원회 회의록 공개', '여러개의 파일 첨부', '25', '2026-09-14')}'
          '</tbody></table>');
      expect(n.single.author, isNot(contains('첨부')));
    });

    test('칸이 3개뿐인 게시판도 날짜를 읽는다', () {
      // 체육교육과처럼 [제목, 첨부, 등록일]만 있는 게시판.
      final n = parse('<table><tbody><tr>'
          '<td class="p-subject"><a href="/v?no=1">폭력예방교육 이수 안내</a></td>'
          '<td>hwp 파일 첨부</td><td>2024-07-02</td>'
          '</tr></tbody></table>');
      expect(n.single.date, '2024-07-02');
    });

    test('두 자리 연도를 2000년대로 편다', () {
      final n = parse('<table><tbody>'
          '${row('공결 신청 안내', '', '52', '26.09.09')}</tbody></table>');
      expect(n.single.date, '2026-09-09');
    });

    test('상대 링크를 절대 주소로 편다', () {
      final n = parse('<table><tbody>'
          '${row('등록금 납부 안내', '', '9', '2026-07-16')}</tbody></table>');
      expect(n.single.link, startsWith('https://www.knue.ac.kr/'));
    });
  });

  group('신문방송사 기사 목록', () {
    const url =
        'https://m.news.knue.ac.kr/news/articleList.html?sc_section_code=S1N3';
    const html = '''
<ul id="section-list">
  <li>
    <a href="/news/articleView.html?idxno=13542">
      <div class="titles">[522호/사무사] 대학 언론의 역할과 책임</div>
    </a>
    <em class="info category">사무사</em>
    <em class="info name">최동인 기자</em>
    <em class="info dated">09.07 09:22</em>
  </li>
</ul>''';

    test('표가 없어도 기사를 읽는다', () {
      // 기사 목록은 게시판 표 구조가 아니라, 예전에는 0건이 나왔다.
      final n = parse(html, url: url);
      expect(n, hasLength(1));
      expect(n.single.title, contains('대학 언론의 역할과 책임'));
      expect(n.single.author, '최동인 기자');
      expect(n.single.link,
          'https://m.news.knue.ac.kr/news/articleView.html?idxno=13542');
    });

    test('연도 없는 날짜에 연도를 채운다', () {
      final n = parse(html, url: url);
      final now = DateTime.now();
      final d = DateTime.parse(n.single.date);
      expect(d.month, 9);
      expect(d.day, 7);
      // 연도를 잘못 넣으면 미래 기사가 되어 목록 맨 위에 박힌다.
      expect(d.isAfter(now.add(const Duration(days: 2))), isFalse);
      expect(now.difference(d).inDays, lessThan(366));
    });
  });

  group('캐시 상한', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('글이 뜸한 게시판도 살아남는다', () async {
      // 날짜순으로만 자르면 오래된 게시판이 통째로 사라진다. 실제로
      // 교환학생·체육교육과 등 6개 게시판이 크롤링은 되는데 앱에서 0건이었다.
      final notices = <Notice>[];
      var day = 0;
      Notice make(String board, DateTime d) => Notice(
            id: notices.length,
            category: board,
            group: 'MAIN',
            title: '$board 공지 ${notices.length}',
            date: '${d.year}-${d.month.toString().padLeft(2, '0')}'
                '-${d.day.toString().padLeft(2, '0')}',
            author: '학교',
            link: 'https://example.com/${notices.length}',
          );
      // 활발한 게시판 40개 × 최근 공지 50건 = 2000건으로 상한을 넘긴다.
      for (var b = 0; b < 40; b++) {
        for (var i = 0; i < 50; i++) {
          notices.add(make('활발$b', DateTime(2026, 9, 1).subtract(Duration(days: day++ % 60))));
        }
      }
      // 뜸한 게시판: 3년 전 공지 5건뿐.
      for (var i = 0; i < 5; i++) {
        notices.add(make('뜸한게시판', DateTime(2023, 1, 1 + i)));
      }
      notices.sort((a, b) => b.date.compareTo(a.date));

      await NoticeCache.save(notices);
      final back = (await NoticeCache.load())!;

      expect(back.where((n) => n.category == '뜸한게시판'), isNotEmpty,
          reason: '오래됐다는 이유로 게시판이 통째로 잘리면 안 된다');
      final boards = back.map((n) => n.category).toSet();
      expect(boards, hasLength(41), reason: '모든 게시판이 남아야 한다');
      expect(back.length, lessThanOrEqualTo(1000));
      // 최신순 정렬은 유지된다.
      for (var i = 1; i < back.length; i++) {
        expect(back[i - 1].date.compareTo(back[i].date), greaterThanOrEqualTo(0));
      }
    });
  });
}
