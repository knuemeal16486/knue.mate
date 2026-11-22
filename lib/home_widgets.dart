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
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bus_timetable_data.dart';
import 'constants.dart' show AppTab, PreferencesService;
import 'notice_feed.dart' show NoticeFeedSettings;
import 'notice_model.dart';
import 'notice_service.dart' show NoticeCache, kDefaultFavoriteBoards;

const kWidgetBusTimetableKey = 'bus_timetable_json';
const kWidgetNoticeRowsKey = 'notice_rows_json';
const kWidgetNoticeBoardsKey = 'notice_boards_json';
const kWidgetNoticeFeedBaseKey = 'notice_feed_base';
const kWidgetNoticeDirectKey = 'notice_feed_direct';

const kIosBusWidgetKind = 'BusWidget';
const kIosNoticeWidgetKind = 'NoticeWidget';
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

/// 게시판마다 최신 글 1개. 게시판끼리는 그 글 날짜가 늦은 것부터(같으면
/// [boards] 순서), 최대 [max]개. 캐시에 없는 게시판은 건너뛴다.
List<NoticeWidgetRow> noticeWidgetRows(
  List<Notice> cache,
  List<String> boards, {
  int max = 8,
}) {
  final latest = <String, Notice>{};
  for (final n in cache) {
    if (!boards.contains(n.category)) continue;
    final cur = latest[n.category];
    if (cur == null || n.date.compareTo(cur.date) > 0) latest[n.category] = n;
  }
  final ordered = boards.where(latest.containsKey).toList();
  // List.sort는 안정 정렬이 아니므로 순서를 직접 비교한다.
  ordered.sort((a, b) {
    final c = latest[b]!.date.compareTo(latest[a]!.date);
    return c != 0 ? c : boards.indexOf(a).compareTo(boards.indexOf(b));
  });
  return ordered
      .take(max)
      .map((b) => NoticeWidgetRow(
            board: b,
            title: latest[b]!.title,
            date: latest[b]!.date,
            link: latest[b]!.link,
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
