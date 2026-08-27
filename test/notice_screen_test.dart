import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
