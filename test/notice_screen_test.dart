import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/notice_screen.dart';

void main() {
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

    await tester.tap(find.widgetWithText(GestureDetector, '초등교육과').first);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('바로 가기'), findsOneWidget);
    expect(find.text('표시할 공지가 없습니다'), findsNothing);
    await tester.pump(const Duration(seconds: 30));
  });
}
