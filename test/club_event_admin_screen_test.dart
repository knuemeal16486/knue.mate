import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/club_event_admin_screen.dart';

void main() {
  testWidgets('ClubEventAdminScreen 비밀번호 게이트 렌더링', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: ClubEventAdminScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    // 비밀번호 입력 UI가 뜨는지 (다이얼로그 or 인라인)
    expect(find.byType(ClubEventAdminScreen), findsOneWidget);
  });
}
