// 원룸 임대 문의 연락처(2026-10-16). 관리자가 원룸촌을 돌며 확인한 번호가 있는
// 건물은 그 번호만 보여 주고 연락처 제보를 받지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_detail_sheet.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

HousingReport _reported(String phone) => HousingReport(
      buildingId: 'b1',
      deposit: 0,
      monthlyRent: 0,
      contactPhone: phone,
      features: const [],
      reportedAt: DateTime(2026, 9, 1),
    );

Widget _sheet({HousingBuildingOverride? edited, List<HousingReport> reports = const []}) => MaterialApp(
      home: Scaffold(
        body: HousingDetailSheet(
          building: const BaseBuilding(
            id: 'b1',
            floors: 4,
            officialName: '자연빌',
            ring: [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)],
          ),
          summary: reports.isEmpty ? HousingSummary.empty : HousingSummary.from(reports),
          known: null,
          edited: edited,
          isDark: false,
          isFavorite: false,
          onToggleFavorite: () async {},
          onReported: () async {},
        ),
      ),
    );

void main() {
  group('effectiveLandlordPhones', () {
    test('확인된 번호가 있으면 그것만 — 예전 제보 번호를 섞지 않는다', () {
      expect(
        effectiveLandlordPhones(
          admin: ['010-9457-5330', '010-3562-8949'],
          reported: ['010-1111-2222'],
        ),
        ['010-9457-5330', '010-3562-8949'],
      );
    });

    test('확인된 번호가 없으면 학생 제보', () {
      expect(effectiveLandlordPhones(admin: [null, ''], reported: ['010-1111-2222']), ['010-1111-2222']);
    });

    test('예전처럼 한 칸에 쉼표로 두 번호를 넣은 것도 나눈다', () {
      expect(
        effectiveLandlordPhones(admin: ['01054604575,01088529282'], reported: const []),
        ['01054604575', '01088529282'],
      );
    });
  });

  testWidgets('확인된 번호가 있는 건물: 그 번호만 보이고 제보 버튼이 없다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const o = HousingBuildingOverride(
      buildingId: 'b1',
      name: '',
      zone: HousingZone.gateBack,
      landlordPhone: '010-9457-5330',
      landlordPhone2: '010-3562-8949',
    );
    await tester.pumpWidget(_sheet(edited: o, reports: [_reported('010-1111-2222')]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('010-9457-5330'), findsOneWidget);
    expect(find.text('010-3562-8949'), findsOneWidget);
    expect(find.text('010-1111-2222'), findsNothing);
    expect(find.text('확인된 번호'), findsOneWidget);
    expect(find.text('수정/제보'), findsNothing);
    expect(find.textContaining('2번째 연락처 추가 제보'), findsNothing);
    expect(find.text('외벽 임대 연락처 제보하기'), findsNothing);
    expect(find.textContaining('외벽 임대 문의 번호 제보하기'), findsNothing);
    // 시세 제보(시세·조건 카드)는 그대로 받는다.
    expect(find.text('제보하기'), findsOneWidget);
  });

  testWidgets('번호가 하나여도 확인된 번호면 2번째 번호 제보를 받지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const o = HousingBuildingOverride(
      buildingId: 'b1',
      name: '',
      zone: HousingZone.gateBack,
      landlordPhone: '010-4757-9088',
    );
    await tester.pumpWidget(_sheet(edited: o));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('010-4757-9088'), findsOneWidget);
    expect(find.textContaining('2번째 연락처 추가 제보'), findsNothing);
    expect(find.text('수정/제보'), findsNothing);
  });

  testWidgets('확인된 번호가 없는 건물은 예전처럼 제보를 받는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_sheet());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('번호 등록'), findsOneWidget);
    expect(find.text('외벽 임대 연락처 제보하기'), findsOneWidget);
  });
}
