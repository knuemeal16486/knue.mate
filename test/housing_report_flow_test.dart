import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_report_sheet.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

HousingReport _r(int deposit, int rent, {int? fee, List<String> features = const []}) => HousingReport(
      buildingId: 'b',
      deposit: deposit,
      monthlyRent: rent,
      maintenanceFee: fee,
      features: features,
      reportedAt: DateTime(2026, 9, 19),
    );

void main() {
  group('제보가 조건 찾기에 반영된다', () {
    // 서버에 실제로 있는 제보 2건(바우하우스, 2026-09-19).
    final real = HousingSummary.from([
      _r(50, 53, fee: 5, features: const ['풀옵션', '엘리베이터', '주차 가능', '베란다']),
      _r(300, 38, fee: 5, features: const ['풀옵션']),
    ]);

    test('실제 제보 2건이 요약·조건 찾기에 잡힌다', () {
      expect(real.reportCount, 2);
      expect(real.allFeatures, contains('풀옵션'));
      // 방 구조를 안 적은 제보는 평균 한 점으로 모인다(월세 45.5 + 관리비 5).
      final r = evaluateHousingFilter(real, null, const HousingFilter(maxMonthly: 55, requiredFeatures: {'풀옵션'}));
      expect(r.verdict, HousingFilterVerdict.match);
      expect(r.best?.maintenanceKnown, isTrue);
      expect(evaluateHousingFilter(real, null, const HousingFilter(maxMonthly: 40)).verdict, HousingFilterVerdict.miss);
    });

    // 한동안 제보 폼이 긴 문구를 저장해서, 조건 찾기(짧은 이름)에 절대 안 걸렸다.
    test('예전 긴 문구로 남긴 장점도 조건 찾기의 짧은 이름으로 걸린다', () {
      final legacy = HousingSummary.from([
        _r(300, 35, features: const ['도시가스 난방', '풀옵션(전자레인지 등)', '채광/남향']),
      ]);
      expect(legacy.allFeatures, containsAll(['도시가스', '풀옵션', '햇빛 잘 듦']));
      final r = evaluateHousingFilter(legacy, null, const HousingFilter(requiredFeatures: {'도시가스', '풀옵션'}));
      expect(r.verdict, HousingFilterVerdict.match);
    });

    test('옛 문구와 새 이름이 한 제보에 겹쳐도 한 번만 센다', () {
      final s = HousingSummary.from([
        _r(300, 35, features: const ['풀옵션', '풀옵션(전자레인지 등)']),
      ]);
      expect(s.allFeatures.where((f) => f == '풀옵션').length, 1);
    });

    test('모든 장점 이름은 조건 찾기 목록에 있다 — 목록이 두 벌로 갈라지지 않게', () {
      expect(canonicalFeature('수압 강함/온수 양호'), '수압 좋음');
      expect(kHousingFeatures, contains('수압 좋음'));
      expect(canonicalFeature('처음 보는 문구'), '처음 보는 문구');
    });
  });

  testWidgets('제보 창: 필수 칸만 보이고, 저장 실패는 실패로 알린다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var submitted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HousingReportSheet(
          building: const BaseBuilding(id: 'b', floors: 4, ring: [Offset(0, 0), Offset(10, 0), Offset(10, 10)]),
          isDark: false,
          onSubmitted: () async => submitted = true,
        ),
      ),
    ));

    // 선택 항목은 접혀 있다
    expect(find.text('좋은 점'), findsNothing);
    expect(find.text('더 알려주기 (선택)'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, '보증금'), '300');
    await tester.enterText(find.widgetWithText(TextFormField, '월세'), '38');
    await tester.tap(find.text('제보하기'));
    // Firebase가 없는 테스트에선 저장이 실패한다 — 예전엔 이때도 "등록되었습니다"가 떴다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
    expect(find.textContaining('등록되었'), findsNothing);
    expect(submitted, isFalse);

    // 펼치면 좋은 점은 조건 찾기와 같은 목록
    await tester.tap(find.text('더 알려주기 (선택)'));
    await tester.pumpAndSettle();
    expect(find.text('좋은 점'), findsOneWidget);
    expect(find.text('풀옵션'), findsOneWidget);
    expect(find.text('풀옵션(전자레인지 등)'), findsNothing);
  });
}
