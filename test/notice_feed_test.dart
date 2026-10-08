// 앱이 공지를 학교 대신 중앙 수집 파일에서 받는다(lib/notice_feed.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knue_mate/notice_collector.dart';
import 'package:knue_mate/notice_feed.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://feed.test/feed';

FeedBoardEntry _entry(
  String group,
  String category, {
  String? hash,
  DateTime? at,
  int count = 2,
}) =>
    FeedBoardEntry(
      group: group,
      category: category,
      file: 'b/${fnvHex('$group$category')}.json',
      fetchedAt: at ?? DateTime.utc(2026, 10, 7, 3),
      ok: true,
      count: count,
      hash: hash ?? 'h-$category',
    );

String _boardFile(FeedBoardEntry e, List<String> titles) => jsonEncode({
      'group': e.group,
      'category': e.category,
      'fetchedAt': e.fetchedAt?.toIso8601String(),
      'items': [
        for (final t in titles)
          {'t': t, 'l': 'https://www.knue.ac.kr/x?$t', 'd': '2026-10-06', 'a': '학사관리과'},
      ],
    });

/// 수집 파일 서버 흉내. 받은 요청 주소를 [log]에 적는다.
MockClient _server(Map<String, String> files, List<String> log) =>
    MockClient((req) async {
      log.add(req.url.toString());
      final path = req.url.toString().replaceFirst('$_base/', '');
      final body = files[path];
      if (body == null) return http.Response('not found', 404);
      return http.Response.bytes(utf8.encode(body), 200);
    });

void main() {
  group('parseNoticeFeedSettings', () {
    test('문서가 없으면 기본 주소, 직접 모드 꺼짐', () {
      final s = parseNoticeFeedSettings(null);
      expect(s.base, kNoticeFeedBase);
      expect(s.direct, isFalse);
    });

    test('직접 모드는 명시적으로 true일 때만 — 엉뚱한 값으로 학교를 두드리지 않는다', () {
      expect(parseNoticeFeedSettings({'direct': 'true'}).direct, isFalse);
      expect(parseNoticeFeedSettings({'direct': 1}).direct, isFalse);
      expect(parseNoticeFeedSettings({'direct': true}).direct, isTrue);
    });

    test('주소는 https만 받고 끝의 / 는 뗀다', () {
      expect(parseNoticeFeedSettings({'base': 'https://x.dev/feed/'}).base, 'https://x.dev/feed');
      expect(parseNoticeFeedSettings({'base': 'http://x.dev/feed'}).base, kNoticeFeedBase);
      expect(parseNoticeFeedSettings({'base': 3}).base, kNoticeFeedBase);
    });
  });

  group('feedBoardsToFetch', () {
    final known = {('MAIN', '학사공지'), ('MAIN', '장학금'), ('DEPT', '수학교육과')};

    test('지문이 같고 캐시에 있으면 받지 않는다', () {
      final a = _entry('MAIN', '학사공지');
      final b = _entry('MAIN', '장학금');
      final todo = feedBoardsToFetch(
        boards: [a, b],
        localHashes: {a.file: a.hash, b.file: 'old'},
        cachedBoards: {('MAIN', '학사공지'), ('MAIN', '장학금')},
        knownBoards: known,
      );
      expect(todo.map((e) => e.category), ['장학금']);
    });

    test('지문이 같아도 캐시에서 사라졌으면 다시 받는다', () {
      final a = _entry('MAIN', '학사공지');
      expect(
        feedBoardsToFetch(
          boards: [a],
          localHashes: {a.file: a.hash},
          cachedBoards: const {},
          knownBoards: known,
        ),
        [a],
      );
    });

    test('앱이 모르는 게시판·아직 수집 안 된 게시판·0건 게시판은 건너뛴다', () {
      final todo = feedBoardsToFetch(
        boards: [
          _entry('MAIN', '새게시판'),
          FeedBoardEntry(group: 'MAIN', category: '학사공지', file: 'b/1.json', fetchedAt: null, ok: false, count: 0, hash: ''),
          _entry('DEPT', '수학교육과', count: 0),
        ],
        localHashes: const {},
        cachedBoards: const {},
        knownBoards: known,
      );
      expect(todo, isEmpty);
    });
  });

  group('feedAlertBoards', () {
    test('즐겨찾기가 있으면 그것만', () {
      expect(feedAlertBoards(['수학교육과'], ['장학']), {'수학교육과'});
    });

    test('키워드만 있으면 모든 게시판(null) — 수집 파일엔 전체가 있어 학교 부담과 무관', () {
      expect(feedAlertBoards(const [], ['장학']), isNull);
    });

    test('아무것도 없으면 기본 4개 — 48개 새 글이 전부 알림으로 오지 않게', () {
      expect(feedAlertBoards(const [], const []), kDefaultFavoriteBoards);
    });
  });

  group('feedScopeStatus·isFeedStale', () {
    final now = DateTime.utc(2026, 10, 7, 12);

    test('보고 있는 게시판 중 가장 오래된 수집 시각과 수집 안 된 게시판', () {
      final st = feedScopeStatus([
        _entry('MAIN', '학사공지', at: now.subtract(const Duration(minutes: 10))),
        _entry('MAIN', '장학금', at: now.subtract(const Duration(minutes: 40))),
        _entry('ANNEX', '종합연수원', at: now.subtract(const Duration(hours: 9))),
        FeedBoardEntry(group: 'DEPT', category: '수학교육과', file: 'b/1.json', fetchedAt: null, ok: false, count: 0, hash: ''),
      ], {'학사공지', '장학금', '수학교육과'});
      // 보고 있지 않은 종합연수원(9시간 전)은 셈에 안 들어간다.
      expect(st.oldest, now.subtract(const Duration(minutes: 40)));
      expect(st.missing, {'수학교육과'});
    });

    test('3시간이 넘어야 늦어졌다고 본다', () {
      expect(isFeedStale(null, now), isFalse);
      expect(isFeedStale(now.subtract(const Duration(hours: 2, minutes: 59)), now), isFalse);
      expect(isFeedStale(now.subtract(const Duration(hours: 3, minutes: 1)), now), isTrue);
    });
  });

  group('withStableId', () {
    test('직접 받던 때의 글도 수집 파일 글과 같은 번호가 된다 — 알림이 같은 글로 본다', () {
      final old = Notice(id: 12345, category: '학사공지', group: 'MAIN', title: '수강 정정', date: '2026-10-06', author: '학사관리과', link: 'https://www.knue.ac.kr/x?1');
      final fixed = withStableId(old);
      expect(fixed.id, stableNoticeId('MAIN', '학사공지', 'https://www.knue.ac.kr/x?1'));
      expect(fixed.title, '수강 정정');
      expect(withStableId(fixed), same(fixed));
    });
  });

  group('NoticeFeed.sync', () {
    late List<String> log;
    final a = _entry('MAIN', '학사공지');
    final b = _entry('MAIN', '장학금');

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      NoticeFeed.debugReset();
      NoticeFeedSettings.debugSet(base: _base);
      log = [];
    });

    Future<bool> syncWith(Map<String, String> files, {bool force = true}) =>
        http.runWithClient(
          () => NoticeFeed.sync(force: force),
          () => _server(files, log),
        );

    test('목록을 보고 게시판 파일을 받아 캐시에 넣는다 — 학교로는 한 건도 안 간다', () async {
      final files = {
        'index.json': encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a, b]),
        a.file: _boardFile(a, ['수강 정정', '휴학 안내']),
        b.file: _boardFile(b, ['국가장학금']),
      };
      expect(await syncWith(files), isTrue);

      final cache = await NoticeCache.load();
      expect(cache!.map((n) => n.title), containsAll(['수강 정정', '휴학 안내', '국가장학금']));
      final n = cache.firstWhere((n) => n.title == '국가장학금');
      expect(n.category, '장학금');
      expect(n.id, stableNoticeId('MAIN', '장학금', n.link));
      expect(NoticeFeed.boards.value.length, 2);
      expect(log.every((u) => u.startsWith(_base)), isTrue);
      expect(log.any((u) => u.contains('knue.ac.kr')), isFalse);
    });

    test('바뀐 게시판만 다시 받는다', () async {
      final files = {
        'index.json': encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a, b]),
        a.file: _boardFile(a, ['수강 정정']),
        b.file: _boardFile(b, ['국가장학금']),
      };
      await syncWith(files);
      log.clear();

      // 아무것도 안 바뀌었으면 목록만 받는다.
      await syncWith(files);
      expect(log, ['$_base/index.json']);
      log.clear();

      // 장학금만 바뀌었다.
      final b2 = _entry('MAIN', '장학금', hash: 'new');
      files['index.json'] = encodeFeedIndex(DateTime.utc(2026, 10, 7, 4), [a, b2]);
      files[b.file] = _boardFile(b2, ['교내장학']);
      await syncWith(files);
      expect(log, ['$_base/index.json', '$_base/${b.file}']);
      final titles = (await NoticeCache.load())!.map((n) => n.title);
      expect(titles, containsAll(['수강 정정', '교내장학']));
      expect(titles, isNot(contains('국가장학금')));
    });

    test('자동 확인은 5분 안에 다시 받지 않는다(당겨서 새로 고침은 받는다)', () async {
      final files = {
        'index.json': encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a]),
        a.file: _boardFile(a, ['수강 정정']),
      };
      await syncWith(files, force: false);
      log.clear();
      expect(await syncWith(files, force: false), isTrue);
      expect(log, isEmpty);
      await syncWith(files, force: true);
      expect(log, ['$_base/index.json']);
    });

    test('수집 파일에 닿지 못하면 false — 받아 둔 공지는 그대로', () async {
      final files = {
        'index.json': encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a]),
        a.file: _boardFile(a, ['수강 정정']),
      };
      await syncWith(files);
      expect(await syncWith(const {}), isFalse);
      expect((await NoticeCache.load())!.single.title, '수강 정정');
    });

    test('게시판 파일 하나가 실패하면 그 게시판은 다음에 다시 받는다', () async {
      final index = encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a, b]);
      expect(
        await syncWith({'index.json': index, a.file: _boardFile(a, ['수강 정정'])}),
        isFalse,
      );
      log.clear();
      await syncWith({
        'index.json': index,
        a.file: _boardFile(a, ['수강 정정']),
        b.file: _boardFile(b, ['국가장학금']),
      });
      expect(log, ['$_base/index.json', '$_base/${b.file}']);
    });

    test('직접 받던 때의 글은 수집 파일 글로 통째로 바뀐다(번호가 바뀐다)', () async {
      await NoticeCache.save([
        Notice(id: 1, category: '학사공지', group: 'MAIN', title: '옛 글', date: '2026-10-01', author: '', link: 'https://www.knue.ac.kr/old'),
      ]);
      await syncWith({
        'index.json': encodeFeedIndex(DateTime.utc(2026, 10, 7, 3), [a]),
        a.file: _boardFile(a, ['새 글']),
      });
      final cache = (await NoticeCache.load())!;
      expect(cache.map((n) => n.title), ['새 글']);
      expect(cache.single.id, stableNoticeId('MAIN', '학사공지', cache.single.link));
    });
  });
}
