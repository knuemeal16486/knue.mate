import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

/// 한 변이 [size]인 정사각형 건물.
BaseBuilding _box(String id, double x, double y,
        {double size = 12, int floors = 4}) =>
    BaseBuilding(
      id: id,
      floors: floors,
      ring: [
        Offset(x, y),
        Offset(x + size, y),
        Offset(x + size, y + size),
        Offset(x, y + size),
      ],
    );

void main() {
  const p = IsoProjection(scale: 2.0);

  group('아이소메트릭 투영 및 360도 회전', () {
    test('원점은 원점으로 간다', () {
      expect(p.project(0, 0), Offset.zero);
    });

    test('x와 y가 같으면 화면에서 가로 위치가 같다', () {
      expect(p.project(10, 10).dx, closeTo(p.project(30, 30).dx, 1e-9));
    });

    test('남쪽·동쪽으로 갈수록 화면 아래로 내려간다', () {
      expect(p.project(0, 10).dy, greaterThan(p.project(0, 0).dy));
      expect(p.project(10, 0).dy, greaterThan(p.project(0, 0).dy));
    });

    test('높이는 화면에서 위로 솟는다', () {
      // 화면 y축은 아래가 양수라, 높이가 있으면 값이 작아져야 한다.
      expect(p.project(0, 0, 10).dy, lessThan(p.project(0, 0).dy));
    });

    test('한 축만 움직이면 가로가 세로의 두 배로 움직인다 (2:1 비율)', () {
      final a = p.project(0, 0), b = p.project(10, 0);
      expect((b.dx - a.dx).abs(), closeTo((b.dy - a.dy).abs() * 2, 1e-9));
    });

    test('x와 y를 반대로 같은 만큼 움직이면 가로로만 이동한다', () {
      final a = p.project(0, 0), b = p.project(10, -10);
      expect(b.dy - a.dy, closeTo(0, 1e-9));
      expect((b.dx - a.dx).abs(), greaterThan(0));
    });

    test('층수가 많을수록 높다', () {
      expect(p.heightOf(_box('a', 0, 0, floors: 10)),
          greaterThan(p.heightOf(_box('b', 0, 0, floors: 3))));
    });

    test('360도 회전 시 360도(2*pi) 회전하면 원래 위치로 복귀한다', () {
      const pRot360 = IsoProjection(scale: 2.0, rotation: 2 * math.pi);
      final pt1 = p.project(15, 25, 6);
      final pt2 = pRot360.project(15, 25, 6);
      expect(pt1.dx, closeTo(pt2.dx, 1e-5));
      expect(pt1.dy, closeTo(pt2.dy, 1e-5));
    });

    test('180도 회전 시 깊이(depthKey)가 반전되어 앞뒤 렌더링 순서가 바뀐다', () {
      const p0 = IsoProjection(scale: 2.0, rotation: 0.0);
      const p180 = IsoProjection(scale: 2.0, rotation: math.pi);
      final b1 = _box('north', 0, 0);
      final b2 = _box('south', 50, 50);

      expect(p0.depthKey(b1), lessThan(p0.depthKey(b2)));
      expect(p180.depthKey(b1), greaterThan(p180.depthKey(b2)));
    });
  });

  group('건물 도형', () {
    test('바닥 외곽선 개수만큼 벽이 생긴다', () {
      final iso = buildIso(_box('a', 0, 0), p);
      expect(iso.walls.length, 4);
    });

    test('벽은 뒤에서 앞 순서로 정렬된다', () {
      // 앞 벽을 나중에 그려야 뒤 벽을 덮는다.
      final iso = buildIso(_box('a', 0, 0), p);
      for (var i = 1; i < iso.walls.length; i++) {
        expect(iso.walls[i - 1].depth,
            lessThanOrEqualTo(iso.walls[i].depth));
      }
    });

    test('면적 계산이 맞는다', () {
      expect(_box('a', 0, 0, size: 10).footprintArea, closeTo(100, 1e-6));
    });

    test('중심점이 맞는다', () {
      expect(_box('a', 0, 0, size: 10).center, const Offset(5, 5));
    });

    test('주소가 없으면 그렇다고 알려준다', () {
      expect(_box('a', 0, 0).addressLabel, '주소 정보 없음');
      const withRoad = BaseBuilding(
        id: 'x',
        floors: 3,
        ring: [Offset.zero, Offset(1, 0), Offset(1, 1)],
        road: '월탄3길',
        buildingNo: '12',
      );
      expect(withRoad.addressLabel, '월탄3길 12');
    });
  });

  group('그리는 순서 (화가 알고리즘)', () {
    test('뒤에 있는 건물이 먼저 그려진다', () {
      final list = layoutBuildings([_box('front', 60, 60), _box('back', 0, 0)], p);
      expect(list.first.building.id, 'back');
      expect(list.last.building.id, 'front');
    });
  });

  group('탭 판정', () {
    test('건물 안을 누르면 그 건물이 잡힌다', () {
      final list = layoutBuildings([_box('only', 0, 0)], p);
      final top = p.project(6, 6, p.heightOf(list.first.building));
      expect(hitTestBuilding(list, top)?.id, 'only');
    });

    test('빈 곳을 누르면 아무것도 안 잡힌다', () {
      final list = layoutBuildings([_box('only', 0, 0)], p);
      expect(hitTestBuilding(list, const Offset(5000, 5000)), isNull);
    });

    test('겹친 곳에서는 앞 건물이 잡힌다', () {
      final list = layoutBuildings([_box('back', 0, 0), _box('front', 4, 4)], p);
      final pt = p.project(8, 8, p.heightOf(list.last.building));
      expect(hitTestBuilding(list, pt)?.id, 'front',
          reason: '가려진 뒤 건물이 잡히면 안 된다');
    });
  });

  group('원룸 이름 사전', () {
    test('id가 중복되지 않는다', () {
      // id는 제보와 건물을 잇는 열쇠라 겹치면 제보가 섞인다.
      final ids = kOneRoomNames.map((n) => n.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('이름이 중복되지 않는다', () {
      final names = kOneRoomNames.map((n) => n.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('색인이 전부 들어 있다', () {
      expect(kOneRoomNameById.length, kOneRoomNames.length);
    });

    test('준공연도가 있으면 상식적인 범위다', () {
      for (final n in kOneRoomNames) {
        if (n.builtYear == null) continue;
        expect(n.builtYear, inInclusiveRange(1980, 2030), reason: n.name);
      }
    });

    test('사진 지도의 구역별 개수와 맞는다', () {
      int c(HousingZone z) => kOneRoomNames.where((n) => n.zone == z).length;
      expect(c(HousingZone.gateBack), 4);
      expect(c(HousingZone.apartments), 5);
      expect(c(HousingZone.mayToCu), 10);
      expect(c(HousingZone.aroundCu), 18);
      expect(c(HousingZone.gyowonVilla), 18);
      expect(c(HousingZone.hqPath), 10);
      expect(c(HousingZone.dreamVilla), 10);
    });
  });

  group('제보 집계', () {
    HousingReport r(int deposit, int rent,
            {List<String> features = const [], String? oneRoomId}) =>
        HousingReport(
          buildingId: 'x',
          deposit: deposit,
          monthlyRent: rent,
          features: features,
          oneRoomId: oneRoomId,
          reportedAt: DateTime(2026, 1, 1),
        );

    test('제보가 없으면 빈 요약이다', () {
      final s = HousingSummary.from(const []);
      expect(s.hasData, isFalse);
      expect(s.medianDeposit, isNull);
      expect(s.oneRoomId, isNull);
    });

    test('홀수 개면 가운데 값', () {
      final s = HousingSummary.from([r(100, 30), r(300, 50), r(200, 40)]);
      expect(s.medianDeposit, 200);
      expect(s.medianRent, 40);
    });

    test('짝수 개면 가운데 두 값의 평균', () {
      final s = HousingSummary.from([r(100, 30), r(200, 40)]);
      expect(s.medianDeposit, 150);
      expect(s.medianRent, 35);
    });

    test('이상치 하나가 중앙값을 흔들지 못한다', () {
      // 평균이었다면 9999에 끌려간다. 중앙값을 쓰는 이유다.
      final s = HousingSummary.from([r(100, 30), r(110, 32), r(9999, 300)]);
      expect(s.medianDeposit, 110);
      expect(s.medianRent, 32);
    });

    test('많이 언급된 특징이 앞에 온다', () {
      final s = HousingSummary.from([
        r(100, 30, features: ['풀옵션', '복층']),
        r(100, 30, features: ['풀옵션']),
        r(100, 30, features: ['주차 가능']),
      ]);
      expect(s.topFeatures.first, '풀옵션');
    });

    test('건물 이름은 다수결로 정해진다', () {
      // 한 사람이 잘못 지목해도 여러 명이 맞게 고르면 바로잡힌다.
      final s = HousingSummary.from([
        r(100, 30, oneRoomId: 'dasom'),
        r(100, 30, oneRoomId: 'dasom'),
        r(100, 30, oneRoomId: 'white'),
      ]);
      expect(s.oneRoomId, 'dasom');
    });

    test('아무도 이름을 안 골랐으면 이름 없이 남는다', () {
      expect(HousingSummary.from([r(100, 30), r(100, 30)]).oneRoomId, isNull);
    });

    test('제보가 3건 미만이면 참고용으로 표시된다', () {
      expect(HousingSummary.from([r(100, 30), r(100, 30)]).isThin, isTrue);
      expect(HousingSummary.from([r(100, 30), r(100, 30), r(100, 30)]).isThin,
          isFalse);
    });

    test('망가진 문서는 무시한다', () {
      expect(HousingReport.fromMap({'buildingId': 'x'}), isNull);
      expect(HousingReport.fromMap({'deposit': 100, 'monthlyRent': 30}), isNull);
      expect(
        HousingReport.fromMap(
            {'buildingId': 'x', 'deposit': 100, 'monthlyRent': 30}),
        isNotNull,
      );
    });

    test('문서 id를 넘기면 그대로 실린다 — 관리 화면이 수정·삭제할 열쇠', () {
      final r = HousingReport.fromMap(
        {'buildingId': 'x', 'deposit': 100, 'monthlyRent': 30},
        id: 'doc123',
      );
      expect(r?.id, 'doc123');
    });
  });

  group('원룸 후보 판정 (looksLikeOneRoom)', () {
    test('교내 건물은 층수·면적 조건을 만족해도 후보가 아니다', () {
      final campus = BaseBuilding(
        id: 'c',
        floors: 5,
        isCampus: true,
        ring: const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ],
      );
      expect(looksLikeOneRoom(campus, const {}), isFalse);
    });

    test('층수·면적이 기준 미만이어도 제보가 있으면 후보다', () {
      final small = BaseBuilding(
        id: 's',
        floors: 1,
        ring: const [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      );
      expect(looksLikeOneRoom(small, {'s': HousingSummary.empty}), isTrue);
    });

    test('3층 이상·50㎡ 이상 비교내 건물은 제보 없이도 후보다', () {
      final big = BaseBuilding(
        id: 'b',
        floors: 4,
        ring: const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
        ],
      );
      expect(looksLikeOneRoom(big, const {}), isTrue);
    });
  });

  group('건물 정보 관리자 덮어쓰기 (HousingBuildingOverride)', () {
    test('저장했다가 읽으면 그대로 돌아온다', () {
      const o = HousingBuildingOverride(
        buildingId: 'b1',
        name: '테스트빌',
        zone: HousingZone.aroundCu,
        builtYear: 2015,
        note: '1층 카페',
      );
      final restored = HousingBuildingOverride.fromMap('b1', o.toFirestore());
      expect(restored?.name, '테스트빌');
      expect(restored?.zone, HousingZone.aroundCu);
      expect(restored?.builtYear, 2015);
      expect(restored?.note, '1층 카페');
    });

    test('이름이 없으면 무시한다', () {
      expect(HousingBuildingOverride.fromMap('b1', {'zone': 'aroundCu'}), isNull);
    });

    test('알 수 없는 구역 값은 무시한다', () {
      expect(
        HousingBuildingOverride.fromMap('b1', {'name': 'x', 'zone': 'nope'}),
        isNull,
      );
    });

    test('OneRoomName으로 바꾸면 지도·검색이 쓰는 필드가 그대로 옮겨진다', () {
      const o = HousingBuildingOverride(
        buildingId: 'b1',
        name: '테스트빌',
        zone: HousingZone.dorm,
        builtYear: 2020,
      );
      final n = o.toOneRoomName();
      expect(n.name, '테스트빌');
      expect(n.zone, HousingZone.dorm);
      expect(n.builtYear, 2020);
    });
  });
  _landUseTests();
}

/// 지적 기반 용도별 바닥면 — 네이버지도식 "깔끔함"의 핵심 레이어.
void _landUseTests() {
  group('용도별 바닥면', () {
    test('저장 키가 enum 이름과 맞는다', () {
      // 에셋의 'g' 값이 그대로 enum 이름이라, 바뀌면 지도가 통째로 빈다.
      expect(LandUse.fromKey('campus'), LandUse.campus);
      expect(LandUse.fromKey('forest'), LandUse.forest);
      expect(LandUse.fromKey('road'), LandUse.road);
      expect(LandUse.fromKey('water'), LandUse.water);
      expect(LandUse.fromKey('farm'), LandUse.farm);
      expect(LandUse.fromKey('park'), LandUse.park);
    });

    test('모르는 값과 null은 조용히 버린다', () {
      expect(LandUse.fromKey('mystery'), isNull);
      expect(LandUse.fromKey(null), isNull);
    });

    test('같은 용도는 Path 하나로 합쳐진다', () {
      // 1,500필지를 따로 그리면 드로우콜이 그만큼 늘어난다.
      const p = IsoProjection(scale: 2.0);
      final iso = projectLandUse([
        BaseLandUse(LandUse.farm, const [Offset(0, 0), Offset(10, 0), Offset(10, 10)]),
        BaseLandUse(LandUse.farm, const [Offset(20, 0), Offset(30, 0), Offset(30, 10)]),
        BaseLandUse(LandUse.campus, const [Offset(0, 20), Offset(10, 20), Offset(10, 30)]),
      ], p);
      expect(iso.byUse.keys.toSet(), {LandUse.farm, LandUse.campus});
    });

    test('점이 3개 미만인 필지는 버린다', () {
      const p = IsoProjection(scale: 2.0);
      final iso = projectLandUse([
        BaseLandUse(LandUse.water, const [Offset(0, 0), Offset(1, 1)]),
      ], p);
      expect(iso.byUse, isEmpty);
    });

    test('용도마다 색이 서로 다르다', () {
      // 같은 색이면 구분이 안 돼 레이어를 나눈 의미가 없다.
      for (final dark in [false, true]) {
        final colors =
            LandUse.values.map((u) => landUseColor(u, dark)).toSet();
        expect(colors.length, LandUse.values.length, reason: 'dark=$dark');
      }
    });

    test('바닥은 옅어서 그 위 건물을 가리지 않는다', () {
      // 라이트 모드에서 바닥이 진하면 건물이 묻힌다.
      for (final u in LandUse.values) {
        final c = landUseColor(u, false);
        expect(c.computeLuminance(), greaterThan(0.55), reason: '$u 가 너무 진하다');
      }
    });

    test('바닥이 배경과 충분히 구분된다', () {
      // 처음엔 라이트를 거의 흰색에 둬서 농지가 배경과 휘도 0.024밖에 차이
      // 나지 않아 전부 하얗게 뭉갰고, 다크는 임야가 0.0008 차이로 묻혔다.
      // 다시 그렇게 되지 않도록 최소 간격을 못 박는다.
      for (final dark in [false, true]) {
        final bg = mapBackgroundColor(dark).computeLuminance();
        final floor = dark ? 0.02 : 0.09;
        for (final u in LandUse.values) {
          final diff = (landUseColor(u, dark).computeLuminance() - bg).abs();
          expect(diff, greaterThanOrEqualTo(floor),
              reason: 'dark=$dark $u 가 배경과 ${diff.toStringAsFixed(3)}밖에 '
                  '차이 안 나 묻힌다');
        }
      }
    });

    test('다크 모드 바닥이 새까맣지 않다', () {
      // 휘도가 배경 수준으로 낮으면 지형이 안 읽힌다.
      for (final u in LandUse.values) {
        expect(landUseColor(u, true).computeLuminance(), greaterThan(0.035),
            reason: '$u 가 너무 어둡다');
      }
    });

    test('라이트가 흰색에 가깝지 않다', () {
      // 휘도 0.88을 넘으면 배경과 붙어 하얗게 뭉친다.
      for (final u in LandUse.values) {
        expect(landUseColor(u, false).computeLuminance(), lessThan(0.85),
            reason: '$u 가 너무 밝다');
      }
    });

    test('도로 필지가 골목까지 담고 있다', () {
      // 도로중심선에는 큰길 64개뿐이라 교내 도로와 원룸촌 골목이 빠져 있었다.
      // 지적 도로 필지로 바꾼 뒤에도 이 커버리지가 유지되는지 지킨다.
      const p = IsoProjection(scale: 2.0);
      final iso = projectLandUse([
        BaseLandUse(LandUse.road,
            const [Offset(0, 0), Offset(30, 0), Offset(30, 4), Offset(0, 4)]),
        BaseLandUse(LandUse.road,
            const [Offset(0, 10), Offset(3, 10), Offset(3, 40), Offset(0, 40)]),
      ], p);
      // 넓은 길과 좁은 골목이 같은 Path에 합쳐져 한 번에 그려진다.
      expect(iso.byUse[LandUse.road], isNotNull);
      expect(iso.byUse.length, 1);
    });
  });
}
