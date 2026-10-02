// 공지 중앙 수집(lib/notice_collector.dart, tool/collect_notices.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_boards.dart';
import 'package:knue_mate/notice_collector.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_parse.dart';

/// 2026-10-02에 받은 실제 RSS와 같은 모양. 본문(description)에 태그가 섞여 있다.
const _rss = '''<?xml version='1.0' encoding='UTF-8' ?>

<rss version="2.0">
<channel>
<title><![CDATA[RSS - 학사공지]]></title>
<link>https://www.knue.ac.kr</link>
<description><![CDATA[RSS - 학사공지]]></description>

	<item>
	<title><![CDATA[ 2026학년도 제2학기 강의 중간 설문 실시 안내 ]]></title>

	<link><![CDATA[ https://www.knue.ac.kr/www/selectBbsNttView.do?key=807&bbsNo=26&nttNo=85090 ]]></link>
	<pubDate><![CDATA[ 2026-10-01 ]]></pubDate>
	<department><![CDATA[ 학사관리과 ]]></department>
	<description><![CDATA[ &lt;p&gt;본문 <title>가짜 제목</title> <link>http://x</link> &lt;/p&gt; ]]></description>
			<filename1><![CDATA[ 안내문.pdf]]></filename1>
	</item>
	<item>
	<title><![CDATA[ 교육봉사 R&amp;D 모집 ]]></title>
	<link><![CDATA[ https://www.knue.ac.kr/www/selectBbsNttView.do?key=807&bbsNo=26&nttNo=84928 ]]></link>
	<pubDate><![CDATA[ 2026-09-22 ]]></pubDate>
	<department><![CDATA[  ]]></department>
	<description><![CDATA[ 내용 ]]></description>
	</item>
</channel>
</rss>''';

void main() {
  group('noticeRssUrl', () {
    test('대표 홈페이지·학과·대학원 게시판은 같은 RSS 주소 하나로 받는다', () {
      expect(
        noticeRssUrl('https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807'),
        'https://www.knue.ac.kr/rssBbsNtt.do?bbsNo=26',
      );
      expect(
        noticeRssUrl('https://www.knue.ac.kr/math/selectBbsNttList.do?bbsNo=151&key=1231'),
        'https://www.knue.ac.kr/rssBbsNtt.do?bbsNo=151',
      );
      // 파라미터 순서가 반대인 등록금 게시판
      expect(
        noticeRssUrl('https://www.knue.ac.kr/www/selectBbsNttList.do?key=550&bbsNo=11'),
        'https://www.knue.ac.kr/rssBbsNtt.do?bbsNo=11',
      );
    });

    test('다른 서버 게시판과 LINK는 RSS가 없다', () {
      expect(noticeRssUrl('https://lib.knue.ac.kr/pyxis-api/1/bulletin-boards/1/bulletins?max=20'), isNull);
      expect(noticeRssUrl('http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=notice'), isNull);
      expect(noticeRssUrl('LINK:https://m.cafe.daum.net/knue-primary/_rec'), isNull);
    });
  });

  group('collectBoards', () {
    final boards = collectBoards();

    test('LINK를 뺀 48개, 그중 40개가 RSS(학교 대표 서버)', () {
      expect(boards.length, 48);
      expect(boards.where((b) => b.rssUrl != null).length, 40);
      expect(boards.any((b) => b.category == '초등교육과'), isFalse);
    });

    test('파일 이름이 겹치지 않는다 — 이름이 같은 "교육대학원" 두 곳도 따로다', () {
      expect({for (final b in boards) b.fileId}.length, boards.length);
      final two = boards.where((b) => b.category == '교육대학원').toList();
      expect(two.length, 2);
      expect(two[0].fileId, isNot(two[1].fileId));
    });

    test('모든 그룹에 수집 간격이 정해져 있다', () {
      for (final g in kNoticeBoardGroups.keys) {
        expect(kCollectIntervalMinutes.containsKey(g), isTrue, reason: g);
      }
    });
  });

  group('stableNoticeId·fnvHex — 어느 기기에서 계산해도 같다', () {
    test('Node로 따로 계산한 값과 같다', () {
      expect(
        stableNoticeId('MAIN', '학사공지', 'https://www.knue.ac.kr/www/selectBbsNttView.do?key=807&bbsNo=26&nttNo=85090'),
        896519427,
      );
      expect(fnvHex('https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807'), '9bbe9821');
    });

    test('게시판이 다르면 같은 링크라도 번호가 다르다', () {
      expect(stableNoticeId('ANNEX', '교육대학원', 'https://x'), isNot(stableNoticeId('GRAD', '교육대학원', 'https://x')));
    });
  });

  group('parseNoticeRss', () {
    final list = parseNoticeRss(_rss, group: 'MAIN', category: '학사공지', now: DateTime(2026, 10, 1))!;

    test('제목·링크·날짜·부서를 읽고 앞뒤 공백을 뗀다', () {
      expect(list.length, 2);
      expect(list[0].title, '2026학년도 제2학기 강의 중간 설문 실시 안내');
      expect(list[0].link, 'https://www.knue.ac.kr/www/selectBbsNttView.do?key=807&bbsNo=26&nttNo=85090');
      expect(list[0].date, '2026-10-01');
      expect(list[0].author, '학사관리과');
      expect(list[0].isNew, isTrue);
    });

    test('본문 안의 가짜 제목·링크에 속지 않는다', () {
      expect(list.any((n) => n.title.contains('가짜')), isFalse);
      expect(list.every((n) => n.link.startsWith('https://www.knue.ac.kr/')), isTrue);
    });

    test('제목의 &amp;를 풀고, 부서가 비면 "학교"', () {
      expect(list[1].title, '교육봉사 R&D 모집');
      expect(list[1].author, '학교');
    });

    test('RSS가 아니면(오류 화면) null — 0건과 구별한다', () {
      expect(parseNoticeRss('<html><body>error</body></html>', group: 'MAIN', category: 'x'), isNull);
      expect(
        parseNoticeRss('<rss version="2.0"><channel></channel></rss>', group: 'MAIN', category: 'x'),
        isEmpty,
      );
    });
  });

  group('isBoardDue', () {
    final now = DateTime.utc(2026, 10, 2, 12);
    const half = Duration(minutes: 30);

    test('받은 적이 없으면 받는다', () {
      expect(isBoardDue(null, half, now), isTrue);
    });

    test('예약 실행이 몇 분 일찍 돌아도 건너뛰지 않는다', () {
      // 30분 간격인데 27분 만에 돌았다 — 건너뛰면 실제 간격이 60분이 된다.
      expect(isBoardDue(now.subtract(const Duration(minutes: 27)), half, now), isTrue);
    });

    test('방금 받은 건 다시 받지 않는다', () {
      expect(isBoardDue(now.subtract(const Duration(minutes: 5)), half, now), isFalse);
    });

    test('2시간 간격 게시판은 30분마다 돌아도 2시간에 한 번만', () {
      const two = Duration(hours: 2);
      expect(isBoardDue(now.subtract(const Duration(minutes: 60)), two, now), isFalse);
      expect(isBoardDue(now.subtract(const Duration(minutes: 115)), two, now), isTrue);
    });
  });

  group('수집 파일 형식', () {
    final notices = [
      Notice(id: 1, category: '학사공지', group: 'MAIN', title: '제목', date: '2026-10-02', author: '학사관리과', link: 'https://a/1'),
    ];

    test('본문은 싣지 않고 제목·링크·날짜·부서만', () {
      expect(encodeFeedItems(notices), [
        {'t': '제목', 'l': 'https://a/1', 'd': '2026-10-02', 'a': '학사관리과'},
      ]);
    });

    test('읽는 쪽에서 글 번호를 다시 계산한다', () {
      final back = decodeFeedItems(encodeFeedItems(notices), group: 'MAIN', category: '학사공지', today: '2026-10-02');
      expect(back.single.id, stableNoticeId('MAIN', '학사공지', 'https://a/1'));
      expect(back.single.isNew, isTrue);
    });

    test('깨진 항목은 건너뛴다', () {
      expect(decodeFeedItems([{'t': '', 'l': 'x'}, 'x', {'l': 'y'}], group: 'g', category: 'c', today: ''), isEmpty);
      expect(decodeFeedItems(null, group: 'g', category: 'c', today: ''), isEmpty);
    });

    test('목록(index.json)을 쓰고 다시 읽는다', () {
      final at = DateTime.utc(2026, 10, 2, 12, 7);
      final body = encodeFeedIndex(at, [
        FeedBoardEntry(group: 'MAIN', category: '학사공지', file: 'b/9bbe9821.json', fetchedAt: at, ok: true, count: 50, hash: 'abcd1234'),
      ]);
      final idx = parseFeedIndex(body)!;
      expect(idx.generatedAt, at);
      expect(idx.boards.single.category, '학사공지');
      expect(idx.boards.single.fetchedAt, at);
      expect(idx.boards.single.hash, 'abcd1234');
    });

    test('모르는 형식 번호·깨진 파일은 읽지 않는다', () {
      expect(parseFeedIndex('{"version": 99, "boards": []}'), isNull);
      expect(parseFeedIndex('<html>404</html>'), isNull);
    });
  });
}
