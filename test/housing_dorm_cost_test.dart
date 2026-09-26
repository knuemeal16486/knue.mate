import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_detail_sheet.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget sheet(String name, {bool campus = true}) => MaterialApp(
      home: Scaffold(
        body: HousingDetailSheet(
          building: BaseBuilding(
            id: name,
            floors: 10,
            officialName: name,
            isCampus: campus,
            ring: const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
          ),
          summary: HousingSummary.empty,
          known: null,
          edited: null,
          isDark: false,
          isFavorite: false,
          onToggleFavorite: () async {},
          onReported: () async {},
        ),
      ),
    );

void main() {
  test('다감관 이름 판정·원 표기', () {
    expect(isDagamName('다감관 A동'), isTrue);
    expect(isDagamName('다감관'), isTrue);
    expect(isDagamName('관리동'), isFalse);
    expect(isDagamName(null), isFalse);
    expect(formatWon(2387120), '2,387,120원');
    expect(formatWon(850000), '850,000원');
    expect(formatWon(0), '0원');
  });

  testWidgets('다감관을 누르면 1인실·2인실 비용과 식비가 보인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 폰 세로 폭에서도 넘치지 않는다
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sheet('다감관 B동'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기숙사 비용'), findsOneWidget);
    expect(find.text('2,387,120원'), findsOneWidget); // 1인실
    expect(find.text('1,350,000원'), findsOneWidget); // 2인실
    expect(find.text('1,684,200원'), findsOneWidget); // 식비
    expect(find.text('4,071,320원'), findsOneWidget); // 1인실 + 식비
    expect(find.text('3,034,200원'), findsOneWidget); // 2인실 + 식비
    expect(find.textContaining('2026-2학기'), findsOneWidget);
  });

  testWidgets('원룸 구역으로 칠한 다감관 동도 시세·제보 없이 기숙사비만', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(sheet('다감관 A동', campus: false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기숙사 비용'), findsOneWidget);
    expect(find.text('시세·조건'), findsNothing);
    expect(find.text('제보하기'), findsNothing);
    expect(find.textContaining('알려주기'), findsNothing);
    expect(find.textContaining('교육·행정'), findsNothing);
  });

  testWidgets('다른 교내 건물엔 안 나온다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(sheet('인문과학관'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기숙사 비용'), findsNothing);
  });
}
