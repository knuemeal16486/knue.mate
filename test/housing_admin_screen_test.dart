import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:knue_mate/housing_admin_screen.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

void main() {
  reportLabelTests();
  listEditSaveTests();

  testWidgets('HousingAdminScreen 비밀번호 게이트 렌더링', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: HousingAdminScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HousingAdminScreen), findsOneWidget);
  });
}

// 관리자 [제보 관리] 목록의 건물 이름(2026-10-08). 모양·색만 고친 건물은 수정
// 문서의 이름 칸이 비어 있어서, 그 칸을 그대로 쓰면 이름이 빈칸으로 나왔다.
void reportLabelTests() {
  BaseBuilding building(String? name) => BaseBuilding(
        id: 'b1',
        officialName: name,
        floors: 4,
        ring: const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
        road: '월탄1길',
        buildingNo: '10-31',
      );
  HousingReport report({String? oneRoomId}) => HousingReport(
        buildingId: 'b1',
        deposit: 300,
        monthlyRent: 35,
        oneRoomId: oneRoomId,
        features: const [],
        reportedAt: DateTime(2026, 10, 2),
      );

  group('housingReportBuildingLabel', () {
    test('관리자가 붙인 이름이 먼저', () {
      expect(
        housingReportBuildingLabel(
          report(),
          override: const HousingBuildingOverride(buildingId: 'b1', name: '한마음', zone: HousingZone.gateBack),
          building: building('옛이름'),
        ),
        '한마음',
      );
    });

    test('수정 문서의 이름 칸이 비었으면 지도 이름 — 빈칸이 아니다', () {
      expect(
        housingReportBuildingLabel(
          report(),
          override: const HousingBuildingOverride(buildingId: 'b1', name: '', zone: HousingZone.gateBack),
          building: building('해오름빌'),
        ),
        '해오름빌',
      );
    });

    test('지도 이름도 없으면 제보자가 고른 원룸 이름, 그것도 없으면 주소', () {
      expect(housingReportBuildingLabel(report(oneRoomId: 'bauhaus-a')), '바우하우스 A동');
      expect(housingReportBuildingLabel(report(), building: building(null)), startsWith('이름 미확인 ('));
      expect(housingReportBuildingLabel(report()), '이름 미확인 건물');
    });
  });

  group('isHousingReportHidden', () {
    test('지도에서 지웠거나 합친 건물의 제보는 앱에 안 보인다', () {
      expect(isHousingReportHidden(null), isFalse);
      expect(isHousingReportHidden(const HousingBuildingOverride(buildingId: 'b1', name: '', zone: HousingZone.gateBack, isDeleted: true)), isTrue);
      expect(isHousingReportHidden(const HousingBuildingOverride(buildingId: 'b1', name: '', zone: HousingZone.gateBack, mergedWith: 'b2')), isTrue);
      expect(isHousingReportHidden(const HousingBuildingOverride(buildingId: 'b1', name: '해오름빌', zone: HousingZone.gateBack)), isFalse);
    });
  });
}

// 관리자 목록 화면의 저장(2026-11-12). setOverride가 문서를 통째로 덮어쓰는데,
// 이 화면에 칸이 없는 값(외곽선·병합·가게·시세·2번째 번호 …)을 안 옮겨서
// 이름 하나만 고쳐도 다 지워졌다.
void listEditSaveTests() {
  const full = HousingBuildingOverride(
    buildingId: 'b1',
    name: '자연빌',
    zone: HousingZone.gateBack,
    builtYear: 2015,
    note: '메모',
    address: '월탄3길 10',
    landlordName: '사장님',
    landlordPhone: '010-9457-5330',
    landlordPhone2: '010-3562-8949',
    floors: 7,
    mapFloors: 11,
    unitCount: 20,
    customColorHex: '#03C75A',
    customRing: [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
    isDeleted: false,
    mergedWith: 'b2',
    hideLabel: true,
    showWindows: true,
    shops: [HousingShop(name: '편의점')],
    prices: [HousingPriceEntry(deposit: 300, monthlyRent: 35)],
  );

  HousingBuildingOverride save({
    HousingBuildingOverride? saved = full,
    String name = '자연빌',
    String builtYear = '2015',
    String note = '메모',
    String phone2 = '010-3562-8949',
  }) =>
      adminListEditedOverride(
        buildingId: 'b1',
        saved: saved,
        name: name,
        zone: HousingZone.gateBack,
        builtYear: builtYear,
        note: note,
        address: '월탄3길 10',
        landlordName: '사장님',
        landlordPhone: '010-9457-5330',
        landlordPhone2: phone2,
        floors: '7',
        unitCount: '20',
        customColorHex: '#03C75A',
      );

  group('adminListEditedOverride', () {
    test('손대지 않고 저장하면 문서가 그대로다', () {
      expect(save().toFirestore(), full.toFirestore());
    });

    test('이름만 고쳐도 화면에 칸이 없는 값은 남는다', () {
      final out = save(name: '새이름').toFirestore();
      expect(out['name'], '새이름');
      for (final key in [
        'mapFloors', 'customRing', 'isDeleted', 'mergedWith', 'hideLabel',
        'showWindows', 'shops', 'prices', 'landlordPhone2',
      ]) {
        expect(out[key], full.toFirestore()[key], reason: key);
      }
    });

    test('칸을 비우면 그 값은 지운다', () {
      final out = save(builtYear: '', note: '  ', phone2: '').toFirestore();
      expect(out.containsKey('builtYear'), isFalse);
      expect(out.containsKey('note'), isFalse);
      expect(out.containsKey('landlordPhone2'), isFalse);
    });

    test('처음 고치는 건물(저장된 값 없음)', () {
      final out = save(saved: null).toFirestore();
      expect(out['name'], '자연빌');
      expect(out.containsKey('customRing'), isFalse);
      expect(out.containsKey('shops'), isFalse);
    });
  });
}
