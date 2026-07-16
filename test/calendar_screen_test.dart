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
  });
}
