import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/notice_collector.dart';
import 'package:knue_mate/notice_feed.dart';
import 'package:knue_mate/notice_model.dart';
import 'package:knue_mate/notice_screen.dart';

void main() {
  setUp(() {
    NoticeFeed.debugReset();
    NoticeFeedSettings.debugSet();
  });

  testWidgets('NoticeScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: NoticeScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('청람공지'), findsOneWidget);
    // initState의 네트워크 조회(및 실패 시 재시도 타이머)를 모두 흘려보내
    // 테스트 종료 시 "Timer is still pending" 오류가 나지 않도록 한다.
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('외부 링크 게시판은 바로 가기를 보여준다', (tester) async {
    // 초등교육과는 학과 공지를 다음 카페에만 올려 크롤링 대상이 아니다.
    // 안내가 없으면 "표시할 공지가 없습니다"만 뜨고 갈 곳을 알 수 없었다.
    SharedPreferences.setMockInitialValues({});
    PreferencesService.favoriteBoards.value = ['초등교육과'];
    await tester.pumpWidget(const MaterialApp(home: NoticeScreen()));
    await tester.pump(const Duration(seconds: 30));

    // '초등교육과'는 "대학/대학원" 큰 탭 소속이라 기본 화면(공지사항 탭)엔
    // 안 보인다. 고정(즐겨찾기)해뒀으니 탭을 넘기면 자동으로 그 학과가
    // 선택되는지까지 같이 확인한다.
    await tester.tap(find.text('대학/대학원'));
    await tester.pumpAndSettle();

    expect(find.text('바로 가기'), findsOneWidget);
    expect(find.text('표시할 공지가 없습니다'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('큰 탭을 바꾸면 하위 탭·게시판 선택이 초기화된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: NoticeScreen()));
    await tester.pump(const Duration(seconds: 30));

    // 공지사항 탭에서 하위 탭 하나를 고른다.
    await tester.tap(find.text('학사안내'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('대학소식'), findsOneWidget);

    // 큰 탭을 넘기면(고정된 학과가 없으니) 학사안내 하위 탭 선택이 풀려서
    // 그 게시판(대학소식 등)은 더 이상 안 보이고, 대신 제1~4대학·대학원이 보인다.
    await tester.tap(find.text('대학/대학원'));
    await tester.pumpAndSettle();
    expect(find.text('제1대학'), findsOneWidget);
    expect(find.text('대학소식'), findsNothing);
  });

  // 수집 파일에는 전체 학과가 들어 있어 "고정한 학과만" 안내가 필요 없다.
  testWidgets('[대학/대학원] 전체: 수집 파일로 받을 땐 범위 안내가 없다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.favoriteBoards.value = [];
    await tester.pumpWidget(const MaterialApp(home: NoticeScreen()));
    await tester.pump(const Duration(seconds: 30));

    await tester.tap(find.text('대학/대학원'));
    await tester.pumpAndSettle();
    expect(find.textContaining('대학이나 학과를 고르면'), findsNothing);
    expect(find.textContaining('고정한 학과만'), findsNothing);
  });

  testWidgets('수집이 3시간 넘게 늦으면 안내를 띄우고, 학교 서버로는 요청하지 않는다', (tester) async {
    final at = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final notice = Notice(
      id: 1,
      category: '학사공지',
      group: 'MAIN',
      title: '수강 정정 안내',
      date: '2026-10-06',
      author: '학사관리과',
      link: 'https://www.knue.ac.kr/x',
    );
    SharedPreferences.setMockInitialValues({
      'notice_feed_index': encodeFeedIndex(at, [
        FeedBoardEntry(group: 'MAIN', category: '학사공지', file: 'b/1.json', fetchedAt: at, ok: true, count: 1, hash: 'h'),
      ]),
      'noticeCache': jsonEncode([notice.toJson()]),
    });
    final requested = <String>[];
    await http.runWithClient(
      () => tester.pumpWidget(const MaterialApp(home: NoticeScreen())),
      () => MockClient((req) async {
        requested.add(req.url.toString());
        return http.Response('down', 503); // 수집 파일도 안 열린다
      }),
    );
    await tester.pump(const Duration(seconds: 30));

    expect(find.text('수강 정정 안내'), findsOneWidget);
    expect(find.textContaining('공지 갱신이 늦어지고 있어요'), findsOneWidget);
    expect(requested, isNotEmpty);
    expect(requested.any((u) => u.contains('knue.ac.kr')), isFalse);
  });

  // 비상 직접 모드: 학과·대학원 27개를 한꺼번에 받지 않는다(정보전산원 요청, 2026-10-02).
  testWidgets('[대학/대학원] 전체(직접 모드): 고정한 학과가 없으면 안내를 띄우고, 안 받은 학과를 실패로 치지 않는다', (tester) async {
    NoticeFeedSettings.debugSet(direct: true);
    SharedPreferences.setMockInitialValues({});
    PreferencesService.favoriteBoards.value = [];
    await tester.pumpWidget(const MaterialApp(home: NoticeScreen()));
    await tester.pump(const Duration(seconds: 30));

    await tester.tap(find.text('대학/대학원'));
    await tester.pumpAndSettle();
    expect(find.textContaining('대학이나 학과를 고르면'), findsOneWidget);
    expect(find.text('일부 게시판을 불러오지 못했습니다'), findsNothing);

    // 대학을 고르면 안내는 사라진다(그 대학의 학과를 받는다).
    await tester.tap(find.text('제4대학'));
    await tester.pump(const Duration(seconds: 30));
    expect(find.textContaining('대학이나 학과를 고르면'), findsNothing);
  });
}
