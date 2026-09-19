import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter/foundation.dart';
import 'notice_model.dart';
import 'offline_cache.dart';

/// 학교 학사일정 페이지는 searchM을 받아도 그 학년도 전체 일정을 한 번에
/// 돌려준다(실측: searchM=09로 요청해도 1~12월 행이 전부 섞여 온다). 여기서
/// 걸러내지 않으면 9월 카드에 1월 일정까지 그대로 들어간다. 월 경계에 걸친
/// 일정(예: 8.31~9.4)은 양쪽 달 모두에 걸리는 게 맞으므로 날짜 범위가 그
/// 달과 겹치는지로 판단한다. 순수 함수 — 테스트 대상.
List<CalendarEvent> scopeEventsToMonth(
  List<CalendarEvent> events,
  int year,
  int month,
) {
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 1);
  return events
      .where(
        (e) => e.startDate.isBefore(monthEnd) && !e.endDate.isBefore(monthStart),
      )
      .toList();
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

  // 최대 재시도 횟수
  static const int maxRetries = 3;

  /// 공지 가져오기. 캐시가 있으면 즉시 반환하고 백그라운드 갱신.
  /// [onlyCategories] 지정 시 해당 게시판만 크롤링(홈 대시보드 경량 경로).
  Future<List<Notice>> fetchAllNotices({
    bool forceRefresh = false,
    Set<String>? onlyCategories,
  }) async {
    if (!forceRefresh) {
      final cached = await NoticeCache.load();
      if (cached != null && cached.isNotEmpty) {
        // throttle이 없으면 revision→재로드→갱신이 끝없이 돌며 즐겨찾기
        // 게시판 전체를 계속 스크래핑한다.
        final key = 'notices_${(onlyCategories?.toList()?..sort())?.join(",") ?? "all"}';
        RefreshThrottle.deferred(
          key,
          () => _fetchAndUpdateCache(onlyCategories: onlyCategories),
        );
        return cached;
      }
    }
    return _fetchAndUpdateCache(onlyCategories: onlyCategories);
  }

  Future<List<Notice>> _fetchAndUpdateCache({Set<String>? onlyCategories}) async {
    List<Notice> all = [];
    List<Future<List<Notice>>> futures = [];

    for (var groupEntry in boardGroups.entries) {
      String groupName = groupEntry.key;
      for (var entry in groupEntry.value.entries) {
        if (onlyCategories != null && !onlyCategories.contains(entry.key)) {
          continue;
        }
        futures.add(
          _fetchBoardWithRetry(groupName, entry.key, entry.value)
              .catchError((e) {
            debugPrint('Error fetching $groupName - ${entry.key}: $e');
            return <Notice>[];
          }),
        );
      }
    }

    for (int i = 0; i < futures.length; i += 5) {
      int end = (i + 5 < futures.length) ? i + 5 : futures.length;
      final results = await Future.wait(futures.sublist(i, end));
      for (var res in results) {
        all.addAll(res);
      }
    }

    all.sort((a, b) => b.date.compareTo(a.date));

    if (onlyCategories == null) {
      await NoticeCache.save(all);
    } else if (all.isNotEmpty) {
      // 부분 크롤링은 기존 캐시에 병합
      final existing = await NoticeCache.load() ?? [];
      final ids = all.map((n) => n.id).toSet();
      existing.removeWhere((n) => ids.contains(n.id));
      final merged = [...all, ...existing]
        ..sort((a, b) => b.date.compareTo(a.date));
      await NoticeCache.save(merged);
    }
    return all;
  }

  // 재시도 로직이 포함된 게시판 가져오기
  Future<List<Notice>> _fetchBoardWithRetry(
    String group,
    String category,
    String url, {
    int retry = 0,
  }) async {
    try {
      return await _fetchBoard(group, category, url);
    } catch (e) {
      if (retry < maxRetries) {
        await Future.delayed(Duration(seconds: 1 * (retry + 1)));
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
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
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

  // 달력 행사 스크래핑
  /// 학사일정. 공지·동아리와 같은 "캐시 먼저, 갱신은 뒤에서" 방식이다.
  /// 한 달치 일정은 자주 바뀌지 않는데 매번 스크래핑을 기다리느라 홈 카드가
  /// 800ms 가까이 비어 있었다.
  Future<List<CalendarEvent>> fetchCalendarEvents(
    int year,
    int month, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await CalendarCache.load(year, month);
      if (cached != null) {
        // throttle이 없으면 갱신→재로드→갱신으로 계속 스크래핑한다.
        RefreshThrottle.deferred(
          "calendar_${year}_$month",
          () => _fetchCalendarAndCache(year, month),
        );
        return cached;
      }
    }
    return _fetchCalendarAndCache(year, month);
  }

  Future<List<CalendarEvent>> _fetchCalendarAndCache(
      int year, int month) async {
    final baseUrl = 'https://www.knue.ac.kr/www/selectSchdleWebList.do';
    final monthStr = month.toString().padLeft(2, '0');
    final url = Uri.parse('$baseUrl?key=542&searchY=$year&searchM=$monthStr');

    try {
      // 타임아웃이 없어서, 응답이 안 오면 카드가 영원히 로딩 상태였다.
      final response =
          await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];

      final document = parser.parse(response.body);
      final listBody = document.querySelectorAll('tbody');
      if (listBody.isEmpty) return [];

      final scheduleTrs = document.querySelectorAll('tbody tr').where((tr) {
        return tr.querySelector('.more_link') != null;
      });

      final List<CalendarEvent> events = [];
      for (var tr in scheduleTrs) {
        final titleElem = tr.querySelector('.more_link');
        if (titleElem == null) continue;
        final title = titleElem.text.trim();

        final startSpan = tr.querySelector('.start');
        final endSpan = tr.querySelector('.end');

        DateTime? startDate;
        DateTime? endDate;

        if (startSpan != null) {
          final mStr = startSpan.querySelector('.month')?.text.trim() ?? '01';
          final dStr = startSpan.querySelector('.days')?.text.trim() ?? '01';
          startDate = DateTime(
            year,
            int.tryParse(mStr) ?? 1,
            int.tryParse(dStr) ?? 1,
          );
        }

        if (endSpan != null) {
          final mStr = endSpan.querySelector('.month')?.text.trim() ?? '01';
          final dStr = endSpan.querySelector('.days')?.text.trim() ?? '01';
          final endMonth = int.tryParse(mStr) ?? 1;
          // 종료월이 시작월보다 앞이면(예: 12.28 ~ 1.3) 해가 넘어간 것이다.
          // 둘 다 요청한 year를 그대로 쓰면 종료일이 시작일보다 앞서게 된다.
          final rolledYear =
              startDate != null && endMonth < startDate.month ? year + 1 : year;
          endDate = DateTime(rolledYear, endMonth, int.tryParse(dStr) ?? 1);
        } else {
          endDate = startDate;
        }

        if (startDate != null && endDate != null && title.isNotEmpty) {
          events.add(
            CalendarEvent(startDate: startDate, endDate: endDate, title: title),
          );
        }
      }

      final scoped = scopeEventsToMonth(events, year, month);
      await CalendarCache.save(year, month, scoped);
      return scoped;
    } catch (e) {
      debugPrint('Calendar Fetch Error: $e');
      // 네트워크가 실패해도 저장해둔 값이 있으면 그걸 쓴다.
      return await CalendarCache.load(year, month) ?? [];
    }
  }
}

/// 학사일정 캐시. 월 단위로 저장한다.
class CalendarCache {
  /// 백그라운드 갱신이 끝나면 값이 바뀐다. 화면은 이걸 구독해 다시 그린다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  // v2: 이전 버전은 월 필터링 버그로 전체 학년도 일정을 그대로 캐싱했다.
  // 버전을 올려 기존 기기의 잘못된 캐시를 무시하고 새로 받게 한다.
  static String _key(int year, int month) => 'calendarCache_v2_${year}_$month';

  static Future<List<CalendarEvent>?> load(int year, int month) async {
    // 학사일정은 학기 중 드물게 바뀐다. 오래된 값이라도 빈 카드보다 낫고,
    // 어차피 백그라운드로 갱신된다.
    final raw = await JsonCache.load(_key(year, month),
        maxAge: const Duration(days: 3));
    if (raw is! List) return null;
    try {
      return raw
          .map((e) => CalendarEvent(
                startDate: DateTime.parse(e['start'] as String),
                endDate: DateTime.parse(e['end'] as String),
                title: e['title'] as String,
              ))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
      int year, int month, List<CalendarEvent> events) async {
    final changed = await JsonCache.save(
      _key(year, month),
      events
          .map((e) => {
                'start': e.startDate.toIso8601String(),
                'end': e.endDate.toIso8601String(),
                'title': e.title,
              })
          .toList(),
    );
    // 내용이 같으면 revision을 올리지 않는다 — 올리면 화면이 다시 로드하고,
    // 그게 또 갱신을 불러 무한 루프가 된다.
    if (changed) revision.value++;
  }
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
