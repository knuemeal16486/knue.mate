import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:knue_mate/club_events_screen.dart';

void main() {
  testWidgets('ClubEventsScreen 렌더링 스모크', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR');
    await tester.pumpWidget(const MaterialApp(home: ClubEventsScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('동아리 공연·행사'), findsOneWidget);
  });
}
