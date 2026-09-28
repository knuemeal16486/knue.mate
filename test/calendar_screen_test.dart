import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/calendar_screen.dart';

void main() {
  testWidgets('CalendarScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: CalendarScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('청람일정'), findsOneWidget);
    // initState의 학사일정 조회(앱 버전 읽기 제한 시간 2초 포함)를 흘려보내
    // "Timer is still pending" 오류가 나지 않게 한다.
    await tester.pump(const Duration(seconds: 15));
  });
}
