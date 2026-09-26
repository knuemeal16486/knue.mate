import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

/// 20m × 20m, 4층 — 원룸으로 볼 만한 건물(3층 이상·50㎡ 이상).
BaseBuilding _b(
  String id, {
  String? road,
  String? no,
  String? name,
  int floors = 4,
  bool campus = false,
}) =>
    BaseBuilding(
      id: id,
      floors: floors,
      ring: const [
        Offset(0, 0),
        Offset(20, 0),
        Offset(20, 20),
        Offset(0, 20),
      ],
      road: road,
      buildingNo: no,
      officialName: name,
      isCampus: campus,
    );

void main() {
  group('housingMapStyle 이름표', () {
    test('조사한 이름이 있으면 그걸 단다', () {
      final s = housingMapStyle([_b('a', road: '월탄3길', no: '48', name: '엘리트빌')]);
      expect(s.displayNames['a'], '엘리트빌');
    });

    test('이름이 없으면 이름표를 달지 않는다 — 번지수 숫자로 채우지 않는다', () {
      // 예전엔 "48"처럼 번지수를 대신 띄웠는데 숫자 마커가 지도를 어지럽혔다.
      final s = housingMapStyle([_b('a', road: '월탄3길', no: '48')]);
      expect(s.displayNames.containsKey('a'), isFalse);
    });

    test('관리자가 끈 건물은 이름이 있어도 이름표가 없다(색은 그대로)', () {
      final s = housingMapStyle(
        [_b('a', road: '월탄3길', no: '48', name: '엘리트빌')],
        overrides: {
          'a': const HousingBuildingOverride(
            buildingId: 'a',
            name: '',
            zone: HousingZone.aroundCu,
            hideLabel: true,
          ),
        },
      );
      expect(s.displayNames.containsKey('a'), isFalse);
      expect(s.zoneColors.containsKey('a'), isTrue, reason: '월탄3길 도로 색');
    });

    test('이름표만 끈 문서도 저장했다 되읽힌다', () {
      const o = HousingBuildingOverride(buildingId: 'a', name: '', zone: HousingZone.aroundCu, hideLabel: true);
      expect(HousingBuildingOverride.fromMap('a', o.toFirestore())?.hideLabel, isTrue);
    });

    test('원룸이 아닌 작은 건물엔 이름표를 달지 않는다', () {
      final s = housingMapStyle([_b('a', road: '월탄1길', no: '3', floors: 1)]);
      expect(s.displayNames.containsKey('a'), isFalse);
      expect(s.oneRoomIds, isEmpty);
    });

    test('관리자 수정이 조사한 이름보다 우선한다', () {
      final s = housingMapStyle(
        [_b('a', road: '월탄3길', no: '48', name: '엘리트빌')],
        overrides: {
          'a': const HousingBuildingOverride(
            buildingId: 'a',
            name: '엘리트빌 신관',
            zone: HousingZone.aroundCu,
          ),
        },
      );
      expect(s.displayNames['a'], '엘리트빌 신관');
      expect(s.zoneColors['a'], HousingZone.aroundCu.color);
    });

    test('교내 건물은 원룸 판정에서 빠진다', () {
      final s = housingMapStyle([_b('a', campus: true)]);
      expect(s.oneRoomIds, isEmpty);
    });
  });

  group('housingMapStyle 색', () {
    test('월탄3길 건물은 층수와 상관없이 초록이다', () {
      final s = housingMapStyle([
        _b('tall', road: '월탄3길', no: '1'),
        _b('low', road: '월탄3길', no: '2', floors: 1),
      ]);
      final green = kHousingRoadColors['월탄3길'];
      expect(s.zoneColors['tall'], green);
      expect(s.zoneColors['low'], green);
    });

    test('다른 길은 도로색이 없다', () {
      final s = housingMapStyle([_b('a', road: '월탄1길', no: '1')]);
      expect(s.zoneColors.containsKey('a'), isFalse);
    });

    test('구역색이 있으면 도로색이 덮지 않는다', () {
      final s = housingMapStyle(
        [_b('a', road: '월탄3길', no: '1')],
        overrides: {
          'a': const HousingBuildingOverride(
            buildingId: 'a',
            name: '드림빌라',
            zone: HousingZone.dreamVilla,
          ),
        },
      );
      expect(s.zoneColors['a'], HousingZone.dreamVilla.color);
    });
  });

  group('내 조건 찾기', () {
    test('조건을 걸면 맞는 건물만 색·이름표가 남는다', () {
      final s = housingMapStyle(
        [
          _b('hit', road: '월탄3길', no: '1', name: '맞는집'),
          _b('miss', road: '월탄3길', no: '2', name: '안맞는집'),
        ],
        matches: {'hit'},
      );
      expect(s.displayNames.keys, ['hit']);
      expect(s.zoneColors.keys, ['hit']);
    });

    test('조건이 없으면 거르지 않는다', () {
      final s = housingMapStyle([
        _b('a', road: '월탄3길', no: '1', name: '가집'),
        _b('b', road: '월탄3길', no: '2', name: '나집'),
      ]);
      expect(s.displayNames.length, 2);
      expect(s.zoneColors.length, 2);
    });
  });
}
