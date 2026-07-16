import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/home_screen.dart';

void main() {
  testWidgets('HomeScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomeScreen), findsOneWidget);
    // initState의 네트워크 조회(공지 크롤링 재시도 타이머 포함)를 모두 흘려보내
    // 테스트 종료 시 "Timer is still pending" 오류가 나지 않도록 한다.
    await tester.pump(const Duration(seconds: 30));
  });
}
