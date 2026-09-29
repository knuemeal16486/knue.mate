import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:knue_mate/admin_auth_service.dart';
import 'package:knue_mate/housing_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 지도 에셋 로딩은 파일마다 한 번만 제대로 돈다 — 그래서 한 테스트 안에서
// 차례로 본다(housing_phone_layout_test와 같은 이유).
void main() {
  testWidgets('카드 닫기(X·아래로 밀기·뒤로가기) + 개발자 도구가 검색 결과를 덮지 않는다', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    AdminAuthService.isAdmin.value = false;
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => AdminAuthService.isAdmin.value = false);

    final focus = ValueNotifier<HousingFocusRequest?>(null);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => HousingScreen(focusRequests: focus))),
          child: const Text('열기'),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pump();
    for (var i = 0; i < 40 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> openCard() async {
      focus.value = HousingFocusRequest.building('에코빌', DateTime.now().microsecondsSinceEpoch);
      await tester.pump();
      expect(find.text('상세보기'), findsOneWidget, reason: '미리보기 카드가 떠야 한다');
    }

    // 1) X: 누를 곳이 44px 이상이고, 누르면 닫힌다.
    await openCard();
    final close = find.bySemanticsLabel('카드 닫기');
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));
    await tester.tap(close);
    await tester.pump();
    expect(find.text('상세보기'), findsNothing);

    // 2) 아래로 밀면 닫힌다.
    await openCard();
    await tester.fling(find.text('상세보기'), const Offset(0, 200), 1000);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('상세보기'), findsNothing);

    // 3) 개발자 모드: 편집 도구(접힘·펼침)가 검색 결과를 덮지 않는다.
    //    예전엔 도구가 위에서 92에 떠 있어 결과 항목을 눌러도 도구가 눌렸다.
    AdminAuthService.isAdmin.value = true;
    await tester.pump();
    bool tileAt(Offset o) =>
        tester.hitTestOnBinding(o).path.any((e) => e.target.runtimeType.toString() == '_RenderListTile');
    Future<void> expectResultsReachable(String state) async {
      await tester.enterText(find.byType(TextField), '관');
      await tester.pump();
      final items = find.text('상세보기 ›');
      expect(items, findsWidgets);
      final listBox = tester.getRect(find.ancestor(of: items.first, matching: find.byType(ListView)));
      for (var i = 0; i < items.evaluate().length; i++) {
        final c = tester.getRect(items.at(i)).center;
        if (!listBox.contains(c)) continue; // 목록 안에서 스크롤해야 보이는 항목
        expect(tileAt(c), isTrue, reason: '$state: $i번째 결과가 가려졌다');
      }
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
    }

    await expectResultsReachable('접힘');
    await tester.tap(find.byTooltip('편집 도구 펼치기'));
    await tester.pump();
    await expectResultsReachable('펼침');

    // 편집 도구는 칩 줄 아래에 있다.
    final chipBottom = tester.getRect(find.text('이름표').first).bottom; // 칩(펼친 도구에도 같은 글자가 있다)
    final toolTop = tester.getRect(find.byTooltip('편집 도구 접기')).top;
    expect(toolTop, greaterThan(chipBottom));
    AdminAuthService.isAdmin.value = false;
    await tester.pump();
    // 4) 뒤로가기는 화면이 아니라 카드를 먼저 닫는다.
    await openCard();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('상세보기'), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget, reason: '지도 화면은 그대로');
    await tester.binding.handlePopRoute(); // 카드가 없으면 화면을 나간다
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('열기'), findsOneWidget);

    tester.takeException(); // 이름표용 google_fonts가 테스트에서 남기는 예외 — 무관
  });
}
