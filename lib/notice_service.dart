import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cp949_codec/cp949_codec.dart';
import 'package:flutter/foundation.dart';
import 'notice_model.dart';

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

  static const Map<String, List<String>> collegeStructure = {
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
    '제4대학': ['음악교육과', '미술교육과', '체육교육과'],
  };

  static const Map<String, List<String>> annexStructure = {
    '도서관': ['도서관일반', '도서관학술'],
    '연수원': ['종합연수원', '영유아연수원'],
    '신문방송사': ['신문방송사'],
    '사도교육원': ['일반공지', '학부/대학원', '교육대학원'],
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
        _fetchAndUpdateCache(onlyCategories: onlyCategories); // await 없이 갱신
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

    final notices = <Notice>[];
    final doc = parser.parse(html);
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

        for (var td in tds) {
          date = _normalizeDate(td.text.trim());
          if (date != null) break;
        }

        // 정규식으로 못 찾았을 때만 컬럼 위치로 추정 — 이 추정치도 실제 날짜
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
            author = tempAuthor;
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
  Future<List<CalendarEvent>> fetchCalendarEvents(int year, int month) async {
    final baseUrl = 'https://www.knue.ac.kr/www/selectSchdleWebList.do';
    final monthStr = month.toString().padLeft(2, '0');
    final url = Uri.parse('$baseUrl?key=542&searchY=$year&searchM=$monthStr');

    try {
      final response = await http.get(url);
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
          endDate = DateTime(
            year,
            int.tryParse(mStr) ?? 1,
            int.tryParse(dStr) ?? 1,
          );
        } else {
          endDate = startDate;
        }

        if (startDate != null && endDate != null && title.isNotEmpty) {
          events.add(
            CalendarEvent(startDate: startDate, endDate: endDate, title: title),
          );
        }
      }
      return events;
    } catch (e) {
      debugPrint('Calendar Fetch Error: $e');
      return [];
    }
  }
}

/// 공지 캐시 — bus의 OfflineCache와 동일 패턴 (SharedPreferences + JSON)
class NoticeCache {
  static const _key = 'noticeCache';
  static const _maxItems = 500;

  /// save()될 때마다 값이 바뀐다. fetchAllNotices()는 캐시를 먼저 반환하고
  /// 백그라운드로 갱신하는데(await 없이), 이 리스너가 있어야 화면이 갱신 완료를
  /// 알아채고 최신 데이터로 다시 그릴 수 있다.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> save(List<Notice> notices) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = notices.take(_maxItems).toList();
    await prefs.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
    await prefs.setInt('${_key}_ts', DateTime.now().millisecondsSinceEpoch);
    revision.value++;
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
