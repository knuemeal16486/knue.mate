import 'dart:convert';

import 'notice_boards.dart';
import 'notice_model.dart';
import 'notice_parse.dart';

// ── 공지 중앙 수집 ─────────────────────────────────────────────────────
//
// 예전엔 앱을 쓰는 기기마다 학교 게시판을 직접 받았다(하루 약 8만 3천 건,
// 2026-09 정보전산원 측정). 이제 수집기 한 곳(GitHub Actions,
// tool/collect_notices.dart)이 받아 제목·링크·날짜·부서만 추린 파일을 만들고,
// 앱은 그 파일만 받는다. 학교로 가는 요청은 이용자 수와 상관없이 수집기의
// 주기로만 정해진다.
//
// 이 파일은 Flutter 없이 돈다 — 수집기와 앱이 같이 쓴다.

/// 수집기가 학교 서버에 밝히는 이름. 앱(`KNUE-Mate/<버전>`)과 구분되게 따로 둔다.
/// 정보전산원이 로그에서 이 값으로 수집기 요청을 가려낸다.
const String kCollectorUserAgent =
    'KNUE-Mate-Collector/1.0 (+knuemeal16486@gmail.com)';

/// 그룹별 수집 간격(분). **학교 서버에 가는 양은 이 값으로만 정해진다.**
///
/// 전부 30분이면 knue.ac.kr 게시판 40개 × 하루 48회 = 1,920건, 약 1.5GB다
/// (2026-10-02 실측: 한 회차 30.8MB. RSS가 본문까지 실어 게시판당 56KB~2.5MB).
/// 예전 하루 8만 3천 건·7.5GB보다 요청은 약 98%, 전송량은 약 80% 적다.
/// 한 회차 중 MAIN·LIFE가 약 8MB, DEPT·GRAD가 약 22MB라서, 전송량을 더 줄여야
/// 하면 학과·대학원 쪽 숫자만 키우면 된다(예: 'DEPT': 60 → 하루 약 0.9GB).
/// 수집기는 30분마다 돌므로 30의 배수로 적는다.
const Map<String, int> kCollectIntervalMinutes = {
  'MAIN': 30,
  'LIFE': 30,
  'DEPT': 30,
  'GRAD': 30,
  'ANNEX': 30,
};

/// 같은 서버로 연달아 보낼 때 사이에 쉬는 시간. 한 서버에는 한 번에 하나씩만 보낸다.
const Duration kCollectRequestGap = Duration(milliseconds: 1500);

/// 한 서버에서 이만큼 연달아 실패하면 그 회차엔 그 서버를 그만 두드린다.
const int kCollectMaxFailuresInRow = 3;

/// 수집 파일 형식 번호. 형식을 바꾸면 올린다(앱이 모르는 번호면 읽지 않는다).
const int kFeedVersion = 1;

/// FNV-1a 32비트를 16진수 8자리로. 실행 환경이 달라도 같은 값이다.
String fnvHex(String s) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// 수집 대상 게시판 하나.
class CollectBoard {
  final String group;
  final String category;

  /// 앱이 쓰던 목록 주소(notice_boards.dart). 이 값이 게시판의 신분이다.
  final String listUrl;

  const CollectBoard(this.group, this.category, this.listUrl);

  /// 학교 대표 서버 게시판이면 RSS 주소, 아니면 null.
  String? get rssUrl => noticeRssUrl(listUrl);

  /// 실제로 받을 주소. 학교가 권한 대로 RSS가 있으면 RSS를 받는다.
  String get fetchUrl => rssUrl ?? listUrl;

  String get host => Uri.parse(fetchUrl).host;

  /// 수집 파일 이름. 주소로 정해지므로 게시판 이름이 겹쳐도('교육대학원'이
  /// 두 개다) 섞이지 않는다.
  String get fileId => fnvHex(listUrl);

  Duration get interval =>
      Duration(minutes: kCollectIntervalMinutes[group] ?? 30);
}

/// 수집 대상 전부. 'LINK:' 게시판(외부 카페 등)은 받지 않는다. 순수 함수 — 테스트 대상.
List<CollectBoard> collectBoards([
  Map<String, Map<String, String>> groups = kNoticeBoardGroups,
]) => [
  for (final g in groups.entries)
    for (final b in g.value.entries)
      if (!b.value.startsWith('LINK:')) CollectBoard(g.key, b.key, b.value),
];

/// 이번 회차에 받을 차례인지. 순수 함수 — 테스트 대상.
///
/// GitHub의 예약 실행은 정시에 안 돈다(몇 분씩 늦거나 이르다). 30분 간격으로
/// 잡았는데 29분 만에 돌았다고 건너뛰면 실제 간격이 60분이 되므로 [slack]만큼
/// 봐준다.
bool isBoardDue(
  DateTime? lastFetchedAt,
  Duration interval,
  DateTime now, {
  Duration slack = const Duration(minutes: 8),
}) {
  if (lastFetchedAt == null || lastFetchedAt.isAfter(now)) return true;
  return now.difference(lastFetchedAt) >= interval - slack;
}

/// 응답을 공지 목록으로. 읽을 수 없으면 null(실패로 친다). 순수 함수 — 테스트 대상.
List<Notice>? parseCollected(CollectBoard b, String body) {
  if (b.rssUrl != null) {
    return parseNoticeRss(body, group: b.group, category: b.category);
  }
  if (b.listUrl.contains('pyxis-api')) {
    try {
      return parsePyxisNotices(body, group: b.group, category: b.category);
    } catch (_) {
      return null;
    }
  }
  return parseNoticeHtml({
    'html': body,
    'group': b.group,
    'category': b.category,
    'url': b.listUrl,
  });
}

/// 수집 파일에 싣는 항목. 본문은 싣지 않는다 — 제목·링크·날짜·작성 부서만.
List<Map<String, String>> encodeFeedItems(List<Notice> notices) => [
  for (final n in notices)
    {'t': n.title, 'l': n.link, 'd': n.date, 'a': n.author},
];

/// 수집 파일의 항목을 공지로. id는 **읽는 쪽에서** 계산한다([stableNoticeId]) —
/// 파일에 싣지 않아도 어느 기기에서나 같은 번호가 나온다. 순수 함수 — 테스트 대상.
List<Notice> decodeFeedItems(
  Object? items, {
  required String group,
  required String category,
  required String today,
}) {
  if (items is! List) return const [];
  final out = <Notice>[];
  for (final e in items) {
    if (e is! Map) continue;
    final title = e['t'], link = e['l'];
    if (title is! String || link is! String || title.isEmpty) continue;
    final date = e['d'] is String ? e['d'] as String : '';
    out.add(
      Notice(
        id: stableNoticeId(group, category, link),
        category: category,
        group: group,
        title: title,
        date: date,
        author: e['a'] is String ? e['a'] as String : '',
        link: link,
        isNew: date == today,
      ),
    );
  }
  return out;
}

/// 수집 목록(index.json)의 게시판 한 줄.
class FeedBoardEntry {
  final String group;
  final String category;
  final String file;

  /// 마지막으로 **성공한** 수집 시각(UTC). 앱은 이걸로 "갱신 지연"을 판단한다.
  final DateTime? fetchedAt;

  /// 마지막 시도가 성공했는지.
  final bool ok;
  final int count;

  /// 항목 내용의 지문. 같으면 앱이 그 게시판 파일을 다시 받지 않는다.
  final String hash;

  const FeedBoardEntry({
    required this.group,
    required this.category,
    required this.file,
    required this.fetchedAt,
    required this.ok,
    required this.count,
    required this.hash,
  });

  Map<String, dynamic> toJson() => {
    'group': group,
    'category': category,
    'file': file,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'ok': ok,
    'count': count,
    'hash': hash,
  };

  static FeedBoardEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final group = j['group'], category = j['category'], file = j['file'];
    if (group is! String || category is! String || file is! String) return null;
    return FeedBoardEntry(
      group: group,
      category: category,
      file: file,
      fetchedAt: j['fetchedAt'] is String
          ? DateTime.tryParse(j['fetchedAt'] as String)
          : null,
      ok: j['ok'] == true,
      count: j['count'] is int ? j['count'] as int : 0,
      hash: j['hash'] is String ? j['hash'] as String : '',
    );
  }
}

/// 수집 목록(index.json). 읽을 수 없거나 모르는 형식이면 null. 순수 함수 — 테스트 대상.
({DateTime? generatedAt, List<FeedBoardEntry> boards})? parseFeedIndex(
  String body,
) {
  try {
    final j = jsonDecode(body);
    if (j is! Map || j['version'] != kFeedVersion || j['boards'] is! List) {
      return null;
    }
    return (
      generatedAt: j['generatedAt'] is String
          ? DateTime.tryParse(j['generatedAt'] as String)
          : null,
      boards: [
        for (final b in j['boards'] as List)
          if (FeedBoardEntry.fromJson(b) case final e?) e,
      ],
    );
  } catch (_) {
    return null;
  }
}

String encodeFeedIndex(DateTime generatedAt, List<FeedBoardEntry> boards) =>
    jsonEncode({
      'version': kFeedVersion,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'collector': kCollectorUserAgent,
      'boards': [for (final b in boards) b.toJson()],
    });
