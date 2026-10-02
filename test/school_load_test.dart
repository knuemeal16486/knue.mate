// 학교 서버 부담을 줄이는 장치들(2026-09-28 정보전산원 메일).
// 이 값들이 풀리면 학교 서버로 다시 요청이 몰린다.
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart';
import 'package:knue_mate/offline_cache.dart';
import 'package:knue_mate/school_http.dart';
import 'package:shared_preferences/shared_preferences.dart';

Notice _n(String group, String category, String title, String date) => Notice(
  id: Object.hash(group, category, title),
  category: category,
  group: group,
  title: title,
  date: date,
  author: '학교',
  link: 'https://example.com/$title',
);

void main() {
  group('schoolUserAgent', () {
    test('앱 이름·학교에 알려진 이름·연락처가 모두 들어간다', () {
      final ua = schoolUserAgent('1.6.2');
      expect(ua, startsWith('KNUE-Mate/1.6.2'));
      expect(ua, contains('KNUE MOA'));
      expect(ua, contains('+knuemeal16486@gmail.com'));
      // 브라우저 흉내를 내면 학교가 우리 요청을 구분하지 못한다.
      expect(ua, isNot(contains('Mozilla')));
    });
  });

  group('backgroundNoticeBoards', () {
    test('아무것도 설정 안 했으면 기본 4개만 — 전체 48개가 아니다', () {
      expect(backgroundNoticeBoards(const [], const []), kDefaultFavoriteBoards);
      expect(kDefaultFavoriteBoards.length, 4);
    });

    test('즐겨찾기가 있으면 그것만(키워드가 있어도)', () {
      expect(
        backgroundNoticeBoards(['수학교육과', '학사공지'], ['장학']),
        {'수학교육과', '학사공지'},
      );
    });

    test('즐겨찾기 없이 키워드만 있으면 대표 홈페이지 13개 — 전체 48개가 아니다', () {
      // 학교가 직접 요청은 고른 게시판만으로 줄여 달라고 했다(2026-10-02).
      expect(backgroundNoticeBoards(const [], ['장학']), kMainHomepageBoards);
    });
  });

  group('kMainHomepageBoards', () {
    test('학교 대표 홈페이지(/www/) 게시판과 정확히 같다', () {
      final www = {
        for (final g in KnueScraper().boardGroups.values)
          for (final b in g.entries)
            if (b.value.contains('www.knue.ac.kr/www/')) b.key,
      };
      expect(kMainHomepageBoards, www);
      expect(kMainHomepageBoards.length, 13);
    });
  });

  group('noticeFetchScope — 공지 화면은 보고 있는 범위만 받는다', () {
    Set<String> scope({String tab = '공지사항', String? sub, String? cat, List<String> favs = const []}) =>
        noticeFetchScope(mainTab: tab, subGroup: sub, category: cat, favorites: favs);

    test('게시판을 하나 고르면 그 게시판만', () {
      expect(scope(tab: '대학/대학원', sub: '제3대학', cat: '수학교육과'), {'수학교육과'});
    });

    test('하위 탭을 고르면 그 안의 게시판만', () {
      expect(scope(sub: '교류 프로그램'), {'학점교류', '교환학생'});
      expect(scope(tab: '대학/대학원', sub: '제4대학'), {'음악교육과', '체육교육과', '미술교육과'});
    });

    test('[공지사항] 전체는 그 탭의 게시판 — 대표 홈페이지 13개를 모두 포함한다', () {
      final s = scope();
      expect(s.containsAll(kMainHomepageBoards), isTrue);
      expect(s.contains('수학교육과'), isFalse);
    });

    test('[대학/대학원] 전체는 고정한 학과만 — 27개를 한꺼번에 받지 않는다', () {
      expect(scope(tab: '대학/대학원'), isEmpty);
      expect(scope(tab: '대학/대학원', favs: ['수학교육과', '학사공지']), {'수학교육과'});
    });
  });

  group('boardQueuesByHost', () {
    test('실제 게시판 목록: 학교 대표 서버 40개가 한 줄에 선다', () {
      final boards = [
        for (final g in KnueScraper().boardGroups.entries)
          for (final b in g.value.entries)
            (group: g.key, category: b.key, url: b.value),
      ];
      final queues = boardQueuesByHost(boards);
      // 정보전산원이 센 40개(대표 홈페이지 13 + 학과·대학원 27)와 같아야 한다.
      expect(queues['www.knue.ac.kr']!.length, 40);
      expect(queues.values.fold<int>(0, (s, q) => s + q.length), 48);
    });

    test('LINK: 게시판은 요청하지 않는다', () {
      final queues = boardQueuesByHost([
        (group: 'DEPT', category: '초등교육과', url: 'LINK:https://m.cafe.daum.net/x'),
        (group: 'MAIN', category: '학사공지', url: 'https://www.knue.ac.kr/www/a'),
      ]);
      expect(queues.keys, ['www.knue.ac.kr']);
    });

    test('같은 서버 안의 순서는 목록 순서 그대로', () {
      final queues = boardQueuesByHost([
        (group: 'MAIN', category: 'A', url: 'https://www.knue.ac.kr/1'),
        (group: 'ANNEX', category: 'B', url: 'https://lib.knue.ac.kr/2'),
        (group: 'MAIN', category: 'C', url: 'https://www.knue.ac.kr/3'),
      ]);
      expect(queues['www.knue.ac.kr']!.map((b) => b.category), ['A', 'C']);
      expect(queues['lib.knue.ac.kr']!.map((b) => b.category), ['B']);
    });
  });

  group('mergeNoticeCache', () {
    final valid = {('MAIN', '학사공지'), ('MAIN', '장학금'), ('ANNEX', '교육대학원'), ('GRAD', '교육대학원')};

    test('받은 게시판은 통째로 바뀌고 나머지는 그대로', () {
      final cached = [
        _n('MAIN', '학사공지', '지워진 글', '2026-09-01'),
        _n('MAIN', '장학금', '장학 안내', '2026-09-02'),
      ];
      final merged = mergeNoticeCache(cached, {
        ('MAIN', '학사공지'): [_n('MAIN', '학사공지', '새 글', '2026-09-28')],
      }, valid);
      expect(merged.map((n) => n.title), ['새 글', '장학 안내']);
    });

    test('빈 결과는 실패로 보고 옛 글을 둔다', () {
      final cached = [_n('MAIN', '학사공지', '옛 글', '2026-09-01')];
      final merged = mergeNoticeCache(cached, {('MAIN', '학사공지'): []}, valid);
      expect(merged.map((n) => n.title), ['옛 글']);
    });

    test('이름이 같은 두 게시판(교육대학원)을 섞지 않는다', () {
      final cached = [
        _n('ANNEX', '교육대학원', '사도교육원 글', '2026-09-01'),
        _n('GRAD', '교육대학원', '대학원 옛 글', '2026-09-01'),
      ];
      final merged = mergeNoticeCache(cached, {
        ('GRAD', '교육대학원'): [_n('GRAD', '교육대학원', '대학원 새 글', '2026-09-28')],
      }, valid);
      expect(merged.map((n) => n.title), ['대학원 새 글', '사도교육원 글']);
    });

    test('목록에서 빠진 게시판의 옛 글은 버린다', () {
      final cached = [_n('MAIN', '없어진 게시판', '글', '2026-09-01')];
      expect(mergeNoticeCache(cached, const {}, valid), isEmpty);
    });
  });

  group('throttleDueKeys', () {
    final now = DateTime(2026, 9, 29, 12);
    const gap = Duration(minutes: 30);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    test('처음 보는 키와 간격이 지난 키만 통과', () {
      final due = throttleDueKeys(
        {'a': ago(const Duration(minutes: 10)), 'b': ago(const Duration(minutes: 31))},
        ['a', 'b', 'c'],
        now,
        gap,
      );
      expect(due, ['b', 'c']);
    });

    test('기록이 미래면(시계를 되돌린 기기) 통과시킨다', () {
      final future = now.add(const Duration(days: 1)).millisecondsSinceEpoch;
      expect(throttleDueKeys({'a': future}, ['a'], now, gap), ['a']);
    });

    test('간격 0(당겨서 새로 고침)은 방금 받았어도 통과', () {
      expect(throttleDueKeys({'a': ago(Duration.zero)}, ['a'], now, Duration.zero), ['a']);
    });

    test('같은 키를 두 번 주지 않는다', () {
      expect(throttleDueKeys(const {}, ['a', 'a'], now, gap), ['a']);
    });
  });

  group('PersistentThrottle', () {
    test('간격 안에서는 두 번째 요청이 막힌다 — 앱을 다시 켜도(기기 저장)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await PersistentThrottle.acquire('t', ['x', 'y'], const Duration(hours: 1)),
        ['x', 'y'],
      );
      expect(
        await PersistentThrottle.acquire('t', ['x', 'z'], const Duration(hours: 1)),
        ['z'],
      );
      // 다른 bucket은 따로 센다.
      expect(await PersistentThrottle.tryAcquire('u', 'x', const Duration(hours: 1)), isTrue);
    });
  });
}
