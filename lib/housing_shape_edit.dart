import 'dart:math' as math;
import 'dart:ui' show Offset;

/// 개발자 모드에서 건물 외곽선을 손으로 고칠 때 쓰는 계산. 순수 함수 — 테스트 대상.
///
/// 외곽선은 지상 평면(미터) 좌표의 꼭짓점 목록이다. 편집하는 동안은 항상
/// "열린" 모양(끝점이 첫 점과 겹치지 않음)으로 다룬다. 그리는 쪽이 알아서
/// 닫는다.

/// 끝점이 첫 점을 한 번 더 적은 닫힌 외곽선이면 그 끝점을 뗀다. 지도
/// 데이터 대부분이 이렇게 닫혀 있어서, 안 떼면 같은 자리에 손잡이가 두 개
/// 겹쳐 떠 하나를 끌면 모서리가 찢어진다.
List<Offset> openRing(List<Offset> ring) {
  if (ring.length >= 2 && ring.first == ring.last) {
    return ring.sublist(0, ring.length - 1);
  }
  return List.of(ring);
}

/// [i]번 꼭짓점을 [to]로 옮긴다.
List<Offset> moveRingVertex(List<Offset> ring, int i, Offset to) => [
      for (var k = 0; k < ring.length; k++) k == i ? to : ring[k],
    ];

/// [i]번과 그다음 꼭짓점 사이 변의 한가운데에 꼭짓점을 끼운다(마지막
/// 꼭짓점이면 첫 점과의 변).
List<Offset> insertRingMidpoint(List<Offset> ring, int i) {
  final a = ring[i];
  final b = ring[(i + 1) % ring.length];
  return [...ring.sublist(0, i + 1), (a + b) / 2, ...ring.sublist(i + 1)];
}

/// [i]번 꼭짓점을 뺀다. 셋 밑으로는 면이 안 되니 null.
List<Offset>? removeRingVertex(List<Offset> ring, int i) {
  if (ring.length <= 3) return null;
  return [...ring]..removeAt(i);
}

/// 각 변의 가운데 점. "+" 손잡이를 여기에 띄운다.
List<Offset> ringMidpoints(List<Offset> ring) => [
      for (var i = 0; i < ring.length; i++)
        (ring[i] + ring[(i + 1) % ring.length]) / 2,
    ];

/// 손가락이 닿은 곳에서 가장 가까운 손잡이. [isMidpoint]면 변 가운데 "+"다.
class ShapeHandlePick {
  final bool isMidpoint;
  final int index;
  const ShapeHandlePick(this.isMidpoint, this.index);

  @override
  bool operator ==(Object other) =>
      other is ShapeHandlePick && other.isMidpoint == isMidpoint && other.index == index;

  @override
  int get hashCode => Object.hash(isMidpoint, index);

  @override
  String toString() => 'ShapeHandlePick(${isMidpoint ? 'mid' : 'vertex'} $index)';
}

/// 꼭짓점과 "+" 가운데 [touch]에 가장 가까운 것을 고른다. 작은 건물은
/// 손잡이 닿는 범위가 서로 겹쳐서, 위에 깔린 손잡이를 고르면 엉뚱한 게
/// 잡히거나 "+"가 아예 안 눌린다. 거리가 같으면 꼭짓점을 고른다.
ShapeHandlePick? pickShapeHandle(
  List<Offset> vertices,
  List<Offset> midpoints,
  Offset touch,
) {
  ShapeHandlePick? best;
  var bestD = double.infinity;
  for (var i = 0; i < vertices.length; i++) {
    final d = (vertices[i] - touch).distanceSquared;
    if (d < bestD) {
      bestD = d;
      best = ShapeHandlePick(false, i);
    }
  }
  for (var i = 0; i < midpoints.length; i++) {
    final d = (midpoints[i] - touch).distanceSquared;
    if (d < bestD) {
      bestD = d;
      best = ShapeHandlePick(true, i);
    }
  }
  return best;
}

/// 외곽선의 면적 중심. 꼭짓점 평균은 한쪽에 점이 몰리면 치우치므로 면적으로
/// 잰다. 넓이가 0에 가까우면(일직선) 꼭짓점 평균을 쓴다.
Offset ringCentroid(List<Offset> ring) {
  var a = 0.0, cx = 0.0, cy = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i], q = ring[(i + 1) % ring.length];
    final cross = p.dx * q.dy - q.dx * p.dy;
    a += cross;
    cx += (p.dx + q.dx) * cross;
    cy += (p.dy + q.dy) * cross;
  }
  if (a.abs() < 1e-9) {
    var sx = 0.0, sy = 0.0;
    for (final p in ring) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / ring.length, sy / ring.length);
  }
  return Offset(cx / (3 * a), cy / (3 * a));
}

/// 외곽선을 면적 중심 기준으로 [degrees]만큼 돌린다. 지도 좌표는 y가 남쪽이
/// +라서, 양수면 위에서 내려다볼 때 **시계 방향**이다.
List<Offset> rotateRing(List<Offset> ring, double degrees) {
  if (ring.isEmpty) return const [];
  final c = ringCentroid(ring);
  final r = degrees * math.pi / 180;
  final cosR = math.cos(r), sinR = math.sin(r);
  return [
    for (final p in ring)
      Offset(
        c.dx + (p.dx - c.dx) * cosR - (p.dy - c.dy) * sinR,
        c.dy + (p.dx - c.dx) * sinR + (p.dy - c.dy) * cosR,
      ),
  ];
}

/// 외곽선 전체를 [delta](지도 좌표, 미터)만큼 옮긴다.
List<Offset> translateRing(List<Offset> ring, Offset delta) => [
      for (final p in ring) p + delta,
    ];

/// 화면에서 ([screenDx], [screenDy]) 방향으로 [meters]만큼 가는 지도 좌표
/// 이동량. 방향키가 **화면 기준**으로 움직이게 한다 — 지도를 돌렸거나 3D
/// 시점이어도 ↑는 화면 위쪽이다. [unproject]는 화면 좌표 → 지도 좌표 역투영.
Offset screenDirToWorld(
  Offset Function(double sx, double sy) unproject,
  double screenDx,
  double screenDy,
  double meters,
) {
  final o = unproject(0, 0);
  final d = unproject(screenDx, screenDy) - o;
  final len = d.distance;
  if (len < 1e-12) return Offset.zero;
  return d / len * meters;
}
