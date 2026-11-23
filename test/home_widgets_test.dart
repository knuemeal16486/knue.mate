import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/bus_timetable_data.dart';
import 'package:knue_mate/constants.dart' show AppTab;
import 'package:knue_mate/home_widgets.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_service.dart'
    show NoticeCache, kDefaultFavoriteBoards;

Notice _n(String board, String date, String title) => Notice(
      id: title.hashCode,
      category: board,
      group: 'MAIN',
      title: title,
      date: date,
      author: '',
      link: 'https://www.knue.ac.kr/$title',
    );

void main() {
  // 이 표는 Swift(BusWidget.swift)·Kotlin(BusWidgetProvider.kt)에도 주석으로
  // 옮겨 둔다 — 세 구현이 같은 규칙을 따라야 한다.
  group('nextDepartures', () {
    const times = ['06:20', '14:27', '15:35'];

    test('지금 이후 n대', () {
      expect(nextDepartures(times, DateTime(2026, 11, 23, 14, 0), 2),
          ['14:27', '15:35']);
    });

    test('같은 분은 지난 차', () {
      expect(nextDepartures(times, DateTime(2026, 11, 23, 14, 27, 30), 2),
          ['15:35']);
    });

    test('자정 직후', () {
      expect(nextDepartures(times, DateTime(2026, 11, 24, 0, 5), 1), ['06:20']);
    });

    test('막차 이후 빈 목록', () {
      expect(nextDepartures(times, DateTime(2026, 11, 23, 23, 30), 2), isEmpty);
    });
  });

  test('isBusHoliday 토·일', () {
    expect(isBusHoliday(DateTime(2026, 11, 22)), isTrue); // 일
    expect(isBusHoliday(DateTime(2026, 11, 21)), isTrue); // 토
    expect(isBusHoliday(DateTime(2026, 11, 23)), isFalse); // 월
  });

  test('busWidgetTimetableJson 노선·출처', () {
    final m = jsonDecode(busWidgetTimetableJson()) as Map<String, dynamic>;
    expect(m['v'], 1);
    final routes = (m['routes'] as List).cast<Map<String, dynamic>>();
    expect(routes.map((r) => r['label']),
        ['513', '514', '518', '913 평동행', '913 미호행']);
    expect(routes[0]['weekday'][0], '06:20');
    expect(routes[0]['weekday'],
        BusTimetableData.schedules['513']!['outgoing']!['weekday']);
    expect(routes[0]['holiday'],
        BusTimetableData.schedules['513']!['outgoing']!['holiday']);
    final p = BusTimetableData.route913MihoToPyeongdong
        .map((t) => t.knueTime)
        .toList();
    expect(routes[3]['weekday'], p);
    expect(routes[3]['holiday'], p);
    expect(
        routes[4]['weekday'],
        BusTimetableData.route913PyeongdongToMiho
            .map((t) => t.knueTime)
            .toList());
  });

  test('noticeWidgetBoards 기본값', () {
    expect(noticeWidgetBoards(null), ['대학소식', '학사공지']);
    expect(noticeWidgetBoards([]), kDefaultFavoriteBoards.toList());
    expect(noticeWidgetBoards(['학사공지']), ['학사공지']);
  });

  group('noticeWidgetRows', () {
    final cache = [
      _n('학사공지', '2026-11-19', '옛글'),
      _n('학사공지', '2026-11-20', '새글'),
      _n('장학금', '2026-11-21', '장학'),
      _n('대학소식', '2026-11-22', '즐겨찾기아님'),
    ];
    const boards = ['학사공지', '장학금', '없는게시판'];

    test('게시판당 최신 1개 먼저(날짜 늦은 게시판부터), 없는 게시판은 건너뜀', () {
      final rows = noticeWidgetRows(cache, boards);
      expect(rows.map((r) => '${r.board} ${r.date}'),
          ['장학금 2026-11-21', '학사공지 2026-11-20', '학사공지 2026-11-19']);
      expect(rows[1].title, '새글');
      expect(rows[1].toJson(), {
        'b': '학사공지',
        't': '새글',
        'd': '2026-11-20',
        'l': 'https://www.knue.ac.kr/새글',
      });
    });

    test('max', () {
      expect(noticeWidgetRows(cache, boards, max: 1).map((r) => r.board),
          ['장학금']);
    });

    test('자리가 남으면 대상 게시판의 다음 글로 채운다(최신순)', () {
      final rows = noticeWidgetRows(
          [
            _n('학사공지', '2026-11-18', '학사3'),
            _n('학사공지', '2026-11-20', '학사1'),
            _n('장학금', '2026-11-21', '장학1'),
            _n('학사공지', '2026-11-19', '학사2'),
            _n('장학금', '2026-11-17', '장학2'),
            _n('대학소식', '2026-11-22', '대상아님'),
          ],
          boards,
          max: 4);
      // 게시판마다 최신 1개가 먼저, 남은 자리는 나머지 글 중 최신순.
      expect(rows.map((r) => r.title), ['장학1', '학사1', '학사2', '학사3']);
    });

    test('같은 글(링크)이 캐시에 두 번 있어도 한 번만', () {
      final rows = noticeWidgetRows(
          [_n('학사공지', '2026-11-20', 'a'), _n('학사공지', '2026-11-20', 'a')],
          boards);
      expect(rows.map((r) => r.title), ['a']);
    });

    test('날짜가 같으면 boards 순서', () {
      final rows = noticeWidgetRows(
          [_n('장학금', '2026-11-20', 'a'), _n('학사공지', '2026-11-20', 'b')],
          boards);
      expect(rows.map((r) => r.board), ['학사공지', '장학금']);
    });
  });

  test('widgetLinkAllowed', () {
    expect(widgetLinkAllowed('https://www.knue.ac.kr/www/x'), isTrue);
    expect(widgetLinkAllowed('https://lib.knue.ac.kr/a'), isTrue);
    expect(widgetLinkAllowed('https://knue.ac.kr/a'), isTrue);
    expect(widgetLinkAllowed('http://www.knue.ac.kr'), isFalse);
    expect(widgetLinkAllowed('https://evil.com/knue.ac.kr'), isFalse);
    expect(widgetLinkAllowed('https://knue.ac.kr.evil.com'), isFalse);
    expect(widgetLinkAllowed('https://evilknue.ac.kr'), isFalse);
    expect(widgetLinkAllowed(''), isFalse);
  });

  group('noticeLinkFromWidgetUri', () {
    const link = 'https://www.knue.ac.kr/www/a?b=1&c=2';
    test('u의 링크를 꺼낸다', () {
      expect(
          noticeLinkFromWidgetUri(Uri.parse(
              'knuemate://notice?u=${Uri.encodeComponent(link)}')),
          link);
    });
    test('학교 밖 주소는 null', () {
      expect(
          noticeLinkFromWidgetUri(Uri.parse(
              'knuemate://notice?u=${Uri.encodeComponent('https://evil.com')}')),
          isNull);
    });
    test('u 없음·다른 주소는 null', () {
      expect(noticeLinkFromWidgetUri(Uri.parse('knuemate://notice')), isNull);
      expect(noticeLinkFromWidgetUri(null), isNull);
      expect(
          noticeLinkFromWidgetUri(Uri.parse(
              'knuemate://bus?u=${Uri.encodeComponent(link)}')),
          isNull);
    });
  });

  test('iOS 위젯 URL(homeWidget 쿼리 포함)도 같이 읽는다', () {
    const link = 'https://www.knue.ac.kr/www/a?b=1';
    expect(
        noticeLinkFromWidgetUri(Uri.parse(
            'knuemate://notice?homeWidget&u=${Uri.encodeComponent(link)}')),
        link);
    expect(widgetTabForUri(Uri.parse('knuemate://bus?homeWidget')), AppTab.bus);
  });

  test('widgetTabForUri', () {
    expect(widgetTabForUri(Uri.parse('knuemate://notice')), AppTab.home);
    expect(widgetTabForUri(Uri.parse('knuemate://meal')), AppTab.meal);
    expect(widgetTabForUri(Uri.parse('knuemate://bus')), AppTab.bus);
    expect(widgetTabForUri(Uri.parse('https://bus')), isNull);
    expect(widgetTabForUri(null), isNull);
  });

  // 백그라운드 공지 작업은 저장 직후 끝날 수 있다 — 위젯에 넣기를 마친 뒤에
  // 돌아와야 Android 공지 위젯이 낡지 않는다.
  test('NoticeCache.save는 공지 위젯에 넣기를 마치고 돌아온다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'fav_boards': ['학사공지']});
    final saved = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'saveWidgetData') {
        saved.add((call.arguments as Map)['id'] as String);
      }
      return true;
    });
    await NoticeCache.save([_n('학사공지', '2026-11-20', '새글')]);
    expect(saved, contains(kWidgetNoticeRowsKey));
  });
}
