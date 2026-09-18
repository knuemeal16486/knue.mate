import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/housing_admin_screen.dart';

void main() {
  testWidgets('HousingAdminScreen 비밀번호 게이트 렌더링', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HousingAdminScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HousingAdminScreen), findsOneWidget);
  });
}
