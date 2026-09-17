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
    PreferencesService.noticeAlertMode.value = NoticeAlertMode.instant;
    PreferencesService.noticeAlertHours.value = [9, 18];
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

  testWidgets('기본값은 즉시 모드라 시각 편집 UI가 안 보인다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    expect(find.text("올라오는 즉시"), findsOneWidget);
    expect(find.text("하루 중 지정한 시각에 모아서"), findsOneWidget);
    expect(find.text("시각 추가"), findsNothing);
  });

  testWidgets('"하루 중 지정한 시각에 모아서"를 고르면 시각 칩이 보인다', (tester) async {
    PreferencesService.noticeKeywords.value = []; // 키워드 칩과 안 섞이게
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    await tester.tap(find.text("하루 중 지정한 시각에 모아서"));
    await tester.pump();
    await tester.pump(); // saveNoticeAlertMode의 await 완료까지

    expect(
      PreferencesService.noticeAlertMode.value,
      NoticeAlertMode.scheduled,
    );
    expect(find.text("시각 추가"), findsOneWidget);
    // 기본 시각(9, 18시)이 칩으로 보이는지 — 로케일에 따라 표기가 다를 수
    // 있어 정확한 문자열 대신 칩 개수로 확인.
    expect(find.byType(Chip), findsNWidgets(2));
  });

  testWidgets('시각이 1개뿐이면 삭제 버튼이 없다(0개 방지)', (tester) async {
    PreferencesService.noticeAlertMode.value = NoticeAlertMode.scheduled;
    PreferencesService.noticeAlertHours.value = [9];
    PreferencesService.noticeKeywords.value = []; // 키워드 칩과 안 섞이게
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.onDeleted, isNull);
  });

  testWidgets('시각 두 개를 거의 동시에 삭제해도 경쟁 없이 둘 다 반영된다', (tester) async {
    PreferencesService.noticeAlertMode.value = NoticeAlertMode.scheduled;
    PreferencesService.noticeAlertHours.value = [9, 12, 18];
    PreferencesService.noticeKeywords.value = []; // 키워드 칩과 안 섞이게
    await tester.pumpWidget(
      const MaterialApp(home: NoticeAlertSettingsScreen()),
    );
    await tester.pump();

    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect(chips, hasLength(3));

    // pump 없이 두 삭제 콜백을 연달아 호출 — 실제 화면에서 두 칩의 삭제
    // 버튼을 빠르게 연속으로 누른 상황과 같다. 큐로 직렬화되지 않으면
    // 나중에 끝난 저장이 먼저 저장을 덮어써서 하나가 유실된다.
    chips[0].onDeleted!();
    chips[1].onDeleted!();
    await tester.pump();
    await tester.pump();
    await tester.pump(); // 체인으로 순서대로 처리되는 두 저장이 끝날 때까지

    expect(PreferencesService.noticeAlertHours.value, hasLength(1));
  });
}
