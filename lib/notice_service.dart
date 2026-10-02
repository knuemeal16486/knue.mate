import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter/foundation.dart';
import 'academic_calendar.dart';
import 'notice_boards.dart';
import 'notice_model.dart';
import 'notice_parse.dart';
import 'offline_cache.dart';
import 'school_http.dart';

export 'academic_calendar.dart';
export 'notice_boards.dart';
export 'notice_parse.dart';

// ── 학교 서버 부담 ─────────────────────────────────────────────────────
//
// 2026-09-28 정보전산원 메일: 이 앱의 공지 요청이 학교 게시판 목록 전송량의
// 약 70%(하루 약 7.5GB, 9/23 약 8만 3천 건)였다. 원인은 기기마다 백그라운드로
// 2시간마다 48개 게시판을 **한꺼번에** 받던 구조다. 아래 값들은 그 부담을
// 줄이려고 정한 것이라, 늘리거나 병렬로 되돌리기 전에 학교와 이야기해야 한다.

/// 앱이 켜져 있을 때 뒤에서 하는 자동 갱신 간격(게시판마다, 기기에 저장).
const Duration kNoticeAutoRefreshGap = Duration(minutes: 30);

/// 캐시가 비어 있을 때(첫 실행, 또는 전부 실패했을 때) 다시 받는 최소 간격.
/// 이게 없으면 학교 서버가 막혔을 때 화면을 열 때마다 전체를 다시 받는다.
const Duration kNoticeFirstLoadGap = Duration(minutes: 5);

/// 한 서버에 동시에 보내는 요청 수. 예전엔 40개를 1초 안에 한꺼번에 보냈다.
/// 하나씩 차례로 보내면 전체 새로 고침이 10~20초 걸려서, 브라우저가 한
/// 사이트에 여는 연결 수(보통 6)보다 적게 잡았다. 전체가 2~4초면 끝난다.
const int kSchoolMaxConcurrent = 4;

/// 즐겨찾기 게시판이 없을 때 홈 카드와 백그라운드 알림이 보는 게시판.
const Set<String> kDefaultFavoriteBoards = {'대학소식', '학사공지', '청람소양', '장학금'};

/// 학교 대표 홈페이지(www.knue.ac.kr/www/)의 게시판 13개.
///
/// 2026-10-02 정보전산원: "대부분은 대표 홈페이지 게시판과 본인 학과 게시판을
/// 본다. 기기에서 학교 서버로 직접 요청할 때는 선택한 게시판만 조회해 달라."
/// 그래서 고른 게 없을 때의 기본 범위는 여기까지다(학과·대학원은 고른 것만).
const Set<String> kMainHomepageBoards = {
  '대학소식', '학사공지', '청람소양', '학점교류', '등록금', '장학금', '교환학생',
  '행사세미나', '채용공고', '입찰공고', '학생지원', '임용안내', '취업정보',
};

/// 공지 화면에서 "전체"로 두면 고른 학과만 받는 큰 탭. 학과·대학원 27개를
/// 통째로 받지 않으려는 것이다.
const String kNoticeOnDemandTab = '대학/대학원';

/// 백그라운드 알림 작업이 받을 게시판. 순수 함수 — 테스트 대상.
///
/// 예전엔 늘 전체 48개를 받았다. 알림은 즐겨찾기 게시판 것만 보내므로 그것만
/// 받는다. 즐겨찾기가 없을 때:
/// - 키워드가 있으면 대표 홈페이지 13개에서 찾는다. 한동안 전체 48개에서
///   찾았는데(2026-09-29), 학교가 직접 요청은 고른 게시판만으로 줄여 달라고
///   해서 좁혔다. 학과 공지에서 키워드를 받으려면 그 학과를 즐겨찾기한다.
/// - 키워드도 없으면 기본 4개 — 예전엔 48개 게시판의 새 글이 전부 알림으로
///   왔다(아무것도 설정 안 한 사람에게).
Set<String> backgroundNoticeBoards(
  Iterable<String> favBoards,
  Iterable<String> keywords,
) {
  if (favBoards.isNotEmpty) return favBoards.toSet();
  if (keywords.isNotEmpty) return kMainHomepageBoards;
  return kDefaultFavoriteBoards;
}

/// 공지 화면이 지금 학교에서 받을 게시판. 순수 함수 — 테스트 대상.
///
/// 예전엔 화면을 열면 48개를 전부 받고 탭·칩은 걸러 보여 주기만 했다. 이제
/// **보고 있는 범위만** 받는다:
/// - 게시판을 하나 골랐으면 그 게시판만.
/// - 하위 탭(학사안내·제2대학…)을 골랐으면 그 안의 게시판.
/// - 큰 탭 "전체": [공지사항]은 그 탭의 게시판 전부, [대학/대학원]은
///   즐겨찾기한 학과만(27개를 한꺼번에 받지 않는다).
Set<String> noticeFetchScope({
  required String mainTab,
  String? subGroup,
  String? category,
  required Iterable<String> favorites,
}) {
  if (category != null) return {category};
  final groups = KnueScraper.noticeTabStructure[mainTab] ?? const {};
  if (subGroup != null) return {...?groups[subGroup]};
  final all = {for (final g in groups.values) ...g};
  if (mainTab == kNoticeOnDemandTab) return all.intersection(favorites.toSet());
  return all;
}

/// 게시판 하나. 같은 이름(category)의 게시판이 두 개 있어서('교육대학원' —
/// 사도교육원과 대학원) 이름만으로는 구분이 안 된다. url이 고유하다.
typedef NoticeBoard = ({String group, String category, String url});

/// 서버(host)별로 줄을 세운다. 순수 함수 — 테스트 대상.
///
/// 같은 서버에는 한 번에 하나씩 차례로 보내고, 서로 다른 서버끼리만 동시에
/// 받는다. 'LINK:' 게시판은 받지 않으므로 뺀다.
Map<String, List<NoticeBoard>> boardQueuesByHost(Iterable<NoticeBoard> boards) {
  final queues = <String, List<NoticeBoard>>{};
  for (final b in boards) {
    if (b.url.startsWith('LINK:')) continue;
    final host = Uri.tryParse(b.url)?.host ?? '';
    (queues[host] ??= []).add(b);
  }
  return queues;
}

/// 새로 받은 게시판 목록을 캐시에 합친다. 순수 함수 — 테스트 대상.
///
/// 받은 게시판은 그 게시판 몫을 **통째로 바꾼다**(글 id로 합치면 지워진
/// 글이 캐시에 영영 남는다). 빈 결과는 실패로 보고 기존 것을 둔다.
/// [validBoards]에 없는 게시판(목록에서 빠진 것)의 옛 글은 버린다.
List<Notice> mergeNoticeCache(
  List<Notice> cached,
  Map<(String, String), List<Notice>> fresh,
  Set<(String, String)> validBoards,
) {
  final replaced = {
    for (final e in fresh.entries)
      if (e.value.isNotEmpty) e.key,
  };
  final merged = <Notice>[
    for (final n in cached)
      if (validBoards.contains((n.group, n.category)) &&
          !replaced.contains((n.group, n.category)))
        n,
    for (final e in fresh.entries) ...e.value,
  ]..sort((a, b) => b.date.compareTo(a.date));
  return merged;
}

class KnueScraper {
  /// 크롤링 대상 게시판(notice_boards.dart). 중앙 수집기와 같은 목록이다.
  Map<String, Map<String, String>> get boardGroups => kNoticeBoardGroups;

  /// 청람공지 화면의 표시 구조(notice_boards.dart).
  static const Map<String, Map<String, List<String>>> noticeTabStructure =
      kNoticeTabStructure;

  /// 네트워크 오류·시간 초과 때 다시 보내는 횟수. 예전엔 3번(최대 4배)이라
  /// 학교 서버가 느려질수록 요청이 불어났다. 서버가 **응답한** 오류(4xx·5xx)는
  /// 곧바로 다시 보내도 소용없으니 다시 보내지 않는다.
  static const int maxRetries = 1;
  static const Duration retryDelay = Duration(seconds: 5);

  /// 한 서버에서 이만큼 연달아 실패하면 그 회차엔 그 서버를 건너뛴다.
  static const int _maxFailuresInRow = 3;

  /// 한 번에 캐시에 반영하는 게시판 수. 전체를 차례로 받으면 20초쯤 걸려서,
  /// 다 받을 때까지 기다리지 않고 중간중간 화면에 채워 넣는다.
  static const int _flushEvery = 10;

  List<NoticeBoard> get _allBoards => [
    for (final g in boardGroups.entries)
      for (final b in g.value.entries)
        (group: g.key, category: b.key, url: b.value),
  ];

  /// 공지 가져오기. 캐시가 있으면 즉시 돌려주고 갱신은 뒤에서 한다.
  ///
  /// [onlyCategories]를 주면 그 게시판만 받고 그 게시판 글만 돌려준다.
  /// 학교 서버로는 게시판마다 [kNoticeAutoRefreshGap](자동) /
  /// [kNoticeFirstLoadGap](캐시가 없을 때) 안에 두 번 가지 않는다 — 이 제한은
  /// 기기에 저장돼 앱을 다시 켜도 유지된다. 제한에 걸린 게시판은 캐시에 있는
  /// 글을 그대로 쓴다.
  ///
  /// [forceRefresh](당겨서 새로 고침·새로고침 버튼·백그라운드 알림)는 제한 없이
  /// 매번 받는다. 사람이 직접 요청한 것이고 드물다. 다만 받은 시각은 기록돼서,
  /// 곧이어 도는 자동 갱신이 같은 게시판을 또 받지는 않는다.
  Future<List<Notice>> fetchAllNotices({
    bool forceRefresh = false,
    Set<String>? onlyCategories,
  }) async {
    final wanted = [
      for (final b in _allBoards)
        if (onlyCategories == null || onlyCategories.contains(b.category)) b,
    ];
    final cached = await NoticeCache.load();
    if (!forceRefresh && cached != null && cached.isNotEmpty) {
      Future.delayed(RefreshThrottle.warmupDelay, () async {
        try {
          await _refreshBoards(wanted, kNoticeAutoRefreshGap);
        } catch (e) {
          debugPrint('공지 배경 갱신 실패: $e');
        }
      });
      return _scope(cached, onlyCategories);
    }
    await _refreshBoards(
      wanted,
      forceRefresh ? Duration.zero : kNoticeFirstLoadGap,
    );
    return _scope(await NoticeCache.load() ?? const [], onlyCategories);
  }

  /// [categories] 게시판 중 [gap]이 지난 것만 지금 받아 캐시에 합치고, 끝날
  /// 때까지 기다린다. 공지 화면이 보고 있는 범위를 받을 때 쓴다
  /// ([noticeFetchScope]). [gap]이 0이면 당겨서 새로 고침처럼 무조건 받는다.
  /// 결과는 [NoticeCache]에서 읽는다.
  Future<void> refreshBoards(
    Set<String> categories, {
    Duration gap = kNoticeAutoRefreshGap,
  }) =>
      _refreshBoards(
        [
          for (final b in _allBoards)
            if (categories.contains(b.category)) b,
        ],
        gap,
      );

  static List<Notice> _scope(List<Notice> notices, Set<String>? only) =>
      only == null
          ? notices
          : notices.where((n) => only.contains(n.category)).toList();

  /// [boards] 중 간격 제한이 지난 것만 받아 캐시에 합친다.
  /// 서버마다 동시에 [kSchoolMaxConcurrent]개까지만 보낸다.
  Future<void> _refreshBoards(List<NoticeBoard> boards, Duration gap) async {
    final dueUrls = (await PersistentThrottle.acquire(
      'notice_board',
      boards.where((b) => !b.url.startsWith('LINK:')).map((b) => b.url),
      gap,
    )).toSet();
    if (dueUrls.isEmpty) return;

    final valid = {for (final b in _allBoards) (b.group, b.category)};
    var pending = <(String, String), List<Notice>>{};
    var flushing = Future<void>.value();
    void flush() {
      if (pending.isEmpty) return;
      final batch = pending;
      pending = {};
      // 합치기는 차례로 — 동시에 하면 앞의 결과를 뒤의 것이 덮어쓴다.
      flushing = flushing.then((_) async {
        final merged =
            mergeNoticeCache(await NoticeCache.load() ?? const [], batch, valid);
        await NoticeCache.save(merged);
      });
    }

    final queues = boardQueuesByHost(boards.where((b) => dueUrls.contains(b.url)));
    await Future.wait(queues.entries.map((q) async {
      final queue = q.value;
      var next = 0;
      var failuresInRow = 0;
      // 서버마다 일꾼 [kSchoolMaxConcurrent]명이 줄에서 하나씩 꺼내 간다.
      Future<void> worker() async {
        while (next < queue.length) {
          // 서버가 연달아 실패하면 이번 회차엔 그 서버를 그만 두드린다.
          // 남은 게시판은 다음 간격이 지난 뒤에 다시 받는다.
          if (failuresInRow >= _maxFailuresInRow) {
            debugPrint('${q.key}: 연속 $failuresInRow번 실패 — 남은 ${queue.length - next}개 건너뜀');
            next = queue.length;
            return;
          }
          final b = queue[next++];
          try {
            final list = await _fetchBoardWithRetry(b.group, b.category, b.url);
            // 같은 이름 게시판('교육대학원')이 두 개라 키에 그룹까지 넣는다.
            (pending[(b.group, b.category)] ??= []).addAll(list);
            failuresInRow = 0;
          } catch (e) {
            failuresInRow++;
            debugPrint('Error fetching ${b.group} - ${b.category}: $e');
          }
          if (pending.length >= _flushEvery) flush();
        }
      }

      await Future.wait([
        for (var i = 0; i < kSchoolMaxConcurrent && i < queue.length; i++)
          worker(),
      ]);
    }));
    flush();
    await flushing;
  }

  Future<List<Notice>> _fetchBoardWithRetry(
    String group,
    String category,
    String url, {
    int retry = 0,
  }) async {
    try {
      return await _fetchBoard(group, category, url);
    } catch (e) {
      if (e is! _HttpStatusException && retry < maxRetries) {
        await Future.delayed(retryDelay);
        return _fetchBoardWithRetry(group, category, url, retry: retry + 1);
      }
      rethrow;
    }
  }

  Future<List<Notice>> _fetchBoard(
    String group,
    String category,
    String url,
  ) async {
    if (url.startsWith('LINK:')) return [];

    final response = await http
        .get(Uri.parse(url), headers: await SchoolHttp.headers())
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw _HttpStatusException(response.statusCode);
    }

    // 도서관 게시판 (JSON API 처리)
    if (url.contains('pyxis-api')) {
      try {
        return parsePyxisNotices(response.body, group: group, category: category);
      } catch (e) {
        debugPrint('Parsing JSON error in $category: $e');
        return [];
      }
    }

    String decodedHtml;
    try {
      decodedHtml = utf8.decode(response.bodyBytes);
    } catch (e) {
      decodedHtml = cp949.decode(response.bodyBytes);
    }

    // 🔥 무거운 HTML 파싱 작업을 별도 Isolate(compute)에서 실행하여 UI 프리징 방지
    return await compute(parseHtml, {
      'html': decodedHtml,
      'group': group,
      'category': category,
      'url': url,
    });
  }

  /// 게시판 목록 HTML 파싱(notice_parse.dart). 테스트·기존 호출부를 위해 남긴 이름.
  static List<Notice> parseHtml(Map<String, dynamic> params) =>
      parseNoticeHtml(params);

  // Isolate에서는 정적 메서드만 사용하므로 기존 인스턴스 메서드들은 삭제되었습니다.

  /// 학사일정. [year]년 [month]월에 걸친 일정.
  ///
  /// 학년도 하나를 공용 캐시(Firestore)에 두고 모든 기기가 나눠 쓴다 —
  /// [AcademicCalendarStore] 참고. 호출부는 예전처럼 달 단위로 부르면 된다.
  Future<List<CalendarEvent>> fetchCalendarEvents(int year, int month) async {
    final events =
        await AcademicCalendarStore.load(academicYearOf(year, month));
    return scopeEventsToMonth(events, year, month);
  }
}

/// 서버가 200이 아닌 응답을 줬다. 네트워크 오류와 달리 다시 보내지 않는다.
class _HttpStatusException implements Exception {
  final int statusCode;
  const _HttpStatusException(this.statusCode);
  @override
  String toString() => 'HTTP $statusCode';
}

/// 공지 캐시 — bus의 OfflineCache와 동일 패턴 (SharedPreferences + JSON)
class NoticeCache {
  static const _key = 'noticeCache';
  static const _maxItems = 1000;

  /// 게시판마다 최소한 이만큼은 남긴다.
  static const _minPerBoard = 20;

  /// save()될 때마다 값이 바뀐다. fetchAllNotices()는 캐시를 먼저 반환하고
  /// 백그라운드로 갱신하는데(await 없이), 이 리스너가 있어야 화면이 갱신 완료를
  /// 알아채고 최신 데이터로 다시 그릴 수 있다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 상한에 맞춰 잘라내되, 게시판마다 [_minPerBoard]건은 남긴다.
  ///
  /// 날짜순으로만 자르면 글이 뜸한 게시판이 통째로 사라진다. 실제로 교환학생·
  /// 체육교육과·윤리교육과 등 6개 게시판은 크롤링이 멀쩡히 되는데도 앱에서는
  /// 0건이었고, 화면은 그걸 "불러오지 못했습니다"로 표시했다.
  static List<Notice> _trim(List<Notice> notices) {
    if (notices.length <= _maxItems) return notices;
    final sorted = List<Notice>.of(notices)
      ..sort((a, b) => b.date.compareTo(a.date));

    final perBoard = <String, int>{};
    final kept = <Notice>[];
    final rest = <Notice>[];
    for (final n in sorted) {
      final seen = perBoard[n.category] ?? 0;
      if (seen < _minPerBoard) {
        perBoard[n.category] = seen + 1;
        kept.add(n);
      } else {
        rest.add(n);
      }
    }
    // 게시판 몫을 채우고 남은 자리는 최신 순으로 메운다.
    for (final n in rest) {
      if (kept.length >= _maxItems) break;
      kept.add(n);
    }
    kept.sort((a, b) => b.date.compareTo(a.date));
    return kept;
  }

  static Future<void> save(List<Notice> notices) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _trim(notices);
    final encoded = jsonEncode(trimmed.map((e) => e.toJson()).toList());
    // 내용이 같으면 revision을 올리지 않는다 — 올리면 화면이 다시 로드하고,
    // 그게 또 갱신을 불러 무한 루프가 된다.
    final changed = prefs.getString(_key) != encoded;
    await prefs.setString(_key, encoded);
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
    if (changed) revision.value++;
  }

  static Future<List<Notice>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list
          .map((e) => Notice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastUpdated() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getInt('${_key}_ts');
    return ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
  }
}
