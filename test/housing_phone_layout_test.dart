import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 폰 세로에선 지도 도구 10개가 오른쪽을 반쯤 가렸다. 폰에선 접고, 태블릿에선 다 보인다.
  // (한 테스트 안에서 화면 크기만 바꾼다 — 지도 에셋 로딩이 테스트마다 새로 돌지 않는다.)
  testWidgets('폰에선 지도 도구·편집 도구를 접고 펼쳐 쓴다, 태블릿은 다 보인다', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.isAdmin.value = false;
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HousingScreen()));
    for (var i = 0; i < 40 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    // 폰: 나침반·확대·축소·중심 + 더보기만
    expect(find.byTooltip('확대'), findsOneWidget);
    expect(find.byTooltip('지도 도구 더보기'), findsOneWidget);
    expect(find.byTooltip('원룸 시세 뱃지 켜기'), findsNothing);
    expect(find.byTooltip('위에서 보기'), findsNothing);

    await tester.tap(find.byTooltip('지도 도구 더보기'));
    await tester.pump();
    expect(find.byTooltip('원룸 시세 뱃지 켜기'), findsOneWidget);
    expect(find.byTooltip('위에서 보기'), findsOneWidget);
    expect(find.byTooltip('지도 도구 접기'), findsOneWidget);

    // 개발자 모드: 폰에선 편집 도구 모음도 접혀서 한 줄(지금 도구 + 실행취소·저장)
    AdminAuthService.isAdmin.value = true;
    await tester.pump();
    expect(find.byTooltip('편집 도구 펼치기'), findsOneWidget);
    expect(find.byTooltip('저장'), findsOneWidget);
    expect(find.text('모양'), findsNothing, reason: '접혀 있으면 도구 버튼들은 안 보인다');
    await tester.tap(find.byTooltip('편집 도구 펼치기'));
    await tester.pump();
    expect(find.text('모양'), findsOneWidget);
    expect(find.byTooltip('편집 도구 접기'), findsOneWidget);

    // 태블릿: 접기 버튼 없이 전부
    tester.view.physicalSize = const Size(900, 1200);
    await tester.pump();
    expect(find.byTooltip('편집 도구 접기'), findsNothing);
    expect(find.byTooltip('편집 도구 펼치기'), findsNothing);
    AdminAuthService.isAdmin.value = false;
    await tester.pump();
    expect(find.byTooltip('지도 도구 접기'), findsNothing);
    expect(find.byTooltip('지도 도구 더보기'), findsNothing);
    expect(find.byTooltip('위에서 보기'), findsOneWidget);

    // "개발 중" 안내는 닫으면 사라지고 기기에 기억된다.
    expect(find.byTooltip('안내 닫기'), findsOneWidget);
    await tester.tap(find.byTooltip('안내 닫기'));
    await tester.pump();
    expect(find.byTooltip('안내 닫기'), findsNothing);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('housing_dev_notice_dismissed'), isTrue);

    tester.takeException(); // 이름표용 google_fonts가 테스트에서 남기는 예외 — 무관
  });
}
