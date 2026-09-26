import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

const _ring = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];

BaseBuilding _b(String id, {bool campus = false, BuildingUse? use, int floors = 3}) =>
    BaseBuilding(id: id, floors: floors, ring: _ring, isCampus: campus, use: use);

HousingBuildingOverride _o(String id, {String? mergedWith, int? floors, int? mapFloors}) =>
    HousingBuildingOverride(
      buildingId: id,
      name: '',
      zone: HousingZone.campus,
      mergedWith: mergedWith,
      isDeleted: mergedWith != null ? true : null,
      floors: floors,
      mapFloors: mapFloors,
    );

void main() {
  group('합친 건물의 교내 여부·용도', () {
    test('교내 조각이 있으면 교내, 용도는 가장 많은 것', () {
      final t = mergedCampusTraits([
        _b('a', campus: true, use: BuildingUse.dorm),
        _b('b', campus: true, use: BuildingUse.dorm),
        _b('c', campus: true, use: BuildingUse.academic),
        _b('d'),
      ]);
      expect(t.isCampus, isTrue);
      expect(t.use, BuildingUse.dorm);
      expect(mergedCampusTraits([_b('x'), _b('y')]).isCampus, isFalse);
    });

    // 예전 합치기는 교내 건물을 합쳐도 "교외 건물"로 만들었다.
    test('이미 합쳐 둔 건물도 원래 조각에서 교내 용도를 되살린다', () {
      final buildings = [
        _b('dorm1', campus: true, use: BuildingUse.dorm),
        _b('dorm2', campus: true, use: BuildingUse.dorm),
        _b('merged_1'), // 교외로 잘못 만들어진 합친 건물
        _b('room'),
      ];
      final out = inheritMergedCampus(buildings, {
        'dorm1': _o('dorm1', mergedWith: 'merged_1'),
        'dorm2': _o('dorm2', mergedWith: 'merged_1'),
      });
      final merged = out.firstWhere((b) => b.id == 'merged_1');
      expect(merged.isCampus, isTrue);
      expect(merged.use, BuildingUse.dorm);
      expect(out.firstWhere((b) => b.id == 'room').isCampus, isFalse);
    });

    test('추가·합친 건물의 용도는 저장했다 되읽힌다', () {
      final b = customBuildingFromMap('merged_1', {
        'name': '다정관',
        'floors': 12,
        'isCampus': true,
        'use': 'dorm',
        'ring': encodeRing(_ring),
      })!;
      expect(b.isCampus, isTrue);
      expect(b.use, BuildingUse.dorm);
    });
  });

  group('표시 층수와 지도 높이', () {
    // 종합교육관: 7층인데 층고가 높아 11층만큼 그려야 실제처럼 보인다.
    test('지도 높이를 따로 적으면 높이는 그걸로, 표시 층수는 그대로', () {
      final o = _o('edu', floors: 7, mapFloors: 11);
      final drawn = applyBuildingOverrides([_b('edu', campus: true, floors: 7)], {'edu': o}).single;
      expect(drawn.floors, 11, reason: '지도에 그리는 높이');
      final back = HousingBuildingOverride.fromMap('edu', o.toFirestore())!;
      expect(back.floors, 7, reason: '화면에 보여주는 층수');
      expect(back.mapFloors, 11);
    });

    test('지도 높이를 비우면 층수대로 그린다', () {
      final drawn = applyBuildingOverrides([_b('a', floors: 3)], {'a': _o('a', floors: 5)}).single;
      expect(drawn.floors, 5);
    });
  });

  test('캠퍼스 시설은 원룸 구역 칩에 나오지 않는다', () {
    expect(HousingZone.housingZones, isNot(contains(HousingZone.campus)));
    expect(HousingZone.values, contains(HousingZone.campus));
    expect(HousingZone.housingZones.length, HousingZone.values.length - 1);
  });

  group('캠퍼스 시설 표시', () {
    test('교내 건물 주소는 수정 문서와 상관없이 태성탑연로 250', () {
      final campus = _b('c', campus: true);
      const o = HousingBuildingOverride(buildingId: 'c', name: '교수아파트', zone: HousingZone.gateBack, address: '태성탑연로 314-7');
      expect(displayAddress(campus, o), '태성탑연로 250');
      expect(campus.addressLabel, '태성탑연로 250');
      final room = BaseBuilding(id: 'r', floors: 4, ring: _ring, road: '월탄3길', buildingNo: '5');
      expect(displayAddress(room, null), '월탄3길 5');
      expect(displayAddress(room, const HousingBuildingOverride(buildingId: 'r', name: 'x', zone: HousingZone.gateBack, address: '월탄3길 5-1')), '월탄3길 5-1');
    });

    // 예전엔 교내 건물을 고치면 구역이 기본값 "정문상가 뒷편"으로 저장돼 그 딱지가 떴다.
    test('교내 건물 딱지는 "캠퍼스 시설"', () {
      const known = OneRoomName(id: 'x', name: '종합교육관', zone: HousingZone.gateBack);
      expect(badgeZone(_b('c', campus: true), known), HousingZone.campus);
      expect(badgeZone(_b('r'), known), HousingZone.gateBack);
    });

    test('구역을 "캠퍼스 시설"로 고른 건물은 교내 건물로 다룬다', () {
      final out = inheritMergedCampus([_b('shop'), _b('room')], {
        'shop': const HousingBuildingOverride(buildingId: 'shop', name: '교원상가', zone: HousingZone.campus),
        'room': const HousingBuildingOverride(buildingId: 'room', name: '가온빌', zone: HousingZone.hqPath),
      });
      expect(out.map((b) => b.isCampus), [true, false]);
    });
  });

  group('시세는 제보가 있을 때만', () {
    test('제보가 없으면 시세가 없다(지어낸 200/34를 띄우지 않는다)', () {
      for (final t in HousingRoomType.values) {
        expect(HousingSummary.empty.getPricing(t), isNull, reason: '$t');
      }
    });
  });
}
