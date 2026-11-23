import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/footpath_clean.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/stall_align.dart';

void main() {
  // 동서로 뻗은 보행로(y = 0), 그려지는 반 폭 1.5m.
  const walk = RoadLine([(0.0, 0.0), (100.0, 0.0)], 1.5);

  test('꺾은선 길이', () {
    expect(polylineLength([(0, 0), (3, 4), (3, 10)]), 11);
    expect(polylineLength([(1, 1)]), 0);
  });

  group('OSM 길의 그림자', () {
    test('길 옆에 나란히 붙어 가는 샛길은 같은 길을 두 번 그린 것이다', () {
      final beside = [(10.0, 5.0), (40.0, 6.0), (70.0, 5.0)];
      expect(roadShadowFraction(beside, [walk]), 1);
      expect(dropRoadShadows([beside], [walk]), isEmpty);
    });

    test('길에서 멀리 떨어졌거나 길을 가로지르는 샛길은 남긴다', () {
      final far = [(10.0, 30.0), (70.0, 30.0)];
      final across = [(50.0, -20.0), (50.0, 20.0)];
      expect(roadShadowFraction(far, [walk]), 0);
      expect(roadShadowFraction(across, [walk]), 0);
      expect(dropRoadShadows([far, across], [walk]), hasLength(2));
    });

    test('일부만 길 옆을 지나면(절반 이하) 남긴다', () {
      // 30m는 길 옆, 60m는 멀어진다.
      final leaving = [(0.0, 5.0), (30.0, 5.0), (30.0, 65.0)];
      expect(roadShadowFraction(leaving, [walk]), closeTo(1 / 3, 1e-9));
      expect(dropRoadShadows([leaving], [walk]), hasLength(1));
    });
  });

  group('끊긴 토막 잇기', () {
    test('마주 본 두 토막을 한 줄로 잇는다(순서·방향이 뒤섞여 있어도)', () {
      final out = joinPolylines([
        [(26.0, 0.5), (40.0, 0.0)],
        [(20.0, 0.0), (0.0, 0.0)], // 거꾸로 적힌 토막
      ]);
      expect(out, hasLength(1));
      expect(polylineLength(out.single), greaterThan(39));
      final ends = [out.single.first.$1, out.single.last.$1]..sort();
      expect(ends, [0, 40]);
    });

    test('세 토막도 차례로 이어진다', () {
      final out = joinPolylines([
        [(0.0, 0.0), (10.0, 0.0)],
        [(30.0, 0.0), (40.0, 0.0)],
        [(15.0, 0.0), (25.0, 0.0)],
      ]);
      expect(out, hasLength(1));
      expect(out.single.map((p) => p.$1), [0, 10, 15, 25, 30, 40]);
    });

    test('틈이 크거나, 옆으로 비켜 선 나란한 길은 잇지 않는다', () {
      expect(
        joinPolylines([
          [(0.0, 0.0), (10.0, 0.0)],
          [(25.0, 0.0), (40.0, 0.0)],
        ]),
        hasLength(2),
      );
      // 끝과 끝이 5m지만 옆으로 나란히(잇는 선이 90° 꺾인다).
      expect(
        joinPolylines([
          [(0.0, 0.0), (10.0, 0.0)],
          [(10.0, 5.0), (0.0, 5.0)],
        ]),
        hasLength(2),
      );
    });
  });

  group('부스러기', () {
    bool never(double x, double y) => false;

    test('어디에도 닿지 않는 짧은 토막은 뺀다', () {
      final scrap = [(0.0, 0.0), (12.0, 0.0)];
      expect(dropIsolatedPaths([scrap], anchored: never), isEmpty);
    });

    test('길면 남긴다', () {
      final long = [(0.0, 0.0), (45.0, 0.0)];
      expect(dropIsolatedPaths([long], anchored: never), hasLength(1));
    });

    test('짧아도 한 끝이 도로·포장면이나 다른 샛길에 닿으면 남긴다', () {
      final short = [(0.0, 0.0), (12.0, 0.0)];
      expect(
        dropIsolatedPaths([short], anchored: (x, y) => x > 10),
        hasLength(1),
      );
      final other = [(13.0, 2.0), (13.0, 60.0)];
      expect(dropIsolatedPaths([short, other], anchored: never), hasLength(2));
    });
  });

  group('지도 데이터', () {
    late CampusBase base;
    late List<RoadLine> roads;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      base = await CampusBase.load();
      roads = [
        for (final r in await CampusBase.loadOsmRoads())
          RoadLine(
            [for (final p in r.points) (p.dx, p.dy)],
            osmRoadDrawnHalfWidth(r.kind, r.widthM),
          ),
      ];
    });

    test('샛길에 OSM 길의 그림자가 없다', () {
      for (final l in base.terrain.traced.footpaths) {
        final line = [for (final p in l) (p.dx, p.dy)];
        expect(roadShadowFraction(line, roads), lessThan(0.6), reason: '${l.first}');
      }
    });

    test('포장면은 큰 덩어리 몇 개다(건물·글씨 자리마다 뜯긴 조각이 아니다)', () {
      final t = base.terrain.traced;
      expect(t.pavementOutlines.length, inInclusiveRange(5, 40));
      double area(List<Offset> r) {
        var a = 0.0;
        for (var i = 0; i < r.length; i++) {
          final p = r[i], q = r[(i + 1) % r.length];
          a += p.dx * q.dy - q.dx * p.dy;
        }
        return a.abs() / 2;
      }

      // 가장 큰 덩어리가 교내 중심부를 통째로 덮는다(10만㎡ 이상).
      expect(t.pavementOutlines.map(area).reduce((a, b) => a > b ? a : b), greaterThan(100000));
    });
  });
}
