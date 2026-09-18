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
}
