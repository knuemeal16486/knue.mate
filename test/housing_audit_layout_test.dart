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
  // 예전엔 그림자 시각 막대가 오른쪽 지도 도구의 아래쪽 버튼(축소·중심·더보기)을 덮었다.
  testWidgets('폰: 그림자 막대를 켜도 지도 도구와 겹치지 않는다', (tester) async {
    await _pumpMap(tester, const HousingScreen());

    await tester.tap(find.byTooltip('지도 도구 더보기'));
    await tester.pump();
    await tester.tap(find.byTooltip('시간별 그림자 보기'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));

    final hud = tester.getRect(find.ancestor(of: find.byTooltip('확대'), matching: find.byType(AnimatedPositioned)));
    final bar = tester.getRect(find.ancestor(of: find.byType(Slider), matching: find.byType(Positioned)).first);
    expect(hud.overlaps(bar), isFalse, reason: 'hud=$hud bar=$bar');
    // 막대 높이를 넉넉히 잡아 뒀는지(위치 계산에 쓰는 값 92).
    expect(bar.height, lessThanOrEqualTo(92));
  });
}
