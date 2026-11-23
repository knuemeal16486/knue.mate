import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:knue_mate/housing_iso.dart';

/// 꺾은선들의 모든 점.
Iterable<Offset> _points(List<List<Offset>> lines) => lines.expand((l) => l);

void main() {
  group('바닥 상자', () {
    // 테니스장 실측과 같은 꼴: 23.8×12.7m, 58° 기울어짐.
    const box = GroundBox(Offset(700, 350), 23.8, 12.7, 1.012);

    test('모서리는 중심에서 대각선 절반만큼 떨어져 있다', () {
      final half = math.sqrt(23.8 * 23.8 + 12.7 * 12.7) / 2;
      for (final c in box.corners) {
        expect((c - box.center).distance, closeTo(half, 1e-9));
      }
      // 긴 변 길이.
      expect((box.corners[1] - box.corners[0]).distance, closeTo(23.8, 1e-9));
      expect((box.corners[2] - box.corners[1]).distance, closeTo(12.7, 1e-9));
    });

    test('기울어진 상자의 안팎을 가린다', () {
      expect(box.contains(box.center), isTrue);
      expect(box.contains(box.at(11, 6)), isTrue);
      expect(box.contains(box.at(13, 0)), isFalse);
      expect(box.contains(box.at(13, 0), margin: 2), isTrue);
      // 축에 나란한 경계상자 안이지만 기울어진 상자 밖인 점.
      expect(box.contains(box.center + const Offset(9, -8)), isFalse);
    });

    test('json에서 읽는다', () {
      final b = GroundBox.fromJson({
        'c': [10, -20.5],
        'l': 30,
        'w': 15.5,
        'a': 0.5,
      });
      expect(b.center, const Offset(10, -20.5));
      expect(b.length, 30);
      expect(b.width, 15.5);
      expect(b.angle, 0.5);
    });
  });

  group('코트 선', () {
    test('크기로 종류를 가린다', () {
      expect(courtKindOf(const GroundBox(Offset.zero, 86, 47, 0)), CourtKind.soccer);
      expect(courtKindOf(const GroundBox(Offset.zero, 23.8, 12.7, 0)), CourtKind.tennis);
      // 풋살장·농구장.
      expect(courtKindOf(const GroundBox(Offset.zero, 41.4, 26.8, 0)), CourtKind.court);
      expect(courtKindOf(const GroundBox(Offset.zero, 29.1, 17.3, 0)), CourtKind.court);
    });

    test('어떤 종류든 선이 코트 밖으로 나가지 않는다', () {
      for (final b in const [
        GroundBox(Offset(568, 419), 86.2, 46.9, -0.244),
        GroundBox(Offset(700, 350), 23.8, 12.7, 1.012),
        GroundBox(Offset(653, -43), 41.4, 26.8, -0.454),
      ]) {
        final lines = courtLines(b);
        expect(lines, isNotEmpty);
        for (final p in _points(lines)) {
          expect(b.contains(p, margin: 1e-6), isTrue, reason: '$p');
        }
      }
    });

    test('축구장: 테두리·중앙선·센터서클·양쪽 벌칙구역과 골구역', () {
      final lines = courtLines(const GroundBox(Offset.zero, 100, 64, 0));
      expect(lines, hasLength(7));
      // 중앙선은 가운데를 세로로 가른다.
      expect(lines[1].first.dx, closeTo(0, 1e-9));
      expect(lines[1].last.dx, closeTo(0, 1e-9));
      // 센터서클은 중심에서 같은 거리.
      final r = (lines[2].first).distance;
      for (final p in lines[2]) {
        expect(p.distance, closeTo(r, 1e-9));
      }
      // 벌칙구역이 골구역보다 크고 둘 다 골라인에 붙어 있다.
      double width(List<Offset> rect) =>
          rect.map((p) => p.dx).reduce(math.max) - rect.map((p) => p.dx).reduce(math.min);
      expect(width(lines[3]), greaterThan(width(lines[4])));
    });

    test('테니스: 테두리·단식 사이드라인 2·서비스라인 2·센터라인·네트', () {
      final lines = courtLines(const GroundBox(Offset.zero, 23.8, 12.7, 0));
      expect(lines, hasLength(7));
      // 네트는 한가운데.
      expect(lines.last.first.dx, closeTo(0, 1e-9));
      // 센터 서비스라인은 서비스라인 사이만 잇는다(끝까지 가지 않는다).
      final center = lines[5];
      expect(center.first.dy, closeTo(0, 1e-9));
      expect((center.last - center.first).distance, lessThan(23.8 * 0.93));
    });
  });

  group('선을 면으로', () {
    test('선분마다 폭만큼의 사각형 하나', () {
      final quads = lineQuads([
        [const Offset(0, 0), const Offset(10, 0), const Offset(10, 5)],
      ], 0.4);
      expect(quads, hasLength(2));
      // 첫 사각형: 길이 10(+양 끝 반 폭씩) × 폭 0.4.
      final q = quads.first;
      final ys = q.map((p) => p.dy).toList()..sort();
      final xs = q.map((p) => p.dx).toList()..sort();
      expect(ys.last - ys.first, closeTo(0.4, 1e-9));
      expect(xs.last - xs.first, closeTo(10.4, 1e-9));
    });

    test('모든 사각형이 같은 방향으로 감긴다(겹쳐도 구멍이 안 난다)', () {
      double signed(List<Offset> r) {
        var a = 0.0;
        for (var i = 0; i < r.length; i++) {
          final p = r[i], q = r[(i + 1) % r.length];
          a += p.dx * q.dy - q.dx * p.dy;
        }
        return a;
      }

      final quads = lineQuads(courtLines(const GroundBox(Offset.zero, 86, 47, 0.7)), 0.45);
      final sign = signed(quads.first).sign;
      for (final q in quads) {
        expect(signed(q).sign, sign);
      }
    });

    test('길이 0인 선분은 건너뛴다', () {
      expect(lineQuads([
        [const Offset(1, 1), const Offset(1, 1)],
      ], 0.4), isEmpty);
    });
  });

  group('주차 구획 띠', () {
    test('양쪽 줄 둘에 가로대가 간격마다', () {
      // 25m 띠, 2.5m 간격 → 칸 10개, 가로대 11개.
      final segs = stallLadder(const GroundBox(Offset.zero, 25, 3, 0));
      expect(segs, hasLength(2 + 11));
      // 양쪽 줄은 띠 길이 그대로.
      expect((segs[0].$2 - segs[0].$1).distance, closeTo(25, 1e-9));
      // 가로대는 띠 폭 그대로.
      for (final s in segs.skip(2)) {
        expect((s.$2 - s.$1).distance, closeTo(3, 1e-9));
      }
    });

    test('자투리 칸이 남지 않게 끝에 맞춰 고르게 나눈다', () {
      final segs = stallLadder(const GroundBox(Offset.zero, 11, 3, 0));
      final us = segs.skip(2).map((s) => s.$1.dx).toList()..sort();
      expect(us.first, closeTo(-5.5, 1e-9));
      expect(us.last, closeTo(5.5, 1e-9));
      final gap = us[1] - us[0];
      for (var i = 1; i < us.length; i++) {
        expect(us[i] - us[i - 1], closeTo(gap, 1e-9));
      }
    });

    test('짧은 띠도 칸 하나는 그린다', () {
      expect(stallLadder(const GroundBox(Offset.zero, 1, 3, 0)), hasLength(4));
    });
  });

  group('도로 높이로 투영', () {
    test('평면 시점에서는 바닥 투영과 같다', () {
      const p = IsoProjection(topDown: true);
      expect(projectOnRoadLevel(p, 300, -200), p.project(300, -200));
    });

    test('기울어진 시점에서는 도로와 똑같이 언덕 높이만큼 뜬다', () {
      const p = IsoProjection();
      // 언덕 위 한 점(손 모델의 높이가 0이 아닌 곳).
      const x = 480.0, y = -250.0;
      final h = CampusElevation.elevationAt(x, y);
      expect(h, greaterThan(1));
      final lifted = projectOnRoadLevel(p, x, y);
      expect(lifted, p.project(x, y, h * kRoadLift));
      expect(lifted.dy, lessThan(p.project(x, y).dy));
      // 같은 점을 지나는 도로의 점과 일치한다.
      final road = projectOsmRoads(
        const [OsmRoad(kind: 'road', widthM: 5, points: [Offset(x, y), Offset(x + 10, y)])],
        p,
      );
      final start = road.lanes.single.path.computeMetrics().first.getTangentForOffset(0)!.position;
      expect((start - lifted).distance, lessThan(1e-6));
    });
  });

  group('지도 데이터', () {
    late CampusBase base;
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      base = await CampusBase.load();
    });

    test('코트·주차 띠·샛길이 들어 있다', () {
      final t = base.terrain.traced;
      // 테니스 9면(이름표에 가린 2면 포함) + 축구장 2 + 풋살·농구 4.
      expect(t.courts, hasLength(15));
      expect(t.courts.where((b) => courtKindOf(b) == CourtKind.tennis), hasLength(9));
      expect(t.courts.where((b) => courtKindOf(b) == CourtKind.soccer), hasLength(2));
      expect(t.stallStrips.length, greaterThan(200));
      expect(t.footpaths.length, greaterThan(50));
    });

    test('주차 띠는 폭이 사다리 한 줄(2~7.5m)이고 길쭉하다', () {
      // 잴 때는 길이가 폭의 1.6배 이상인 것만 받는다. 그 뒤 모서리·도로에
      // 겹친 끝을 (절반까지) 줄이므로 몇 개는 그보다 짧아진다.
      for (final b in base.terrain.traced.stallStrips) {
        expect(b.width, inInclusiveRange(1.8, 7.5));
        expect(b.length / b.width, greaterThanOrEqualTo(0.8));
      }
    });

    test('코트 자리의 뭉친 잔디·선 얼룩 대신 반듯한 코트를 그린다', () {
      const proj = IsoProjection(topDown: true);
      final iso = projectTerrain(base.terrain, proj);
      // 테니스 코트 한가운데는 초록(코트 면)이다.
      final court = base.terrain.traced.courts
          .firstWhere((b) => courtKindOf(b) == CourtKind.tennis);
      final c = proj.project(court.center.dx, court.center.dy);
      expect(iso.greens.contains(c), isTrue);
      // 네트 선(코트 한가운데를 지난다)이 선 층에 있다.
      expect(iso.fieldLines.contains(c), isTrue);
      // 예전 주차장 면은 띠가 대신한다.
      expect(iso.parking.getBounds().isEmpty, isTrue);
      expect(iso.parkingStalls.getBounds().isEmpty, isFalse);
      expect(iso.footpaths.getBounds().isEmpty, isFalse);
    });
  });
}
