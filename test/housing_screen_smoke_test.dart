import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 지도가 화면을 꽉 채우는지 본다. 일반 사용자일 때 개발자 툴바 자리에
  // 위치 없는 SizedBox.shrink가 Stack 자식으로 들어가자 Stack이 폭 0으로
  // 줄어 지도·검색창이 통째로 사라진 적이 있다(관리자 화면에선 멀쩡해서
  // 눈으로 확인할 때 놓쳤다).
  testWidgets('일반 사용자에게도 지도가 화면 폭만큼 보인다', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.isAdmin.value = false;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HousingScreen()));
    // 지도 에셋은 실제 파일 읽기라 가짜 시간 밖에서 기다린다.
    // 컴퓨터가 바쁠 때 지도 에셋 로딩이 2초를 넘겨 가끔 실패했다 — 넉넉히 6초.
    for (var i = 0; i < 60 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }

    final viewer = find.byType(InteractiveViewer);
    expect(viewer, findsOneWidget);
    expect(tester.getSize(viewer).width, 400);
    expect(tester.getSize(find.byType(TextField)).width, greaterThan(200));

    // 이름표용 google_fonts는 테스트에서 에셋이 없어 예외를 남긴다 — 무관.
    tester.takeException();
  });
}
