import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/campus_greenery.dart';
import 'package:knue_mate/housing_iso.dart';

void main() {
  late CampusBase base;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    base = await CampusBase.load();
  });

  group('위성사진 기반 캠퍼스 녹지·수목 생성', () {
    test('교내 산림·구릉·잔디 구역과 수목이 정상 로드된다', () {
      expect(base.terrain.campusGreenZones, isNotEmpty);
      expect(base.terrain.campusTrees.length, greaterThan(150));
      final kinds = base.terrain.campusTrees.map((t) => t.kind).toSet();
      expect(
        kinds,
        containsAll([
          CampusTreeKind.pine,
          CampusTreeKind.broadleaf,
          CampusTreeKind.olive,
          CampusTreeKind.street,
        ]),
      );
    });

    test('정문 로터리 중앙 화단과 시그니처 수목 군락이 배치된다', () {
      expect(
        base.terrain.roundaboutIslands.any(
          (ri) => (ri.center - kRoundaboutCenter).distance < 1.0,
        ),
        isTrue,
      );
      final islandTrees = base.terrain.campusTrees
          .where(
            (t) =>
                (t.position - kRoundaboutCenter).distance <=
                kRoundaboutIslandRadius,
          )
          .length;
      expect(islandTrees, greaterThanOrEqualTo(5));
    });

    test('수목은 건물·코트·수면과 겹치지 않는다', () {
      for (final tree in base.terrain.campusTrees) {
        final p = tree.position;
        for (final b in base.buildings) {
          expect(
            pointInPolygon(p, b.ring),
            isFalse,
            reason: '수목 $p 가 건물 ${b.id}(${b.officialName}) 안에 놓임',
          );
        }
        for (final c in base.terrain.traced.courts) {
          expect(
            c.contains(p),
            isFalse,
            reason: '수목 $p 가 코트 ${c.center} 위에 놓임',
          );
        }
        for (final w in base.terrain.traced.waterAreas) {
          expect(
            pointInPolygon(p, w),
            isFalse,
            reason: '수목 $p 가 수면 위에 놓임',
          );
        }
      }
    });

    test('아이소메트릭·평면 투영 모두 녹지·트랙·수목 Path를 생성한다', () {
      for (final proj in const [
        IsoProjection(scale: 2.0, topDown: false),
        IsoProjection(scale: 2.0, topDown: true),
      ]) {
        final iso = projectTerrain(base.terrain, proj);
        expect(iso.campusPineForest.getBounds().isEmpty, isFalse);
        expect(iso.campusWoodland.getBounds().isEmpty, isFalse);
        expect(iso.campusLawns.getBounds().isEmpty, isFalse);
        expect(iso.athleticStadiumTrack.getBounds().isEmpty, isFalse);
        expect(iso.athleticStadiumLanes.getBounds().isEmpty, isFalse);
        expect(iso.tennisCourts.getBounds().isEmpty, isFalse);
        expect(iso.roundaboutIslandsCombined.getBounds().isEmpty, isFalse);
        expect(iso.treeShadowsPath.getBounds().isEmpty, isFalse);
        expect(iso.treePineBasePath.getBounds().isEmpty, isFalse);
        expect(iso.treeZelkovaBasePath.getBounds().isEmpty, isFalse);
        expect(iso.treeStreetBasePath.getBounds().isEmpty, isFalse);
        // 평면 시점에서는 나무 줄기를 숨기고, 2.5D 시점에서는 그린다.
        expect(iso.treeTrunksPath.getBounds().isEmpty, proj.topDown);
      }
    });

    test('위성사진 기준 보완 건물(다감관·청람천문대·대운동장 본부석)이 정확히 반영됐다', () {
      BaseBuilding byName(String name) =>
          base.buildings.firstWhere((b) => b.officialName == name);

      final dagam = byName('다감관');
      expect(dagam.floors, 10);
      expect(dagam.center.dy, lessThan(-480));

      final obs = byName('청람천문대');
      expect(obs.center.dy, greaterThan(300)); // 남쪽 언덕

      final grandstand = byName('대운동장 본부석');
      expect(grandstand.center.dy, lessThan(-200)); // 대운동장 남서측 직선주로 옆
    });
  });
}
