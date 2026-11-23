import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';
import 'package:knue_mate/stall_align.dart';

const _deg = math.pi / 180;

void main() {
  // 동서로 곧게 뻗은 도로(y = 0), 그려지는 반 폭 3m.
  const road = RoadLine([(0.0, 0.0), (100.0, 0.0)], 3);

  group('도로 폭', () {
    test('종류별 최소 폭을 보장한다', () {
      expect(osmRoadBaseWidth('road', 4.5), 5.2);
      expect(osmRoadBaseWidth('road', 7), 7);
      expect(osmRoadBaseWidth('major', 6), 8.5);
      expect(osmRoadBaseWidth('walk', 2.2), 2.6);
    });

    test('그려지는 반 폭은 폭 × 0.75 / 0.7071의 절반', () {
      expect(osmRoadDrawnHalfWidth('road', 4.5), closeTo(5.2 * 0.75 / 0.7071 / 2, 1e-9));
    });
  });

  group('선의 방향 차이', () {
    test('180° 돌아도 같은 선이다', () {
      expect(lineAngleDiff(0.1, 0.1 + math.pi), closeTo(0, 1e-9));
      expect(lineAngleDiff(1.5, -1.5), closeTo(math.pi - 3.0, 1e-9));
      expect(lineAngleDiff(0, 0.2), closeTo(0.2, 1e-9));
      expect(lineAngleDiff(0.2, 0), closeTo(-0.2, 1e-9));
    });
  });

  group('주차 띠를 도로에 맞춘다', () {
    test('조금 비뚤고 떠 있는 띠를 나란히 돌려 가장자리에 붙인다', () {
      // 길 가장자리(y=3)에서 0.9m 떠 있고 5° 비뚤다.
      final s = alignStallStrip(
        (cx: 50, cy: 6.4, len: 20, wid: 5, ang: 5 * _deg),
        [road],
      );
      expect(s.ang, closeTo(0, 1e-9));
      // 길 쪽 변이 도로 가장자리에 딱 붙는다: 중심 = 3 + 5/2.
      expect(s.cy, closeTo(5.5, 1e-9));
      expect(s.cx, closeTo(50, 1e-9));
      expect(s.len, 20);
      expect(s.wid, 5);
    });

    test('길에 걸친 띠는 밀어내고, 길 반대편 띠는 그쪽에 붙인다', () {
      final over = alignStallStrip((cx: 50, cy: 4, len: 20, wid: 5, ang: 0), [road]);
      expect(over.cy, closeTo(5.5, 1e-9));
      final other = alignStallStrip((cx: 50, cy: -6, len: 20, wid: 5, ang: 0), [road]);
      expect(other.cy, closeTo(-5.5, 1e-9));
    });

    test('길에서 한 줄 떨어진 띠는 방향만 맞추고 옮기지 않는다', () {
      final s = alignStallStrip(
        (cx: 50, cy: 16, len: 20, wid: 5, ang: -4 * _deg),
        [road],
      );
      expect(s.ang, closeTo(0, 1e-9));
      expect(s.cy, 16);
    });

    test('방향이 많이 다르거나 먼 도로에는 맞추지 않는다', () {
      const skew = (cx: 50.0, cy: 6.0, len: 20.0, wid: 5.0, ang: 40 * _deg);
      expect(alignStallStrip(skew, [road]), skew);
      const far = (cx: 50.0, cy: 60.0, len: 20.0, wid: 5.0, ang: 0.02);
      expect(alignStallStrip(far, [road]), far);
      expect(alignStallStrip(far, const []), far);
    });

    test('여러 구간 중 나란하고 가장 가까운 구간을 고른다', () {
      // ㄱ자로 꺾인 길: 동쪽으로 가다 남쪽으로.
      const bent = RoadLine([(0.0, 0.0), (100.0, 0.0), (100.0, 100.0)], 3);
      final s = alignStallStrip(
        (cx: 106, cy: 50, len: 20, wid: 5, ang: 88 * _deg),
        [bent],
      );
      expect(lineAngleDiff(s.ang, math.pi / 2), closeTo(0, 1e-9));
      expect(s.cx, closeTo(105.5, 1e-9));
    });

    test('방향 값은 원래 값 근처에 머문다(반 바퀴 튀지 않는다)', () {
      // 도로 점 순서가 반대(서쪽으로)여도 띠 방향은 3°만 돈다.
      const west = RoadLine([(100.0, 0.0), (0.0, 0.0)], 3);
      final s = alignStallStrip((cx: 50, cy: 6, len: 20, wid: 5, ang: 3 * _deg), [west]);
      expect(s.ang, closeTo(0, 1e-9));
    });

    test('구간 끝 너머에 있는 띠는 가장자리에 붙이지 않는다', () {
      final s = alignStallStrip((cx: 115, cy: 6.5, len: 20, wid: 5, ang: 0.05), [road]);
      expect(s.ang, closeTo(0, 1e-9));
      expect(s.cy, 6.5);
    });
  });

  group('주차장 통로', () {
    test('마주 보는 두 줄 사이를 통로로 낸다', () {
      final aisles = stallAisles([
        (cx: 0, cy: 0, len: 30, wid: 5, ang: 0),
        (cx: 5, cy: 11, len: 20, wid: 5, ang: 0),
      ]);
      expect(aisles, hasLength(1));
      final a = aisles.single;
      // 사이 6m, 가운데 y = 2.5 + 3.
      expect(a.wid, closeTo(6, 1e-9));
      expect(a.cy, closeTo(5.5, 1e-9));
      // 길이는 두 줄을 합친 범위(-15 ~ 15).
      expect(a.len, closeTo(30, 1e-9));
      expect(a.cx, closeTo(0, 1e-9));
    });

    test('기울어진 줄도 같은 식으로', () {
      const ang = 0.6;
      final c = math.cos(ang), s = math.sin(ang);
      final aisles = stallAisles([
        (cx: 10, cy: 20, len: 30, wid: 5, ang: ang),
        (cx: 10 + 11 * s, cy: 20 - 11 * c, len: 30, wid: 5, ang: ang),
      ]);
      expect(aisles, hasLength(1));
      expect(aisles.single.cx, closeTo(10 + 5.5 * s, 1e-9));
      expect(aisles.single.cy, closeTo(20 - 5.5 * c, 1e-9));
      expect(aisles.single.wid, closeTo(6, 1e-9));
    });

    test('너무 붙었거나 멀거나, 비뚤거나, 엇갈린 줄은 통로가 아니다', () {
      const a = (cx: 0.0, cy: 0.0, len: 30.0, wid: 5.0, ang: 0.0);
      expect(stallAisles([a, (cx: 0, cy: 6, len: 30, wid: 5, ang: 0)]), isEmpty);
      expect(stallAisles([a, (cx: 0, cy: 20, len: 30, wid: 5, ang: 0)]), isEmpty);
      expect(stallAisles([a, (cx: 0, cy: 11, len: 30, wid: 5, ang: 0.3)]), isEmpty);
      expect(stallAisles([a, (cx: 40, cy: 11, len: 30, wid: 5, ang: 0)]), isEmpty);
    });
  });

  group('겹친 띠 정리', () {
    test('나란히 겹친 토막은 한 줄로 잇는다(폭·옆 위치도 합친 범위)', () {
      final out = mergeOverlappingStrips([
        (cx: 0, cy: 0, len: 20, wid: 4, ang: 0),
        (cx: 14, cy: 0.5, len: 12, wid: 5, ang: 0.01),
      ]);
      expect(out, hasLength(1));
      final m = out.single;
      // 길이: -10 ~ 20.
      expect(m.len, closeTo(30, 1e-9));
      expect(m.cx, closeTo(5, 1e-9));
      // 폭: -2 ~ 3.
      expect(m.wid, closeTo(5, 1e-9));
      expect(m.cy, closeTo(0.5, 1e-9));
      expect(m.ang, 0);
    });

    test('끝이 떨어져 있거나 옆 줄이면 합치지 않는다', () {
      const a = (cx: 0.0, cy: 0.0, len: 20.0, wid: 4.0, ang: 0.0);
      expect(mergeOverlappingStrips([a, (cx: 25, cy: 0, len: 10, wid: 4, ang: 0)]), hasLength(2));
      expect(mergeOverlappingStrips([a, (cx: 0, cy: 5, len: 20, wid: 4, ang: 0)]), hasLength(2));
    });

    test('엇갈려 겹친 짧은 띠는 빼고, 끝만 닿은 띠는 둔다', () {
      const a = (cx: 0.0, cy: 0.0, len: 20.0, wid: 4.0, ang: 0.0);
      final inside = mergeOverlappingStrips([
        (cx: 3, cy: 1, len: 8, wid: 3, ang: 0.8),
        a,
      ]);
      expect(inside, [a]);
      final corner = mergeOverlappingStrips([
        a,
        (cx: 9, cy: 6, len: 10, wid: 4, ang: math.pi / 2),
      ]);
      expect(corner, hasLength(2));
    });

    test('다른 띠나 도로 위로 나온 끝만 줄인다', () {
      // x < 0이 막힌 자리.
      final s = trimStripEnds(
        (cx: 3, cy: 0, len: 10, wid: 3, ang: 0),
        (x, y) => x < 0,
      );
      // -2 ~ 8이던 것이 0 ~ 8로(0.25m 걸음).
      expect(s.len, closeTo(8, 0.26));
      expect(s.cx + s.len / 2, closeTo(8, 1e-9));
      expect(s.cx - s.len / 2, inInclusiveRange(0, 0.25));
    });

    test('절반 넘게 줄여야 하면 손대지 않는다', () {
      const s = (cx: 3.0, cy: 0.0, len: 10.0, wid: 3.0, ang: 0.0);
      expect(trimStripEnds(s, (x, y) => x < 5), s);
      expect(trimStripEnds(s, (x, y) => false), s);
    });

    test('모서리에서 만나는 짧은 줄의 끝을 긴 줄 밖으로 뺀다', () {
      final out = trimStripOverlaps([
        (cx: 0, cy: 0, len: 30, wid: 4, ang: 0),
        // 세로 줄: y -1 ~ 11, 위 끝이 가로 줄(y ±2) 안에 들어가 있다.
        (cx: 10, cy: 5, len: 12, wid: 4, ang: math.pi / 2),
      ], const []);
      expect(out.first.len, 30);
      final v = out.last;
      expect(v.cy - v.len / 2, inInclusiveRange(2, 2.25));
      expect(v.cy + v.len / 2, closeTo(11, 1e-9));
    });

    test('가로지르는 도로 위로 나온 끝을 줄이되, 제 도로 가장자리는 건드리지 않는다', () {
      // 띠는 동서 도로(y=0) 남쪽 가장자리에 붙어 있고, 서쪽 끝이 남북 도로(x=0) 위.
      const cross = RoadLine([(0.0, -50.0), (0.0, 50.0)], 3);
      final out = trimStripOverlaps([
        (cx: 8, cy: 5.5, len: 20, wid: 5, ang: 0),
      ], [road, cross]);
      final s = out.single;
      expect(s.cx - s.len / 2, inInclusiveRange(2.8, 3.1));
      expect(s.cx + s.len / 2, closeTo(18, 1e-9));
      expect(s.cy, 5.5);
    });
  });

  group('횡단보도를 도로에 맞춘다', () {
    test('차도 위의 것은 중심선으로 옮기고 도로를 가로지르게 돌린다', () {
      // 도로(y=0, 반 폭 3) 가장자리 근처에, 방향은 캡처처럼 0°.
      final c = snapCrosswalk((cx: 40, cy: 2.5, wid: 4.5, len: 8.7, angDeg: 0), [road])!;
      expect(c.cx, closeTo(40, 1e-9));
      expect(c.cy, closeTo(0, 1e-9));
      // 줄무늬가 늘어선 방향 = 도로에 수직, 늘어선 길이 = 도로 폭.
      expect(lineAngleDiff(c.angDeg * _deg, math.pi / 2), closeTo(0, 1e-9));
      expect(c.len, closeTo(6, 1e-9));
      expect(c.wid, 3);
    });

    test('비스듬한 도로에서는 그 도로에 수직', () {
      const diag = RoadLine([(0.0, 0.0), (100.0, 100.0)], 3);
      final c = snapCrosswalk((cx: 51, cy: 49, wid: 4, len: 8, angDeg: 90), [diag])!;
      expect(c.cx, closeTo(50, 1e-9));
      expect(c.cy, closeTo(50, 1e-9));
      expect(lineAngleDiff(c.angDeg * _deg, 135 * _deg), closeTo(0, 1e-9));
    });

    test('차도 밖에 떠 있는 것은 버린다(계단·주차선을 잘못 읽은 것)', () {
      expect(snapCrosswalk((cx: 40, cy: 9, wid: 4, len: 8, angDeg: 0), [road]), isNull);
      expect(snapCrosswalk((cx: 40, cy: 2, wid: 4, len: 8, angDeg: 0), const []), isNull);
    });

    test('같은 자리에 겹친 것은 하나만 남긴다', () {
      final out = snapCrosswalks([
        (cx: 40, cy: 1, wid: 4, len: 8, angDeg: 0),
        (cx: 42, cy: -2, wid: 4, len: 8, angDeg: 90),
        (cx: 70, cy: 0, wid: 4, len: 8, angDeg: 0),
        (cx: 40, cy: 30, wid: 4, len: 8, angDeg: 0),
      ], [road]);
      expect(out, hasLength(2));
      expect(out.map((c) => c.cx), [40, 70]);
    });
  });

  test('코트 위에 놓인 띠는 뺀다', () {
    const court = (cx: 0.0, cy: 0.0, len: 24.0, wid: 13.0, ang: 1.0);
    const on = (cx: 2.0, cy: 1.0, len: 8.0, wid: 3.0, ang: 1.0);
    const off = (cx: 30.0, cy: 0.0, len: 8.0, wid: 3.0, ang: 1.0);
    expect(dropStripsOnCourts([on, off], [court]), [off]);
    expect(dropStripsOnCourts([on, off], const []), [on, off]);
  });

  group('지도 데이터', () {
    late CampusBase base;
    late List<RoadLine> roads;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      base = await CampusBase.load();
      roads = [
        for (final r in await CampusBase.loadOsmRoads())
          if (isStallRoad(r.kind, r.widthM))
            RoadLine(
              [for (final p in r.points) (p.dx, p.dy)],
              osmRoadDrawnHalfWidth(r.kind, r.widthM),
            ),
      ];
    });

    test('에셋의 주차 띠는 도로와 나란하고, 길가의 띠는 가장자리에 붙어 있다', () {
      // 에셋은 좌표 0.01m·각도 0.0001rad로 반올림돼 있다.
      var parallel = 0, flush = 0;
      for (final b in base.terrain.traced.stallStrips) {
        var isParallel = false, isFlush = false;
        for (final r in roads) {
          for (var i = 0; i + 1 < r.points.length; i++) {
            final (ax, ay) = r.points[i];
            final (bx, by) = r.points[i + 1];
            final len = math.sqrt(math.pow(bx - ax, 2) + math.pow(by - ay, 2));
            if (len < 1) continue;
            final turn = lineAngleDiff(b.angle, math.atan2(by - ay, bx - ax));
            if (turn.abs() > 2e-4) continue;
            final tx = (bx - ax) / len, ty = (by - ay) / len;
            final dx = b.center.dx - ax, dy = b.center.dy - ay;
            final along = dx * tx + dy * ty;
            if (along < -b.length / 2 || along > len + b.length / 2) continue;
            final off = (-dx * ty + dy * tx).abs();
            if (off > 25) continue;
            isParallel = true;
            if ((off - (r.halfWidth + b.width / 2)).abs() < 0.05) isFlush = true;
          }
        }
        if (isParallel) parallel++;
        if (isFlush) flush++;
      }
      printOnFailure('나란한 띠 $parallel, 붙은 띠 $flush');
      expect(parallel, greaterThan(100));
      expect(flush, greaterThan(30));
    });

    test('주차 띠의 중심이 차도 위에 놓이지 않는다', () {
      for (final b in base.terrain.traced.stallStrips) {
        for (final r in roads) {
          for (var i = 0; i + 1 < r.points.length; i++) {
            final (ax, ay) = r.points[i];
            final (bx, by) = r.points[i + 1];
            final dx = bx - ax, dy = by - ay;
            final len = math.sqrt(dx * dx + dy * dy);
            if (len < 1) continue;
            // 나란한 도로만 본다(가로지르는 길과의 교차는 끝 다듬기 몫).
            if (lineAngleDiff(b.angle, math.atan2(dy, dx)).abs() > 15 * _deg) continue;
            final along = ((b.center.dx - ax) * dx + (b.center.dy - ay) * dy) / len;
            if (along < 0 || along > len) continue;
            final off = (-(b.center.dx - ax) * dy + (b.center.dy - ay) * dx).abs() / len;
            if (off < 0.3) continue; // 어느 쪽인지 알 수 없어 그대로 둔 것
            expect(off, greaterThan(r.halfWidth - 0.05), reason: '${b.center}');
          }
        }
      }
    });

    test('횡단보도는 모두 차도 위에 있고 그 도로를 가로지른다', () {
      final cws = base.terrain.traced.crosswalks;
      expect(cws.length, inInclusiveRange(15, 60));
      for (final c in cws) {
        final again = snapCrosswalk(
          (cx: c.center.dx, cy: c.center.dy, wid: c.width, len: c.length, angDeg: c.angleDeg),
          roads,
        );
        expect(again, isNotNull, reason: '${c.center}');
        // 에셋은 0.1m·0.1°로 반올림돼 있다.
        expect((again!.cx - c.center.dx).abs(), lessThan(0.2));
        expect((again.cy - c.center.dy).abs(), lessThan(0.2));
        expect(
          lineAngleDiff(c.angleDeg * _deg, again.angDeg * _deg).abs(),
          lessThan(0.5 * _deg),
        );
      }
    });

    test('코트 위에는 주차 띠가 없다', () {
      final t = base.terrain.traced;
      for (final s in t.stallStrips) {
        expect(t.courts.any((c) => c.contains(s.center)), isFalse, reason: '${s.center}');
      }
    });

    test('마주 보는 주차 줄 사이에 통로가 깔린다', () {
      final t = base.terrain.traced;
      expect(t.stallAisles.length, greaterThan(20));
      for (final a in t.stallAisles) {
        expect(a.width, inInclusiveRange(3, 9));
      }
    });
  });
}
