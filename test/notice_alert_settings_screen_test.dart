import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/constants.dart';
import 'package:knue_mate/notice_alert_settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PreferencesService.noticeAlarmOn.value = true;
    PreferencesService.noticeKeywords.value = ['장학', '수강', '졸업'];
  });

  testWidgets('렌더링되고 알림 스위치가 켜진 상태로 시작한다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    expect(find.text("공지 알림"), findsOneWidget);
    expect(find.text("새 공지 알림 받기"), findsOneWidget);
    final switchWidget = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switchWidget.value, isTrue);
  });

  testWidgets('스위치를 끄면 PreferencesService.noticeAlarmOn도 꺼진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.pump(); // saveNoticeAlarm의 await 완료까지

    expect(PreferencesService.noticeAlarmOn.value, isFalse);
  });

  testWidgets('키워드가 있으면 칩으로, 없으면 경고 문구로 보여준다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();
    expect(find.text('장학'), findsOneWidget);

    PreferencesService.noticeKeywords.value = [];
    await tester.pump();
    expect(find.textContaining("등록된 키워드 없음"), findsOneWidget);
  });
}
