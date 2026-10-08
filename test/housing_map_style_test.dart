import 'package:flutter/painting.dart';
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

  // 2026-10-08: 흰 건물은 손님 화면에서 누르지 않고, 시세 제보는 색이 칠해진
  // 주거 건물(아파트·빌라·원룸)에만 받는다. 상가는 뺀다.
  group('누를 수 있는 건물·시세 제보 받는 건물', () {
    const green = Color(0xFF8BC34A);
    HousingBuildingOverride painted(Color c) => HousingBuildingOverride(
          buildingId: 'a',
          name: '',
          zone: HousingZone.gateBack,
          customColorHex: '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        );

    test('색이 없거나 흰색이면 누를 수 없다 — 교내 건물은 누른다', () {
      expect(isHousingTappable(_b('a'), null), isFalse);
      expect(isHousingTappable(_b('a'), const Color(0xFFFFFFFF)), isFalse);
      expect(isHousingTappable(_b('a'), green), isTrue);
      expect(isHousingTappable(_b('a', campus: true), null), isTrue);
    });

    test('지도 색 그대로 판정한다 — 월탄3길 도로 색 건물도 누른다, 이름 없는 4층 건물은 흰색', () {
      final s = housingMapStyle([_b('a', road: '월탄3길'), _b('b', road: '월탄1길')]);
      expect(isHousingTappable(_b('a', road: '월탄3길'), s.zoneColors['a']), isTrue);
      expect(isHousingTappable(_b('b', road: '월탄1길'), s.zoneColors['b']), isFalse);
    });

    test('주거 건물만 제보를 받는다 — 흰 건물·교내 건물은 안 받는다', () {
      expect(isHousingReportable(_b('a'), mapColor: green, override: painted(green)), isTrue);
      expect(isHousingReportable(_b('a'), mapColor: null), isFalse);
      expect(isHousingReportable(_b('a', campus: true), mapColor: green), isFalse);
    });

    test('상가 색 건물은 안 받는다 — 이미 시세가 있으면(1층 상가·위층 원룸) 받는다', () {
      final shop = painted(kHousingShopColor);
      expect(isHousingReportable(_b('a'), mapColor: kHousingShopColor, override: shop), isFalse);
      expect(isHousingReportable(_b('a'), mapColor: kHousingShopColor, override: shop, hasRent: true), isTrue);
    });

    test('상가주택(가온빌·디저트 39·원더빌)은 상가 색이어도 받는다', () {
      final shop = painted(kHousingShopColor);
      for (final name in ['가온빌', '디저트39', '원더빌']) {
        expect(isHousingReportable(_b('a'), mapColor: kHousingShopColor, name: name, override: shop), isTrue, reason: name);
      }
      expect(isHousingReportable(_b('a'), mapColor: kHousingShopColor, name: '교원상가1', override: shop), isFalse);
    });

    test('교내 건물은 누르지만 퇴계관(철거 예정)은 못 누른다', () {
      expect(isHousingTappable(_b('a', campus: true), null, name: '교육박물관'), isTrue);
      expect(isHousingTappable(_b('a', campus: true), null, name: '퇴계관'), isFalse);
      expect(isHousingTappable(_b('a', campus: true), null, name: '퇴계 관'), isFalse);
    });

    test('경로당은 색이 있어도 안 받는다', () {
      const brown = Color(0xFF795548);
      expect(isHousingReportable(_b('a'), mapColor: brown, name: '월탄2리 경로당', override: painted(brown)), isFalse);
      expect(isHousingTappable(_b('a'), brown), isTrue); // 누르는 건 된다
    });
  });
}
