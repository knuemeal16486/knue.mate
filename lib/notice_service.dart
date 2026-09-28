import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter/foundation.dart';
import 'academic_calendar.dart';
import 'notice_model.dart';
import 'offline_cache.dart';
import 'school_http.dart';

export 'academic_calendar.dart';

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

/// 백그라운드 알림 작업이 받을 게시판. null이면 전체. 순수 함수 — 테스트 대상.
///
/// 예전엔 늘 전체 48개를 받았다. 알림은 즐겨찾기 게시판 것만 보내므로 그것만
/// 받는다. 즐겨찾기가 없을 때:
/// - 키워드가 있으면 전체 — 키워드 알림은 원래 모든 게시판에서 찾아 줬다.
///   이걸 줄이면 사용자가 받던 알림이 말없이 끊긴다.
/// - 키워드도 없으면 기본 4개 — 예전엔 48개 게시판의 새 글이 전부 알림으로
///   왔다(아무것도 설정 안 한 사람에게).
Set<String>? backgroundNoticeBoards(
  Iterable<String> favBoards,
  Iterable<String> keywords,
) {
  if (favBoards.isNotEmpty) return favBoards.toSet();
  if (keywords.isNotEmpty) return null;
  return kDefaultFavoriteBoards;
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
  // 모든 게시판 그룹 (기존과 동일)
  final Map<String, Map<String, String>> boardGroups = {
    'MAIN': {
      '대학소식': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=25&key=806',
      '학사공지': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=26&key=807',
      '청람소양':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=256&key=1609',
      '학점교류':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=254&key=1562',
      '등록금': 'https://www.knue.ac.kr/www/selectBbsNttList.do?key=550&bbsNo=11',
      '장학금':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=207&key=1443',
      '교환학생': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=13&key=597',
      '행사세미나':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=28&key=809',
      '채용공고': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=27&key=808',
      '입찰공고': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=29&key=810',
    },
    'ANNEX': {
      '도서관일반':
          'https://lib.knue.ac.kr/pyxis-api/1/bulletin-boards/1/bulletins?max=20&offset=0',
      '도서관학술':
          'https://lib.knue.ac.kr/pyxis-api/1/bulletin-boards/2/bulletins?max=20&offset=0',
      // 종합교육연수원 (공통 게시판 패턴)
      '종합연수원':
          'https://tot.knue.ac.kr/common/bbs/management/selectCmmnBBSMgmtList.do?menuId=3000001755&bbsId=BBSMSTR_003000000094',
      // 영유아교육연수원
      '영유아연수원':
          'https://tot.knue.ac.kr/common/bbs/management/selectCmmnBBSMgmtList.do?menuId=3000001756&bbsId=BBSMSTR_003000000576',
      // 신문방송사 (기사 목록 URL)
      '신문방송사':
          'https://m.news.knue.ac.kr/news/articleList.html?sc_section_code=S1N3',
      // 사도교육원
      '일반공지': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=edunotice',
      '학부/대학원': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=notice',
      '교육대학원': 'http://rec.knue.ac.kr/bbs/lstBoard.jsp?bodcode=boardt',
    },
    'LIFE': {
      '학생지원':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=258&key=1625',
      '임용안내':
          'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=259&key=1630',
      '취업정보': 'https://www.knue.ac.kr/www/selectBbsNttList.do?bbsNo=12&key=574',
    },
    'DEPT': {
      // 제1대학
      '교육학과':
          'https://www.knue.ac.kr/education/selectBbsNttList.do?bbsNo=86&key=985',
      '유아교육과':
          'https://www.knue.ac.kr/ece/selectBbsNttList.do?bbsNo=93&key=1005',
      '초등교육과': 'LINK:https://m.cafe.daum.net/knue-primary/_rec',
      '특수교육과':
          'https://www.knue.ac.kr/sped/selectBbsNttList.do?bbsNo=100&key=1025',

      // 제2대학
      '국어교육과':
          'https://www.knue.ac.kr/korean/selectBbsNttList.do?bbsNo=106&key=1044',
      '영어교육과':
          'https://www.knue.ac.kr/english/selectBbsNttList.do?bbsNo=113&key=1114',
      '독어교육과':
          'https://www.knue.ac.kr/german/selectBbsNttList.do?bbsNo=223&key=1065',
      '불어교육과':
          'https://www.knue.ac.kr/french/selectBbsNttList.do?bbsNo=119&key=1079',
      '중국어교육과':
          'https://www.knue.ac.kr/chinese/selectBbsNttList.do?bbsNo=226&key=1143',
      '윤리교육과':
          'https://www.knue.ac.kr/ethics/selectBbsNttList.do?bbsNo=189&key=1343',
      '일반사회교육과':
          'https://www.knue.ac.kr/social/selectBbsNttList.do?bbsNo=133&key=1132',
      '지리교육과':
          'https://www.knue.ac.kr/geography/selectBbsNttList.do?bbsNo=229&key=1158',
      '역사교육과':
          'https://www.knue.ac.kr/history/selectBbsNttList.do?bbsNo=141&key=1092',

      // 제3대학
      '수학교육과':
          'https://www.knue.ac.kr/math/selectBbsNttList.do?bbsNo=151&key=1231',
      '물리교육과':
          'https://www.knue.ac.kr/phys/selectBbsNttList.do?bbsNo=194&key=1202',
      '화학교육과':
          'https://www.knue.ac.kr/chemedu/selectBbsNttList.do?bbsNo=235&key=1273',
      '생물교육과':
          'https://www.knue.ac.kr/bioedu/selectBbsNttList.do?bbsNo=161&key=1216',
      '지구과학교육과':
          'https://www.knue.ac.kr/earth/selectBbsNttList.do?bbsNo=166&key=1247',
      '가정교육과':
          'https://www.knue.ac.kr/homeedu/selectBbsNttList.do?bbsNo=199&key=1176',
      '환경교육과':
          'https://www.knue.ac.kr/envi/selectBbsNttList.do?bbsNo=178&key=1285',
      '기술교육과':
          'https://www.knue.ac.kr/techedu/selectBbsNttList.do?bbsNo=169&key=1189',
      '컴퓨터교육과':
          'https://www.knue.ac.kr/comedu/selectBbsNttList.do?bbsNo=242&key=1258',

      // 제4대학
      '음악교육과':
          'https://www.knue.ac.kr/music/selectBbsNttList.do?bbsNo=204&key=1314',
      '체육교육과':
          'https://www.knue.ac.kr/phy/selectBbsNttList.do?bbsNo=211&key=1327',
      '미술교육과':
          'https://www.knue.ac.kr/artedu/selectBbsNttList.do?bbsNo=181&key=1300',
    },
    'GRAD': {
      '대학원': 'https://www.knue.ac.kr/grad/selectBbsNttList.do?bbsNo=67&key=645',
      '교육대학원':
          'https://www.knue.ac.kr/grad/selectBbsNttList.do?bbsNo=68&key=646',
      '교육정책대학원':
          'https://www.knue.ac.kr/edupol/selectBbsNttList.do?bbsNo=73&key=659',
    },
  };

  /// 청람공지 화면의 표시 구조 — 큰 탭(공지사항 / 대학·대학원) → 하위 탭 →
  /// 게시판. boardGroups(크롤링 대상)와는 별개의 "보여주는 방식"만 담당한다
  /// — 여기 값을 바꿔도 크롤링이나 즐겨찾기·키워드 알림 저장 키(게시판
  /// 이름 그 자체)는 그대로다.
  ///
  /// '교육대학원'이 캠퍼스 생활(사도교육원 소속, 기숙사 공지)과 대학원
  /// (GRAD 소속, 학사 공지) 양쪽에 나오는데, 이건 boardGroups에 실제로
  /// 이름이 같은 게시판 두 개가 따로 있어서다(원래부터 있던 것 — 두 게시판이
  /// 같은 category 문자열을 공유해 즐겨찾기/알림이 서로 엮일 수 있는 상태).
  static const Map<String, Map<String, List<String>>> noticeTabStructure = {
    '공지사항': {
      '학사안내': [
        '대학소식',
        '학사공지',
        '등록금',
        '장학금',
        '청람소양',
        '행사세미나',
        '채용공고',
        '입찰공고',
      ],
      '교류 프로그램': ['학점교류', '교환학생'],
      '캠퍼스 생활': [
        '학생지원',
        '임용안내',
        '취업정보',
        '일반공지',
        '학부/대학원',
        '교육대학원',
        '도서관일반',
        '도서관학술',
        '종합연수원',
        '영유아연수원',
        '신문방송사',
      ],
    },
    '대학/대학원': {
      '제1대학': ['교육학과', '유아교육과', '초등교육과', '특수교육과'],
      '제2대학': [
        '국어교육과',
        '영어교육과',
        '독어교육과',
        '불어교육과',
        '중국어교육과',
        '윤리교육과',
        '일반사회교육과',
        '지리교육과',
        '역사교육과',
      ],
      '제3대학': [
        '수학교육과',
        '물리교육과',
        '화학교육과',
        '생물교육과',
        '지구과학교육과',
        '가정교육과',
        '환경교육과',
        '기술교육과',
        '컴퓨터교육과',
      ],
      '제4대학': ['음악교육과', '체육교육과', '미술교육과'],
      '대학원': ['대학원', '교육대학원', '교육정책대학원'],
    },
  };

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

    final notices = <Notice>[];

    // 도서관 게시판 (JSON API 처리)
    if (url.contains('pyxis-api')) {
      try {
        final decoded = jsonDecode(response.body);
        final list = decoded['data']['list'] as List;
        for (var item in list) {
          String title = item['title'] ?? '제목없음';
          String date =
              _normalizeDate((item['dateCreated'] ?? '').split(' ')[0]) ?? '';
          String author = item['writer'] ?? '학교';
          // 공지사항 1번, 학술 2번

          String fullLink =
              'https://lib.knue.ac.kr/#/bbs/notice/${item['id']}?offset=0&max=20';

          // Stable ID generation using title and link
          int id = (title + fullLink).hashCode;
          bool isNew = date == DateFormat('yyyy-MM-dd').format(DateTime.now());

          notices.add(
            Notice(
              id: id,
              category: category,
              group: group,
              title: title,
              date: date,
              author: author,
              link: fullLink,
              isNew: isNew,
            ),
          );
        }
      } catch (e) {
        debugPrint('Parsing JSON error in $category: $e');
      }
      return notices;
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

  // 🔥 Isolate에서 실행할 static 파싱 함수 (테스트를 위해 public)
  static List<Notice> parseHtml(Map<String, dynamic> params) {
    final String html = params['html'];
    final String group = params['group'];
    final String category = params['category'];
    final String url = params['url'];

    final doc = parser.parse(html);
    // 신문방송사는 게시판이 아니라 기사 목록이라 표가 없다. 구조가 아예 달라
    // 전용 경로로 보낸다.
    if (url.contains('news.knue.ac.kr')) {
      return _parseNewsList(doc, group, category, url);
    }

    final notices = <Notice>[];
    final rows = doc.querySelectorAll('tbody tr');

    for (var row in rows) {
      try {
        var titleEl =
            row.querySelector('.p-subject a') ?? row.querySelector('a');
        if (titleEl == null) continue;

        String title = titleEl.text.trim();
        title = title.replaceAll(RegExp(r'\[?새글\]?\s*'), '').trim();

        String relativeLink = titleEl.attributes['href'] ?? '';
        String fullLink = _resolveLinkStatic(url, relativeLink);

        var tds = row.querySelectorAll('td');
        String? date;
        String author = '학교';

        // 제목 칸은 건너뛴다. 제목에 날짜가 들어간 공지가 있어서
        // ("제42권 제6호(2026.11.30.발간예정)") 앞에서부터 찾으면 그 날짜를
        // 게시일로 읽고, 미래 날짜라 목록 맨 위에 박힌다. 등록일은 보통
        // 마지막 날짜 칸이다.
        for (var td in tds) {
          if (td.querySelector('a') != null) continue;
          final d = _normalizeDate(td.text.trim());
          if (d != null) date = d;
        }

        // 날짜 칸을 하나도 못 찾았을 때만 제목 칸까지 포함해 훑는다.
        if (date == null) {
          for (var td in tds) {
            date = _normalizeDate(td.text.trim());
            if (date != null) break;
          }
        }

        // 그래도 없으면 컬럼 위치로 추정 — 이 추정치도 실제 날짜
        // 형태일 때만 채택한다(조회수/작성자 등 엉뚱한 값이 날짜로 둔갑하는 것 방지).
        if (date == null && tds.length > 2) {
          date = tds.length > 4
              ? _normalizeDate(tds[4].text.trim())
              : _normalizeDate(tds[2].text.trim());
        }
        final dateStr = date ?? '';

        if (tds.length > 2) {
          String tempAuthor = tds[2].text.trim();
          if (tempAuthor != dateStr && !RegExp(r'\d{4}').hasMatch(tempAuthor)) {
            // 3번째 칸은 작성자가 아니라 첨부파일 칸인 게시판이 많다.
            // 거르지 않으면 "여러개의 파일 첨부"가 작성자로 들어간다.
            if (!tempAuthor.contains('첨부')) author = tempAuthor;
          }
        }

        int id = Object.hash(group, category, title, fullLink);
        bool isNew = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

        notices.add(
          Notice(
            id: id,
            category: category,
            group: group,
            title: title,
            date: dateStr,
            author: author,
            link: fullLink,
            isNew: isNew,
          ),
        );
      } catch (e) {
        // Isolate 내에서는 print보다는 로그 기록 권장되나 기존 로직 유지
      }
    }
    return notices;
  }

  /// 신문방송사 기사 목록. 표가 아니라 `#section-list li` 구조이고,
  /// 날짜가 "09.07 09:22"처럼 연도 없이 나온다.
  static List<Notice> _parseNewsList(
    dynamic doc,
    String group,
    String category,
    String url,
  ) {
    final notices = <Notice>[];
    final today = DateTime.now();
    for (final li in doc.querySelectorAll('#section-list li')) {
      final a = li.querySelector('a');
      if (a == null) continue;
      final titleEl = li.querySelector('.titles') ?? a;
      final title = titleEl.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (title.isEmpty) continue;

      final link = _resolveLinkStatic(url, a.attributes['href'] ?? '');
      final author = li.querySelector('.info.name')?.text.trim() ?? '';
      final dateStr =
          _newsDate(li.querySelector('.info.dated')?.text.trim() ?? '', today);

      notices.add(
        Notice(
          id: Object.hash(group, category, title, link),
          category: category,
          group: group,
          title: title,
          date: dateStr,
          author: author.isEmpty ? '한국교원대신문' : author,
          link: link,
          isNew: dateStr == DateFormat('yyyy-MM-dd').format(today),
        ),
      );
    }
    return notices;
  }

  /// 기사 날짜. 연도가 없으면 올해로 보되, 그 결과가 미래면 작년 기사로 본다
  /// (연초에 작년 12월 기사를 올해 12월로 읽어 목록 맨 위에 박히는 것을 막는다).
  static String _newsDate(String raw, DateTime today) {
    final full = _normalizeDate(raw);
    if (full != null) return full;
    final m = RegExp(r'(\d{1,2})[.-](\d{1,2})').firstMatch(raw);
    if (m == null) return '';
    final month = int.parse(m.group(1)!), day = int.parse(m.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return '';
    var d = DateTime(today.year, month, day);
    if (d.isAfter(today.add(const Duration(days: 1)))) {
      d = DateTime(today.year - 1, month, day);
    }
    return DateFormat('yyyy-MM-dd').format(d);
  }

  /// 게시판마다 다른 날짜 표기(2/4자리 연도, '-'/'.' 구분자)를 "yyyy-MM-dd"로
  /// 정규화한다. 정규화해야 게시판이 달라도 문자열 비교로 안전하게 정렬·비교할 수 있다.
  /// 날짜로 보이지 않으면 null — 조회수/작성자 같은 값을 날짜로 오인하지 않기 위함.
  static String? _normalizeDate(String raw) {
    final match = RegExp(r'(\d{2,4})[-.](\d{1,2})[-.](\d{1,2})').firstMatch(raw);
    if (match == null) return null;
    int year = int.parse(match.group(1)!);
    if (year < 100) year += 2000;
    final month = match.group(2)!.padLeft(2, '0');
    final day = match.group(3)!.padLeft(2, '0');
    return '$year-$month-$day';
  }

  static String _resolveLinkStatic(String baseUrl, String relative) {
    if (relative.isEmpty) return baseUrl;
    if (relative.startsWith('http')) return relative;
    try {
      var uri = Uri.parse(baseUrl);
      var resolved = uri.resolve(relative);
      return resolved.toString();
    } catch (e) {
      return baseUrl + (relative.startsWith('/') ? relative : '/$relative');
    }
  }

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
