import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';
import 'package:knue_mate/housing_shape_edit.dart';

void main() {
  const square = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];

  group('외곽선 편집', () {
    // 지도 데이터 대부분이 첫 점을 끝에 한 번 더 적는다. 그대로 두면 같은
    // 자리에 손잡이가 둘 떠서 하나만 끌면 모서리가 찢어진다.
    test('닫힌 외곽선은 끝점을 떼고, 열린 건 그대로 둔다', () {
      expect(openRing([...square, square.first]), square);
      expect(openRing(square), square);
    });

    test('꼭짓점을 옮긴다', () {
      expect(moveRingVertex(square, 2, const Offset(12, 14))[2], const Offset(12, 14));
      expect(moveRingVertex(square, 2, const Offset(12, 14)).length, 4);
    });

    test('변 가운데에 꼭짓점을 끼운다(마지막 변은 첫 점과 이어진다)', () {
      expect(insertRingMidpoint(square, 0)[1], const Offset(5, 0));
      final last = insertRingMidpoint(square, 3);
      expect(last.length, 5);
      expect(last.last, const Offset(0, 5));
      expect(ringMidpoints(square), const [Offset(5, 0), Offset(10, 5), Offset(5, 10), Offset(0, 5)]);
    });

    // 작은 건물은 손잡이 닿는 범위가 겹친다. 위에 깔린 손잡이를 고르면
    // "+"가 꼭짓점 밑에 묻혀 한 번도 안 눌렸다.
    test('손가락에 가장 가까운 손잡이를 고른다 — "+"도 묻히지 않는다', () {
      final mids = ringMidpoints(square);
      expect(pickShapeHandle(square, mids, const Offset(9, 1)), const ShapeHandlePick(false, 1));
      expect(pickShapeHandle(square, mids, const Offset(5, 1)), const ShapeHandlePick(true, 0));
      expect(pickShapeHandle(square, mids, const Offset(10, 5)), const ShapeHandlePick(true, 1));
      expect(pickShapeHandle(const [], const [], Offset.zero), isNull);
    });

    test('면적 중심 — 한쪽에 꼭짓점이 몰려도 치우치지 않는다', () {
      expect(ringCentroid(square), const Offset(5, 5));
      // 윗변에 점을 잔뜩 넣어도 정사각형의 중심은 그대로다.
      final dense = [const Offset(0, 0), for (var x = 1; x < 10; x++) Offset(x.toDouble(), 0), ...square.sublist(1)];
      final c = ringCentroid(dense);
      expect(c.dx, closeTo(5, 1e-9));
      expect(c.dy, closeTo(5, 1e-9));
    });

    test('중심을 축으로 돌린다 — 양수는 위에서 볼 때 시계 방향', () {
      // 지도 좌표는 y가 남쪽. 동쪽(+x)에 있던 점을 시계 방향 90° 돌리면 남쪽(+y)으로 간다.
      final r = rotateRing(square, 90);
      expect(ringCentroid(r).dx, closeTo(5, 1e-9));
      expect(ringCentroid(r).dy, closeTo(5, 1e-9));
      final east = rotateRing(const [Offset(10, 0), Offset(-10, 1), Offset(-10, -1)], 90);
      final c = ringCentroid(const [Offset(10, 0), Offset(-10, 1), Offset(-10, -1)]);
      expect(east.first.dx, closeTo(c.dx, 1e-9));
      expect(east.first.dy, greaterThan(c.dy));
    });

    test('1°씩 360번 돌리면 제자리, 크기는 그대로', () {
      var r = square;
      for (var i = 0; i < 360; i++) {
        r = rotateRing(r, 1);
      }
      for (var i = 0; i < square.length; i++) {
        expect((r[i] - square[i]).distance, lessThan(1e-6));
      }
      final once = rotateRing(square, 1.5);
      expect((once[1] - once[0]).distance, closeTo(10, 1e-9));
    });

    test('통째로 옮긴다', () {
      expect(translateRing(square, const Offset(2, -3)).first, const Offset(2, -3));
      expect(translateRing(square, const Offset(2, -3)).length, 4);
    });

    group('방향키는 화면 기준', () {
      test('위에서 보기: ↑는 북쪽(y −), →는 동쪽(x +)', () {
        const p = IsoProjection(scale: 2.2, topDown: true);
        final up = screenDirToWorld((x, y) => p.unproject(x, y), 0, -1, 0.5);
        expect(up.dx, closeTo(0, 1e-9));
        expect(up.dy, closeTo(-0.5, 1e-9));
        final right = screenDirToWorld((x, y) => p.unproject(x, y), 1, 0, 3);
        expect(right.dx, closeTo(3, 1e-9));
      });

      test('3D 시점: ↑는 화면 위쪽 = 지도의 북서쪽, 길이는 그대로', () {
        const p = IsoProjection(scale: 2.2);
        final up = screenDirToWorld((x, y) => p.unproject(x, y, 12), 0, -1, 1);
        expect(up.distance, closeTo(1, 1e-9));
        expect(up.dx, closeTo(up.dy, 1e-9));
        expect(up.dx, lessThan(0));
        // 옮긴 뒤 화면에서 정말 위로만 갔는지.
        final a = p.project(0, 0, 12), b = p.project(up.dx, up.dy, 12);
        expect((b - a).dx, closeTo(0, 1e-9));
        expect((b - a).dy, lessThan(0));
      });

      test('지도를 돌려도 ↑는 화면 위쪽', () {
        const p = IsoProjection(scale: 2.2, rotation: 1.1);
        final up = screenDirToWorld((x, y) => p.unproject(x, y), 0, -1, 1);
        final a = p.project(0, 0), b = p.project(up.dx, up.dy);
        expect((b - a).dx, closeTo(0, 1e-9));
        expect((b - a).dy, lessThan(0));
      });
    });

    test('꼭짓점을 빼되 셋 밑으로는 안 된다', () {
      expect(removeRingVertex(square, 1), const [Offset(0, 0), Offset(10, 10), Offset(0, 10)]);
      expect(removeRingVertex(square.sublist(0, 3), 0), isNull);
    });
  });

  group('모양만 고친 수정 문서', () {
    const b = BaseBuilding(id: 'b', floors: 2, ring: square, officialName: '어떤 건물');
    const shapeOnly = HousingBuildingOverride(
      buildingId: 'b',
      name: '',
      zone: HousingZone.darak,
      customRing: [Offset(0, 0), Offset(20, 0), Offset(20, 20)],
    );

    test('이름 없이 저장돼도 되읽히고, 모양이 반영된다', () {
      final restored = HousingBuildingOverride.fromMap('b', shapeOnly.toFirestore());
      expect(restored, isNotNull);
      expect(restored!.isNamed, isFalse);
      expect(applyBuildingOverrides([b], {'b': restored}).single.ring, shapeOnly.customRing);
    });

    test('색만 칠한 문서도 이름 없이 되읽힌다', () {
      const painted = HousingBuildingOverride(
        buildingId: 'b',
        name: '',
        zone: HousingZone.darak,
        customColorHex: '#FF5722',
      );
      final restored = HousingBuildingOverride.fromMap('b', painted.toFirestore());
      expect(restored?.customColor?.toARGB32(), 0xFFFF5722);
      expect(housingMapStyle([b], overrides: {'b': restored!}).displayNames['b'], '어떤 건물');
    });

    // 모양을 고쳤다고 건물이 원룸 구역 색으로 칠해지면 안 된다.
    test('색·이름표는 건드리지 않는다', () {
      final plain = housingMapStyle([b]);
      final edited = housingMapStyle([b], overrides: {'b': shapeOnly});
      expect(edited.zoneColors, plain.zoneColors);
      expect(edited.displayNames, plain.displayNames);
    });
  });

  // 색을 한 번 정한 건물은 다크 모드로 바꿔도 그 색에 묶여 있었다. "시스템"을
  // 고르면 고정 색 없이 밝은/다크 모드 기본 색을 따른다.
  group('시스템 색', () {
    const ring = [Offset(0, 0), Offset(10, 0), Offset(10, 10)];
    const b = BaseBuilding(id: 'b', floors: 2, ring: ring, road: '월탄3길', officialName: '가온빌');
    const sys = HousingBuildingOverride(
      buildingId: 'b',
      name: '가온빌',
      zone: HousingZone.darak,
      customColorHex: HousingBuildingOverride.systemColor,
    );

    test('저장했다 되읽어도 시스템 색이고, 고정 색은 없다', () {
      final restored = HousingBuildingOverride.fromMap('b', sys.toFirestore())!;
      expect(restored.usesSystemColor, isTrue);
      expect(restored.customColor, isNull);
    });

    test('구역 색도 도로 색도 칠하지 않고 이름표만 단다', () {
      // 시스템이 아니면 이름 붙은 수정은 구역 색으로 칠해진다.
      final zoned = housingMapStyle([b], overrides: {'b': sys.copyWith(customColorHex: '')});
      expect(zoned.zoneColors.containsKey('b'), isTrue);

      final style = housingMapStyle([b], overrides: {'b': sys});
      expect(style.zoneColors.containsKey('b'), isFalse);
      expect(style.displayNames['b'], '가온빌');
    });
  });

  // 다정관처럼 교내 건물은 칠해도 용도 색에 가려 그대로였다.
  group('교내 건물 색', () {
    const ring = [Offset(0, 0), Offset(10, 0), Offset(10, 10)];
    const dorm = BaseBuilding(id: 'd', floors: 12, ring: ring, isCampus: true, officialName: '다정관');

    test('관리자가 칠한 색은 교내 건물에도 들어간다', () {
      final style = housingMapStyle([dorm], overrides: {
        'd': const HousingBuildingOverride(buildingId: 'd', name: '다정관', zone: HousingZone.darak, customColorHex: '#E53935'),
      });
      expect(style.zoneColors['d']?.toARGB32(), 0xFFE53935);
    });

    test('이름만 고친 교내 건물은 원룸 구역 색으로 칠하지 않는다(용도 색 유지)', () {
      final style = housingMapStyle([dorm], overrides: {
        'd': const HousingBuildingOverride(buildingId: 'd', name: '다정관', zone: HousingZone.darak),
      });
      expect(style.zoneColors.containsKey('d'), isFalse);
      expect(style.displayNames['d'], '다정관');
    });
  });

  test('팔레트: 색이 겹치지 않고, 밝은 색 위 체크는 검게', () {
    expect(kHousingPalette.map((c) => c.toARGB32()).toSet().length, kHousingPalette.length);
    expect(kHousingPalette.length, greaterThanOrEqualTo(20));
    expect(paletteCheckColor(const Color(0xFFFFEB3B)), isNot(Colors.white));
    expect(paletteCheckColor(const Color(0xFFFFFFFF)), isNot(Colors.white));
    expect(paletteCheckColor(const Color(0xFF3F51B5)), Colors.white);
  });
}
