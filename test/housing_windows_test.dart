import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/painting.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/housing_model.dart';
import 'package:knue_mate/housing_service.dart';

void main() {
  // 이름표는 TextPainter로 글자를 재서 바인딩이 필요하다.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('벽 창문 자리', () {
    test('층마다 같은 수의 창문이 층 사이 벽을 남기고 난다', () {
      final w = wallWindows(12, 4, 3);
      expect(w.length % 4, 0, reason: '층마다 같은 수');
      final perFloor = w.length ~/ 4;
      expect(perFloor, 2); // (12 - 1) / 5 → 2개
      for (final x in w) {
        final floor = (x.z0 / 3).floor();
        // 한 층(3m) 안, 바닥·천장과 떨어져 있다.
        expect(x.z0, greaterThan(floor * 3.0));
        expect(x.z1, lessThan((floor + 1) * 3.0));
        expect(x.t0, greaterThanOrEqualTo(0));
        expect(x.t1, lessThanOrEqualTo(1));
        expect((x.t1 - x.t0) * 12, closeTo(2.0, 1e-9), reason: '폭 2m');
      }
    });

    test('창문끼리 겹치지 않는다', () {
      final firstFloor = wallWindows(20, 1, 3)..sort((a, b) => a.t0.compareTo(b.t0));
      for (var i = 1; i < firstFloor.length; i++) {
        expect(firstFloor[i].t0, greaterThan(firstFloor[i - 1].t1));
      }
    });

    test('짧은 벽 조각·층 없는 건물엔 창문이 없다', () {
      expect(wallWindows(2.9, 5, 3), isEmpty);
      expect(wallWindows(10, 0, 3), isEmpty);
    });
  });

  test('자취방 건물에만 창문을 내고, 위에서 보기에선 뺀다', () {
    const ring = [Offset(0, 0), Offset(12, 0), Offset(12, 10), Offset(0, 10)];
    const room = BaseBuilding(id: 'r', floors: 4, ring: ring);
    const campus = BaseBuilding(id: 'c', floors: 4, ring: ring, isCampus: true);
    const p = IsoProjection(scale: 2);
    bool hasWindows(IsoBuilding b) => b.walls.any((w) => w.windows != null);
    expect(hasWindows(buildIso(room, p, isOneRoom: true)), isTrue);
    expect(hasWindows(buildIso(room, p)), isFalse, reason: '원룸이 아닌 건물');
    expect(hasWindows(buildIso(campus, p, isOneRoom: true)), isFalse, reason: '교내 건물');
    expect(hasWindows(buildIso(room, const IsoProjection(scale: 2, topDown: true), isOneRoom: true)), isFalse);
  });

  group('창문 색: 벽에 녹아든다', () {
    test('벽 색보다 아주 조금만 밝다', () {
      const wall = Color(0xFF4CAF50);
      final w = HSLColor.fromColor(windowColorFor(wall));
      final base = HSLColor.fromColor(wall);
      expect(w.lightness - base.lightness, closeTo(0.06, 0.01));
      expect(w.hue, closeTo(base.hue, 1.0), reason: '색은 같고 명도만');
    });

    test('흰 벽처럼 이미 밝은 벽은 조금 어둡게', () {
      final w = HSLColor.fromColor(windowColorFor(const Color(0xFFEFF3F8)));
      expect(w.lightness, lessThan(HSLColor.fromColor(const Color(0xFFEFF3F8)).lightness));
    });
  });

  group('건물마다 창문 켜고 끄기', () {
    const ring = [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)];
    const room = BaseBuilding(id: 'r', floors: 4, ring: ring);
    const campus = BaseBuilding(id: 'c', floors: 4, ring: ring, isCampus: true);

    test('기본은 자취방 건물만', () {
      final s = housingMapStyle([room, campus]);
      expect(s.windowIds, {'r'});
    });

    test('자취방 건물은 끄고, 교내 건물은 켤 수 있다', () {
      final s = housingMapStyle([room, campus], overrides: {
        'r': const HousingBuildingOverride(buildingId: 'r', name: '', zone: HousingZone.gateBack, showWindows: false),
        'c': const HousingBuildingOverride(buildingId: 'c', name: '', zone: HousingZone.campus, showWindows: true),
      });
      expect(s.windowIds, {'c'});
      final laid = layoutBuildings([room, campus], const IsoProjection(scale: 2),
          oneRoomIds: s.oneRoomIds, windowIds: s.windowIds);
      bool has(String id) => laid.firstWhere((b) => b.building.id == id).walls.any((w) => w.windows != null);
      expect(has('r'), isFalse);
      expect(has('c'), isTrue);
    });

    test('창문 설정만 적은 문서도 되읽힌다', () {
      const o = HousingBuildingOverride(buildingId: 'r', name: '', zone: HousingZone.gateBack, showWindows: false);
      expect(HousingBuildingOverride.fromMap('r', o.toFirestore())?.showWindows, isFalse);
    });
  });

  test('이름표 끄기: 교내 공식 명칭까지 모두 뺀다', () {
    const ring = [Offset(0, 0), Offset(20, 0), Offset(20, 20), Offset(0, 20)];
    const campus = BaseBuilding(id: 'c', floors: 4, ring: ring, isCampus: true, officialName: '도서관');
    const room = BaseBuilding(id: 'r', floors: 4, ring: ring);
    const p = IsoProjection(scale: 2);
    final on = layoutBuildings([campus, room], p, displayNames: {'r': '가온빌'});
    expect(on.map((b) => b.displayName).toSet(), {'도서관', '가온빌'});
    final off = layoutBuildings([campus, room], p, displayNames: {'r': '가온빌'}, showLabels: false);
    expect(off.every((b) => b.displayName == null), isTrue);
  });
}
