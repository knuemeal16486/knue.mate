/// 공지·버스 홈 위젯의 규칙과 위젯 저장소 연결.
///
/// 규칙(다음 차 고르기, 게시판별 최신 글, 링크 허용)은 여기 순수 함수로 두고
/// 테스트한다(test/home_widgets_test.dart). 위젯 쪽(Swift
/// `ios/MealWidget/BusWidget.swift`·`NoticeWidget.swift`, Kotlin
/// `BusWidgetProvider.kt`·`NoticeWidgetProvider.kt`)은 같은 규칙을 옮겨
/// 쓴다 — 여기를 바꾸면 거기도 바꾼다.
///
/// 위젯 저장소 키 (Swift·Kotlin 문자열과 같아야 한다 —
/// test/native_id_consistency_test.dart가 확인):
///
/// | 키 | 값 |
/// |---|---|
/// | `bus_timetable_json` | `busWidgetTimetableJson()` |
/// | `notice_rows_json` | `noticeWidgetRows` → `[{b,t,d,l}]` |
/// | `notice_boards_json` | 대상 게시판 이름 목록 |
/// | `notice_feed_base` | 수집 파일 주소(`NoticeFeed.base`) |
/// | `notice_feed_direct` | 비상 직접 모드면 true(iOS 위젯이 받지 않는다) |
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bus_timetable_data.dart';
import 'constants.dart' show AppTab, PreferencesService, kIosMealWidgetKind;
import 'notice_feed.dart' show NoticeFeedSettings;
import 'notice_model.dart';
import 'notice_service.dart' show NoticeCache, kDefaultFavoriteBoards;

const kWidgetBusTimetableKey = 'bus_timetable_json';
const kWidgetNoticeRowsKey = 'notice_rows_json';
const kWidgetNoticeBoardsKey = 'notice_boards_json';
const kWidgetNoticeFeedBaseKey = 'notice_feed_base';
const kWidgetNoticeDirectKey = 'notice_feed_direct';

/// 위젯 강조색(앱 테마 색). "#RRGGBB" 문자열 — Android·iOS 모두 문자열로 읽는다.
const kWidgetAccentLightKey = 'accent_light';
const kWidgetAccentDarkKey = 'accent_dark';

const kIosBusWidgetKind = 'BusWidget';
const kIosNoticeWidgetKind = 'NoticeWidget';
const kAndroidMealWidget = 'com.knue.knuemate.MealWidgetProvider';
const kAndroidBusWidget = 'com.knue.knuemate.BusWidgetProvider';
const kAndroidNoticeWidget = 'com.knue.knuemate.NoticeWidgetProvider';

int? _minutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// "HH:mm" 시각 중 오늘 지금 이후에 떠나는 차 앞에서 [n]대.
///
/// 지금과 같은 분에 떠나는 차는 방금 떠난 차로 본다(`출발 분 > 지금 분`).
/// 시간표는 하루치라 자정을 넘기면 다시 첫 차부터다.
///
/// | 지금 | 시각표 06:20·14:27·15:35 | n | 결과 |
/// |---|---|---|---|
/// | 14:00 | | 2 | 14:27, 15:35 |
/// | 14:27:30 | | 2 | 15:35 |
/// | 00:05 | | 1 | 06:20 |
/// | 23:30 | | 2 | (없음) |
List<String> nextDepartures(List<String> times, DateTime now, int n) {
  final nowMin = now.hour * 60 + now.minute;
  final out = <String>[];
  for (final t in times) {
    final m = _minutes(t);
    if (m != null && m > nowMin) {
      out.add(t);
      if (out.length >= n) break;
    }
  }
  return out;
}

/// 앱 버스 화면과 같다: 토·일이면 주말 시간표(공휴일은 구분하지 않는다).
bool isBusHoliday(DateTime now) =>
    now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

/// 위젯에 넣는 시간표 — 학교에서 나가는 차만.
String busWidgetTimetableJson() {
  final routes = <Map<String, dynamic>>[];
  for (final no in const ['513', '514', '518']) {
    final out = BusTimetableData.schedules[no]?['outgoing'];
    if (out == null) continue;
    routes.add({
      'label': no,
      'sub': '교원문화관',
      'weekday': out['weekday'] ?? const <String>[],
      'holiday': out['holiday'] ?? const <String>[],
    });
  }
  void add913(String label, List<Route913Trip> trips) {
    final times = trips.map((t) => t.knueTime).toList();
    routes.add({
      'label': label,
      'sub': '교원대 경유',
      'weekday': times,
      'holiday': times,
    });
  }

  add913('913 평동행', BusTimetableData.route913MihoToPyeongdong);
  add913('913 미호행', BusTimetableData.route913PyeongdongToMiho);
  return jsonEncode({'v': 1, 'routes': routes});
}

/// 공지 위젯이 볼 게시판. 저장값이 없으면 PreferencesService.loadSettings의
/// 기본값, 비었으면 앱 홈 공지 카드와 같은 기본 4개.
List<String> noticeWidgetBoards(List<String>? stored) {
  if (stored == null) return const ['대학소식', '학사공지'];
  if (stored.isEmpty) return kDefaultFavoriteBoards.toList();
  return stored;
}

class NoticeWidgetRow {
  final String board;
  final String title;
  final String date;
  final String link;

  const NoticeWidgetRow({
    required this.board,
    required this.title,
    required this.date,
    required this.link,
  });

  Map<String, String> toJson() => {'b': board, 't': title, 'd': date, 'l': link};
}

/// 위젯에 넣는 공지 최대 줄 수. 위젯은 높이에 맞는 만큼만 보여 준다.
/// Swift kNoticeWidgetMaxRows·Kotlin ROW_IDS 개수와 같게.
const kNoticeWidgetMaxRows = 10;

/// 공지 위젯 게시판 이름 색 개수. Swift·Kotlin의 색 목록 길이와 같게.
const kNoticeBoardColorCount = 8;

/// 게시판 이름 색 번호. 대상 게시판([boards], 즐겨찾기 순서)이면 그 순서대로라
/// 8개까지 서로 다른 색이다. 대상에 없으면 이름의 UTF-16 코드 합으로 고정한다.
/// Swift noticeBoardColorIndex·Kotlin boardColorIndex와 같은 규칙.
int noticeBoardColorIndex(String board, List<String> boards) {
  final i = boards.indexOf(board);
  if (i >= 0) return i % kNoticeBoardColorCount;
  return board.codeUnits.fold<int>(0, (a, c) => a + c) % kNoticeBoardColorCount;
}

/// 게시판마다 최신 글 1개를 먼저 둔다. 게시판끼리는 그 글 날짜가 늦은 것부터
/// (같으면 [boards] 순서). 최대 [max]개이고, 즐겨찾기가 적어 자리가 남으면
/// 대상 게시판의 나머지 글을 최신순으로 채운다(같으면 [boards] 순서·캐시 순서).
/// 같은 링크는 한 번만. 캐시에 없는 게시판은 건너뛴다.
List<NoticeWidgetRow> noticeWidgetRows(
  List<Notice> cache,
  List<String> boards, {
  int max = kNoticeWidgetMaxRows,
}) {
  final seen = <String>{};
  final posts = <Notice>[];
  for (final n in cache) {
    if (!boards.contains(n.category)) continue;
    if (!seen.add('${n.category}|${n.link}|${n.title}')) continue;
    posts.add(n);
  }
  // 날짜 내림차순 → boards 순서 → 캐시 순서. List.sort는 안정 정렬이 아니라
  // 원래 위치를 직접 비교한다.
  final idx = List.generate(posts.length, (i) => i)
    ..sort((i, j) {
      final a = posts[i], b = posts[j];
      final c = b.date.compareTo(a.date);
      if (c != 0) return c;
      final bo =
          boards.indexOf(a.category).compareTo(boards.indexOf(b.category));
      return bo != 0 ? bo : i.compareTo(j);
    });
  final firsts = <Notice>[];
  final rest = <Notice>[];
  final used = <String>{};
  for (final n in idx.map((i) => posts[i])) {
    (used.add(n.category) ? firsts : rest).add(n);
  }
  return [...firsts, ...rest]
      .take(max)
      .map((n) => NoticeWidgetRow(
            board: n.category,
            title: n.title,
            date: n.date,
            link: n.link,
          ))
      .toList();
}

/// 위젯에서 여는 링크는 https이면서 knue.ac.kr 계열일 때만.
bool widgetLinkAllowed(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'knue.ac.kr' || host.endsWith('.knue.ac.kr');
}

/// 위젯 URI(knuemate://meal 등)를 보고 갈 탭을 정한다.
/// 모르는 주소면 null — 그냥 평소 시작 탭으로 연다.
AppTab? widgetTabForUri(Uri? uri) {
  if (uri == null) return null;
  if (uri.scheme != 'knuemate') return null;
  switch (uri.host) {
    case 'meal':
      return AppTab.meal;
    case 'bus':
      return AppTab.bus;
    case 'notice':
      // 공지는 홈 카드에 있다.
      return AppTab.home;
    default:
      return null;
  }
}

/// iOS 공지 위젯 줄은 `knuemate://notice?u=<링크>`로 앱을 연다(위젯 Link는
/// 앱으로만 URL을 넘긴다). 학교 링크일 때만 꺼내 준다.
String? noticeLinkFromWidgetUri(Uri? uri) {
  if (uri == null || uri.scheme != 'knuemate' || uri.host != 'notice') {
    return null;
  }
  final link = uri.queryParameters['u'];
  if (link == null || !widgetLinkAllowed(link)) return null;
  return link;
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// 앱 테마 색을 위젯 강조색(라이트·다크 배경용)으로. 흰 배경에서 너무 밝은 색
/// (노랑 등)은 어둡게, 검은 배경에서 너무 어두운 색(남색 등)은 밝게 — 글씨가
/// 읽히게 한다. 보통 색은 그대로.
({String light, String dark}) widgetAccentHex(Color c) {
  const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
  var light = c, dark = c;
  for (var t = 0.1; light.computeLuminance() > 0.4 && t <= 1; t += 0.1) {
    light = Color.lerp(c, black, t)!;
  }
  for (var t = 0.1; dark.computeLuminance() < 0.15 && t <= 1; t += 0.1) {
    dark = Color.lerp(c, white, t)!;
  }
  return (light: _hex(light), dark: _hex(dark));
}

const _kAppGroupId = 'group.knue.meal';

/// 시간표를 위젯 저장소에 넣는다. 같은 값이면 건너뛴다.
Future<void> pushBusWidgetTimetable() async {
  try {
    await HomeWidget.setAppGroupId(_kAppGroupId);
    final json = busWidgetTimetableJson();
    final cur = await HomeWidget.getWidgetData<String>(kWidgetBusTimetableKey);
    if (cur == json) return;
    await HomeWidget.saveWidgetData<String>(kWidgetBusTimetableKey, json);
    await HomeWidget.updateWidget(
      iOSName: kIosBusWidgetKind,
      qualifiedAndroidName: kAndroidBusWidget,
    );
  } catch (e) {
    debugPrint('버스 위젯 갱신 실패: $e');
  }
}

/// 공지 캐시에서 게시판별 최신 글을 골라 위젯 저장소에 넣는다.
/// 백그라운드 작업에서도 부른다 — 화면(UI)에 기대지 않는다.
Future<void> pushNoticeWidget() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final boards = noticeWidgetBoards(
      prefs.getStringList(PreferencesService.keyFavBoards),
    );
    final cache = await NoticeCache.load() ?? const <Notice>[];
    final rows = noticeWidgetRows(cache, boards);
    await NoticeFeedSettings.loadCached();
    await HomeWidget.setAppGroupId(_kAppGroupId);
    await HomeWidget.saveWidgetData<String>(
      kWidgetNoticeRowsKey,
      jsonEncode(rows.map((r) => r.toJson()).toList()),
    );
    await HomeWidget.saveWidgetData<String>(
      kWidgetNoticeBoardsKey,
      jsonEncode(boards),
    );
    await HomeWidget.saveWidgetData<String>(
      kWidgetNoticeFeedBaseKey,
      NoticeFeedSettings.base,
    );
    await HomeWidget.saveWidgetData<bool>(
      kWidgetNoticeDirectKey,
      NoticeFeedSettings.direct,
    );
    await HomeWidget.updateWidget(
      iOSName: kIosNoticeWidgetKind,
      qualifiedAndroidName: kAndroidNoticeWidget,
    );
  } catch (e) {
    debugPrint('공지 위젯 갱신 실패: $e');
  }
}

/// 앱 테마 색이 바뀌면 위젯 강조색(식당 끼니·"학교 출발 버스"·"공지" 머리글)도
/// 바꾼다. 같은 값이면 건너뛴다.
Future<void> pushWidgetAccent(Color color) async {
  try {
    final a = widgetAccentHex(color);
    await HomeWidget.setAppGroupId(_kAppGroupId);
    final cur = await HomeWidget.getWidgetData<String>(kWidgetAccentLightKey);
    final curDark = await HomeWidget.getWidgetData<String>(kWidgetAccentDarkKey);
    if (cur == a.light && curDark == a.dark) return;
    await HomeWidget.saveWidgetData<String>(kWidgetAccentLightKey, a.light);
    await HomeWidget.saveWidgetData<String>(kWidgetAccentDarkKey, a.dark);
    await HomeWidget.updateWidget(
      iOSName: kIosMealWidgetKind,
      qualifiedAndroidName: kAndroidMealWidget,
    );
    await redrawBusNoticeWidgets();
  } catch (e) {
    debugPrint('위젯 강조색 갱신 실패: $e');
  }
}

/// 테마·투명도가 바뀌었을 때 버스·공지 위젯도 다시 그린다.
Future<void> redrawBusNoticeWidgets() async {
  try {
    await HomeWidget.updateWidget(
      iOSName: kIosBusWidgetKind,
      qualifiedAndroidName: kAndroidBusWidget,
    );
    await HomeWidget.updateWidget(
      iOSName: kIosNoticeWidgetKind,
      qualifiedAndroidName: kAndroidNoticeWidget,
    );
  } catch (e) {
    debugPrint('버스·공지 위젯 다시 그리기 실패: $e');
  }
}
