import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpMap(WidgetTester tester, Widget home) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues({});
  AdminAuthService.isAdmin.value = false;
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  for (var i = 0; i < 40 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  // 캠퍼스맵 안에 끼우면 상단바가 없어서 "내 조건 찾기"로 갈 길이 없었다.
  testWidgets('캠퍼스맵 안의 [자취방]에서도 내 조건 찾기·지도 안내를 연다', (tester) async {
    await _pumpMap(tester, const HousingScreen(isEmbedded: true, campusMode: true));

    expect(find.text('내 조건 찾기'), findsNothing, reason: '캠퍼스 모드에선 자취방 조건을 숨긴다');
    await tester.tap(find.text('자취방'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('내 조건 찾기'), findsOneWidget);

    await tester.ensureVisible(find.text('지도 안내'));
    await tester.tap(find.text('지도 안내'));
    await tester.pumpAndSettle();
    expect(find.text('자취방 지도 안내'), findsOneWidget);
  });
}
