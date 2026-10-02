import 'dart:convert';

import 'package:html/parser.dart' as parser;
import 'package:intl/intl.dart';

import 'notice_model.dart';

// 공지 파싱. Flutter 없이 돈다 — 앱과 중앙 수집기(tool/collect_notices.dart)가
// 같은 파서를 쓴다.
/// 게시판 목록 HTML을 공지 목록으로. compute()에 넘길 수 있게 최상위 함수다.
List<Notice> parseNoticeHtml(Map<String, dynamic> params) {
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
      String fullLink = resolveNoticeLink(url, relativeLink);

      var tds = row.querySelectorAll('td');
      String? date;
      String author = '학교';

      // 제목 칸은 건너뛴다. 제목에 날짜가 들어간 공지가 있어서
      // ("제42권 제6호(2026.11.30.발간예정)") 앞에서부터 찾으면 그 날짜를
      // 게시일로 읽고, 미래 날짜라 목록 맨 위에 박힌다. 등록일은 보통
      // 마지막 날짜 칸이다.
      for (var td in tds) {
        if (td.querySelector('a') != null) continue;
        final d = normalizeNoticeDate(td.text.trim());
        if (d != null) date = d;
      }

      // 날짜 칸을 하나도 못 찾았을 때만 제목 칸까지 포함해 훑는다.
      if (date == null) {
        for (var td in tds) {
          date = normalizeNoticeDate(td.text.trim());
          if (date != null) break;
        }
      }

      // 그래도 없으면 컬럼 위치로 추정 — 이 추정치도 실제 날짜
      // 형태일 때만 채택한다(조회수/작성자 등 엉뚱한 값이 날짜로 둔갑하는 것 방지).
      if (date == null && tds.length > 2) {
        date = tds.length > 4
            ? normalizeNoticeDate(tds[4].text.trim())
            : normalizeNoticeDate(tds[2].text.trim());
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
List<Notice> _parseNewsList(
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

    final link = resolveNoticeLink(url, a.attributes['href'] ?? '');
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
String _newsDate(String raw, DateTime today) {
  final full = normalizeNoticeDate(raw);
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
String? normalizeNoticeDate(String raw) {
  final match = RegExp(r'(\d{2,4})[-.](\d{1,2})[-.](\d{1,2})').firstMatch(raw);
  if (match == null) return null;
  int year = int.parse(match.group(1)!);
  if (year < 100) year += 2000;
  final month = match.group(2)!.padLeft(2, '0');
  final day = match.group(3)!.padLeft(2, '0');
  return '$year-$month-$day';
}

String resolveNoticeLink(String baseUrl, String relative) {
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

/// 도서관 게시판(pyxis JSON API) 응답을 공지 목록으로.
List<Notice> parsePyxisNotices(
  String body, {
  required String group,
  required String category,
}) {
  final decoded = jsonDecode(body);
  final list = decoded['data']['list'] as List;
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  return [
    for (final item in list)
      () {
        final String title = item['title'] ?? '제목없음';
        final date =
            normalizeNoticeDate((item['dateCreated'] ?? '').split(' ')[0]) ?? '';
        final link =
            'https://lib.knue.ac.kr/#/bbs/notice/${item['id']}?offset=0&max=20';
        return Notice(
          id: (title + link).hashCode,
          category: category,
          group: group,
          title: title,
          date: date,
          author: item['writer'] ?? '학교',
          link: link,
          isNew: date == today,
        );
      }(),
  ];
}

// ── 학교 RSS ────────────────────────────────────────────────────────────
//
// 정보전산원이 중앙 수집기에서는 HTML 화면 대신 RSS를 권했다(2026-10-02).
//   https://www.knue.ac.kr/rssBbsNtt.do?bbsNo=N
// 대표 홈페이지·학과·대학원 게시판 모두 이 주소 하나로 받는다(확인함).
// 한 번에 최대 50건이고, 글 본문(description)까지 실려 110~770KB다 —
// 기기에서 받기엔 무겁고, 수집기가 받아 제목·링크·날짜·부서만 추린다.

/// 게시판 목록 주소에서 RSS 주소를 만든다. 학교 대표 서버(www.knue.ac.kr)의
/// 게시판이 아니면 null — 도서관·연수원·신문방송사·사도교육원은 RSS가 없다.
/// 순수 함수 — 테스트 대상.
String? noticeRssUrl(String listUrl) {
  final uri = Uri.tryParse(listUrl);
  if (uri == null || uri.host != 'www.knue.ac.kr') return null;
  if (!uri.path.endsWith('/selectBbsNttList.do')) return null;
  final bbsNo = uri.queryParameters['bbsNo'];
  if (bbsNo == null || !RegExp(r'^\d+$').hasMatch(bbsNo)) return null;
  return 'https://www.knue.ac.kr/rssBbsNtt.do?bbsNo=$bbsNo';
}

/// 글 번호. 게시판과 링크로 정해지며 **어느 기기에서 계산해도 같다**(FNV-1a).
///
/// 예전 id는 `Object.hash`·`String.hashCode`였는데, 이 값은 실행 환경이
/// 달라지면 같다는 보장이 없다. 수집기(서버)와 앱이 같은 글을 같은 번호로
/// 봐야 "이미 알린 글" 기록이 맞으므로 직접 계산한다. 순수 함수 — 테스트 대상.
int stableNoticeId(String group, String category, String link) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode('$group|$category|$link')) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

String? _rssTag(String xml, String tag) {
  final open = xml.indexOf('<$tag>');
  if (open < 0) return null;
  final close = xml.indexOf('</$tag>', open);
  if (close < 0) return null;
  var t = xml.substring(open + tag.length + 2, close).trim();
  if (t.startsWith('<![CDATA[') && t.endsWith(']]>')) {
    t = t.substring(9, t.length - 3);
  }
  return t.trim();
}

String _rssUnescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

/// 학교 게시판 RSS를 공지 목록으로. RSS가 아니면(오류 화면 등) null.
/// 본문(description)은 읽지 않는다. 순수 함수 — 테스트 대상.
List<Notice>? parseNoticeRss(
  String xml, {
  required String group,
  required String category,
  DateTime? now,
}) {
  if (!xml.contains('<rss') || !xml.contains('<channel>')) return null;
  final today = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
  final out = <Notice>[];
  for (final m in RegExp(r'<item>([\s\S]*?)</item>').allMatches(xml)) {
    // 제목·링크는 본문보다 앞에 온다. 본문 안에 같은 이름의 태그가 섞여
    // 있어도 헷갈리지 않게 본문 앞까지만 본다.
    final raw = m.group(1)!;
    final cut = raw.indexOf('<description>');
    final head = cut < 0 ? raw : raw.substring(0, cut);
    final title = _rssUnescape(_rssTag(head, 'title') ?? '');
    final link = _rssTag(head, 'link') ?? '';
    if (title.isEmpty || !link.startsWith('http')) continue;
    final date = normalizeNoticeDate(_rssTag(head, 'pubDate') ?? '') ?? '';
    final dept = _rssUnescape(_rssTag(head, 'department') ?? '');
    out.add(
      Notice(
        id: stableNoticeId(group, category, link),
        category: category,
        group: group,
        title: title,
        date: date,
        author: dept.isEmpty ? '학교' : dept,
        link: link,
        isNew: date == today,
      ),
    );
  }
  return out;
}
