// 주차 구획 띠를 도로에 맞춰 정렬한다. 순수 Dart(Flutter 없음) — 앱과
// `tool/trace_map.dart`가 같이 쓴다.
//
// 띠는 캡처의 사다리 얼룩에 직사각형을 맞춰(주성분) 잰 것이라, 방향이 띠마다
// 몇 도씩 흔들리고 위치도 1~2m 어긋난다. 반면 도로는 OSM 중심선으로 반듯하게
// 긋는다. 둘을 따로 재면 주차칸이 길과 비뚤게 놓이고, 길에 걸치거나 떠 보인다.
// 실제 주차칸은 길을 따라 그어져 있으니, 가까운 도로의 방향·가장자리에 맞춘다.
import 'dart:math' as math;

/// OSM 도로를 그릴 때 종류별로 보장하는 최소 폭(m). 앱의 `projectOsmRoads`가
/// 이 값으로 굵기를 정한다.
double osmRoadBaseWidth(String kind, double widthM) {
  if (kind == 'major') return math.max(widthM, 8.5);
  if (kind == 'walk' || kind == 'path' || kind == 'steps') {
    return math.max(widthM, 2.6);
  }
  return math.max(widthM, 5.2);
}

/// 도로 굵기에 곱하는 값(화면 굵기 = 폭 × 배율 × 이 값).
const double kOsmRoadSquash = 0.75;

/// 지도에 그려지는 도로 노면의 반 폭(m, 평면 시점 기준).
///
/// 평면 시점은 1m가 `0.7071 × 배율` 픽셀이고 굵기는 `폭 × 배율 × 0.75` 픽셀이라
/// 그려진 폭은 `폭 × 0.75 / 0.7071`m다.
double osmRoadDrawnHalfWidth(String kind, double widthM) =>
    osmRoadBaseWidth(kind, widthM) * kOsmRoadSquash / 0.7071 / 2;

/// 주차칸이 붙을 만한 길인지 — 차도(road·major)와, 보행로로 적혀 있어도
/// 차가 다닐 폭(4m 이상)인 교내 길.
bool isStallRoad(String kind, double widthM) =>
    kind == 'road' || kind == 'major' || (kind == 'walk' && widthM >= 4);

/// 도로 한 줄 — 중심선과 그려지는 반 폭(m).
class RoadLine {
  final List<(double, double)> points;
  final double halfWidth;
  const RoadLine(this.points, this.halfWidth);
}

/// 주차 구획 띠 — 중심·긴 변·짧은 변(m)·긴 변의 방향(라디안).
typedef StallStrip = ({double cx, double cy, double len, double wid, double ang});

/// 방향 [a]에서 [b]까지의 차이를 (-π/2, π/2]로. 선은 앞뒤가 없어 180°가 같다.
double lineAngleDiff(double a, double b) {
  var d = (b - a) % math.pi;
  if (d > math.pi / 2) d -= math.pi;
  return d;
}

/// [s]를 가까운 도로에 맞춘 띠. 맞출 도로가 없으면 [s] 그대로.
///
/// - **방향**: 띠와 [maxAngle] 안으로 나란하고 [reach]m 안에 있는 도로 구간 중
///   가장 가까운 것의 방향으로 돌린다(중심은 제자리). 길에서 한 줄 떨어진
///   둘째 줄 주차칸도 이걸로 첫 줄과 나란해진다.
/// - **위치**: 띠가 길에 걸쳤거나, 길 쪽 변이 도로 가장자리에서 [maxSnap]m
///   안으로 떠 있으면 가장자리에 딱 붙인다. 그보다 멀면 길가 주차칸이 아니니
///   옮기지 않는다.
StallStrip alignStallStrip(
  StallStrip s,
  List<RoadLine> roads, {
  double maxAngle = 15 * math.pi / 180,
  double reach = 25,
  double maxSnap = 3,
}) {
  double? bestDist;
  var bestTurn = 0.0;
  var bestSigned = 0.0; // 띠 중심이 도로 중심선에서 떨어진 거리(부호 = 어느 쪽)
  var bestNx = 0.0, bestNy = 0.0;
  var bestHalf = 0.0;
  var bestBeside = false;
  for (final r in roads) {
    for (var i = 0; i + 1 < r.points.length; i++) {
      final (ax, ay) = r.points[i];
      final (bx, by) = r.points[i + 1];
      final dx = bx - ax, dy = by - ay;
      final segLen = math.sqrt(dx * dx + dy * dy);
      if (segLen < 1) continue;
      final turn = lineAngleDiff(s.ang, math.atan2(dy, dx));
      if (turn.abs() > maxAngle) continue;
      final tx = dx / segLen, ty = dy / segLen;
      final along = (s.cx - ax) * tx + (s.cy - ay) * ty;
      final t = along.clamp(0.0, segLen);
      final qx = ax + tx * t, qy = ay + ty * t;
      final dist = math.sqrt(
        (s.cx - qx) * (s.cx - qx) + (s.cy - qy) * (s.cy - qy),
      );
      if (dist > reach) continue;
      if (bestDist != null && dist >= bestDist) continue;
      bestDist = dist;
      bestTurn = turn;
      bestNx = -ty;
      bestNy = tx;
      bestSigned = (s.cx - ax) * bestNx + (s.cy - ay) * bestNy;
      bestHalf = r.halfWidth;
      // 띠가 이 구간 옆에 놓여 있어야(구간 끝 너머가 아니라) 가장자리에 붙인다.
      bestBeside = along > -s.len / 2 && along < segLen + s.len / 2;
    }
  }
  if (bestDist == null) return s;

  var cx = s.cx, cy = s.cy;
  final target = bestHalf + s.wid / 2;
  final off = bestSigned.abs();
  // 길에 걸친 띠는 얼마나 걸쳤든 밀어낸다 — 차도 위의 주차칸은 언제나 틀렸다.
  if (bestBeside && off > 0.3 && (off < target || off - target <= maxSnap)) {
    final move = (bestSigned > 0 ? target : -target) - bestSigned;
    cx += bestNx * move;
    cy += bestNy * move;
  }
  return (cx: cx, cy: cy, len: s.len, wid: s.wid, ang: s.ang + bestTurn);
}

/// 마주 보는 두 줄 주차칸 사이의 **통로**(띠와 같은 꼴의 직사각형).
///
/// 캡처의 큰 주차장은 통로를 가운데 두고 주차칸 두 줄이 마주 본다. 그 통로는
/// OSM에 없는 경우가 많아, 그리지 않으면 주차칸 두 줄이 맨바닥에 떠 보인다.
/// 나란하고([maxAngle]) 사이가 차 한두 대 지나갈 폭([minGap]~[maxGap]m)이며
/// 길이 방향으로 겹치는 두 띠 사이를 통로로 본다. 길이는 두 띠를 합친 범위다.
List<StallStrip> stallAisles(
  List<StallStrip> strips, {
  double maxAngle = 6 * math.pi / 180,
  double minGap = 3,
  double maxGap = 9,
}) {
  final out = <StallStrip>[];
  for (var i = 0; i < strips.length; i++) {
    final a = strips[i];
    final c = math.cos(a.ang), s = math.sin(a.ang);
    for (var j = i + 1; j < strips.length; j++) {
      final b = strips[j];
      if (lineAngleDiff(a.ang, b.ang).abs() > maxAngle) continue;
      final dx = b.cx - a.cx, dy = b.cy - a.cy;
      final du = dx * c + dy * s, dv = -dx * s + dy * c;
      final gap = dv.abs() - (a.wid + b.wid) / 2;
      if (gap < minGap || gap > maxGap) continue;
      final lo = math.max(-a.len / 2, du - b.len / 2);
      final hi = math.min(a.len / 2, du + b.len / 2);
      if (hi - lo < math.min(5.0, math.min(a.len, b.len) / 2)) continue;
      final u0 = math.min(-a.len / 2, du - b.len / 2);
      final u1 = math.max(a.len / 2, du + b.len / 2);
      final um = (u0 + u1) / 2;
      // 통로의 가운데: 두 띠의 마주 보는 변 사이 한가운데.
      final vm = dv.sign * (a.wid / 2 + gap / 2);
      out.add((
        cx: a.cx + um * c - vm * s,
        cy: a.cy + um * s + vm * c,
        len: u1 - u0,
        wid: gap,
        ang: a.ang,
      ));
    }
  }
  return out;
}

/// 띠 전부를 맞춘다(마지막에 [mergeOverlappingStrips]·[trimStripOverlaps]로
/// 겹친 띠를 정리하므로 개수·순서·길이가 달라진다). 먼저 띠마다 [alignStallStrip]으로 도로에 맞추고, 맞출
/// 도로가 없던 띠(차도에서 떨어진 주차장 안쪽)는 [neighbor]m 안에서 가장
/// 가까운 **맞춰진 띠**와 [maxAngle] 안으로 나란하면 그 방향을 따른다 —
/// 같은 주차장의 줄들이 서로 몇 도씩 어긋나 보이지 않게.
List<StallStrip> alignStallStrips(
  List<StallStrip> strips,
  List<RoadLine> roads, {
  double neighbor = 40,
  double maxAngle = 10 * math.pi / 180,
}) {
  final out = [for (final s in strips) alignStallStrip(s, roads)];
  final anchored = [for (var i = 0; i < strips.length; i++) out[i] != strips[i]];
  for (var i = 0; i < out.length; i++) {
    if (anchored[i]) continue;
    final s = out[i];
    double? best;
    var turn = 0.0;
    for (var j = 0; j < out.length; j++) {
      if (!anchored[j]) continue;
      final o = out[j];
      final d = math.sqrt(
        (o.cx - s.cx) * (o.cx - s.cx) + (o.cy - s.cy) * (o.cy - s.cy),
      );
      if (d > neighbor || (best != null && d >= best)) continue;
      final t = lineAngleDiff(s.ang, o.ang);
      if (t.abs() > maxAngle) continue;
      best = d;
      turn = t;
    }
    if (best != null) {
      out[i] = (cx: s.cx, cy: s.cy, len: s.len, wid: s.wid, ang: s.ang + turn);
    }
  }
  return trimStripOverlaps(mergeOverlappingStrips(out), roads);
}

/// 겹쳐 그려지는 띠를 정리한다.
///
/// 한 줄이 토막 나 잡힌 띠들은 같은 도로 가장자리에 붙이고 나면 서로 겹친다
/// (사다리 가로대가 엇갈려 지저분하다).
/// - **나란히 겹친 것**(방향 차 [maxAngle] 안, 옆으로 반 폭 안, 길이 방향으로
///   겹침): 긴 쪽의 줄에 맞춰 하나로 잇는다.
/// - **엇갈려 겹친 것**: 짧은 띠의 중심이 긴 띠 안에 있으면 짧은 쪽을 뺀다.
///   모서리에서 끝만 맞닿은 두 줄은 그대로 둔다.
List<StallStrip> mergeOverlappingStrips(
  List<StallStrip> strips, {
  double maxAngle = 4 * math.pi / 180,
}) {
  // 긴 것부터 — 긴 띠가 기준이 된다.
  final list = [...strips]..sort((a, b) => b.len.compareTo(a.len));
  var changed = true;
  while (changed) {
    changed = false;
    outer:
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      final c = math.cos(a.ang), s = math.sin(a.ang);
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        final dx = b.cx - a.cx, dy = b.cy - a.cy;
        final du = dx * c + dy * s, dv = -dx * s + dy * c;
        if (lineAngleDiff(a.ang, b.ang).abs() <= maxAngle) {
          if (dv.abs() > math.min(a.wid, b.wid) / 2) continue;
          final lo = math.max(-a.len / 2, du - b.len / 2);
          final hi = math.min(a.len / 2, du + b.len / 2);
          if (hi <= lo) continue;
          final u0 = math.min(-a.len / 2, du - b.len / 2);
          final u1 = math.max(a.len / 2, du + b.len / 2);
          final um = (u0 + u1) / 2;
          // 폭도 둘을 합친 범위로 — 폭만 키우고 중심을 그대로 두면 도로 쪽으로
          // 삐져나온다(둘 다 같은 가장자리에 붙어 있으니 합쳐도 그 변은 그대로다).
          final v0 = math.min(-a.wid / 2, dv - b.wid / 2);
          final v1 = math.max(a.wid / 2, dv + b.wid / 2);
          final vm = (v0 + v1) / 2;
          list[i] = (
            cx: a.cx + um * c - vm * s,
            cy: a.cy + um * s + vm * c,
            len: u1 - u0,
            wid: v1 - v0,
            ang: a.ang,
          );
          list.removeAt(j);
        } else {
          if (du.abs() > a.len / 2 || dv.abs() > a.wid / 2) continue;
          list.removeAt(j);
        }
        changed = true;
        break outer;
      }
    }
  }
  return list;
}

/// 띠의 양 끝이 [blocked]인 자리(다른 띠 안·가로지르는 도로 위)에 들어가
/// 있으면 그만큼 끝을 줄인 띠. 끝 변의 세 점(가운데와 양옆)으로 본다.
/// 길이의 절반 넘게 줄여야 하면 손대지 않는다(끝이 아니라 통째로 걸친 것).
StallStrip trimStripEnds(
  StallStrip s,
  bool Function(double x, double y) blocked, {
  double step = 0.25,
}) {
  final c = math.cos(s.ang), sn = math.sin(s.ang);
  bool hit(double u) {
    for (final v in [0.0, s.wid / 3, -s.wid / 3]) {
      if (blocked(s.cx + u * c - v * sn, s.cy + u * sn + v * c)) return true;
    }
    return false;
  }

  var u0 = -s.len / 2, u1 = s.len / 2;
  final limit = s.len / 2;
  while (u1 - u0 > limit && hit(u0)) {
    u0 += step;
  }
  while (u1 - u0 > limit && hit(u1)) {
    u1 -= step;
  }
  if (u1 - u0 <= limit) return s;
  if (u0 == -s.len / 2 && u1 == s.len / 2) return s;
  final um = (u0 + u1) / 2;
  return (cx: s.cx + um * c, cy: s.cy + um * sn, len: u1 - u0, wid: s.wid, ang: s.ang);
}

bool _inStrip(StallStrip a, double x, double y) {
  final c = math.cos(a.ang), s = math.sin(a.ang);
  final dx = x - a.cx, dy = y - a.cy;
  return (dx * c + dy * s).abs() <= a.len / 2 &&
      (-dx * s + dy * c).abs() <= a.wid / 2;
}

bool _onRoad(List<RoadLine> roads, double x, double y) {
  for (final r in roads) {
    for (var i = 0; i + 1 < r.points.length; i++) {
      final (ax, ay) = r.points[i];
      final (bx, by) = r.points[i + 1];
      final dx = bx - ax, dy = by - ay;
      final l2 = dx * dx + dy * dy;
      if (l2 < 1e-9) continue;
      final t = (((x - ax) * dx + (y - ay) * dy) / l2).clamp(0.0, 1.0);
      final qx = ax + dx * t - x, qy = ay + dy * t - y;
      // 가장자리에 딱 붙인 띠가 제 도로에 걸리지 않게 한 뼘 여유.
      if (qx * qx + qy * qy < (r.halfWidth - 0.2) * (r.halfWidth - 0.2)) return true;
    }
  }
  return false;
}

/// 모서리에서 만나는 줄들의 끝과, 가로지르는 도로 위로 나온 끝을 다듬는다.
/// 긴 띠는 그대로 두고 짧은 띠의 끝만 줄인다.
List<StallStrip> trimStripOverlaps(List<StallStrip> strips, List<RoadLine> roads) {
  final list = [...strips]..sort((a, b) => b.len.compareTo(a.len));
  for (var i = 0; i < list.length; i++) {
    list[i] = trimStripEnds(list[i], (x, y) {
      if (_onRoad(roads, x, y)) return true;
      for (var j = 0; j < i; j++) {
        if (_inStrip(list[j], x, y)) return true;
      }
      return false;
    });
  }
  return list;
}

/// 횡단보도 — 중심, 줄무늬 하나의 길이([wid]), 줄무늬가 늘어선 길이([len]),
/// 늘어선 방향([angDeg], 도). 앱의 `BaseCrosswalk`와 같은 뜻이다.
typedef Crosswalk = ({double cx, double cy, double wid, double len, double angDeg});

/// 횡단보도를 도로에 맞춘다. 차도 위가 아니면 null(그리지 않는다).
///
/// 캡처에서 뽑은 횡단보도는 방향이 0°/90°뿐이라 비스듬한 교내 도로와
/// 어긋나고, 절반은 계단·주차선 같은 줄무늬를 잘못 읽은 것이라 길도 아닌
/// 맨바닥에 떠 있다. 중심이 차도 가장자리에서 [slack]m 안에 있는 것만 남겨,
/// 도로 중심선 위로 옮기고 **도로를 가로질러** 줄무늬가 늘어서게 한다 —
/// 줄무늬 하나는 도로와 나란히 [barLength]m, 늘어선 길이는 그려지는 도로 폭.
Crosswalk? snapCrosswalk(
  Crosswalk c,
  List<RoadLine> roads, {
  double slack = 1.5,
  double barLength = 3,
}) {
  double? best;
  Crosswalk? out;
  for (final r in roads) {
    for (var i = 0; i + 1 < r.points.length; i++) {
      final (ax, ay) = r.points[i];
      final (bx, by) = r.points[i + 1];
      final dx = bx - ax, dy = by - ay;
      final l2 = dx * dx + dy * dy;
      if (l2 < 1) continue;
      final t = (((c.cx - ax) * dx + (c.cy - ay) * dy) / l2).clamp(0.0, 1.0);
      final qx = ax + dx * t, qy = ay + dy * t;
      final d = math.sqrt((c.cx - qx) * (c.cx - qx) + (c.cy - qy) * (c.cy - qy));
      if (d > r.halfWidth + slack || (best != null && d >= best)) continue;
      best = d;
      out = (
        cx: qx,
        cy: qy,
        wid: barLength,
        len: r.halfWidth * 2,
        // 줄무늬는 도로를 가로질러 늘어선다 = 도로 방향에 수직.
        angDeg: math.atan2(dy, dx) * 180 / math.pi + 90,
      );
    }
  }
  return out;
}

/// 횡단보도 전부를 [snapCrosswalk]로 맞추고, 같은 자리에 겹친 것([minGap]m
/// 안)은 하나만 남긴다.
List<Crosswalk> snapCrosswalks(
  List<Crosswalk> list,
  List<RoadLine> roads, {
  double minGap = 6,
}) {
  final out = <Crosswalk>[];
  for (final c in list) {
    final s = snapCrosswalk(c, roads);
    if (s == null) continue;
    if (out.any((o) =>
        (o.cx - s.cx) * (o.cx - s.cx) + (o.cy - s.cy) * (o.cy - s.cy) <
        minGap * minGap)) {
      continue;
    }
    out.add(s);
  }
  return out;
}

/// 코트 위에 놓인 띠를 뺀다 — 코트 바닥의 선이 주차 사다리처럼 잡힌 것이다.
/// [courts]는 코트 직사각형(띠와 같은 꼴). 띠의 중심이 코트 안이면 뺀다.
List<StallStrip> dropStripsOnCourts(List<StallStrip> strips, List<StallStrip> courts) => [
      for (final s in strips)
        if (!courts.any((c) => _inStrip(c, s.cx, s.cy))) s,
    ];
