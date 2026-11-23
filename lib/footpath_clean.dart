// 캡처에서 뜬 샛길(가는 길의 가운데 선)을 다듬는다. 순수 Dart —
// `tool/trace_map.dart`와 테스트가 같이 쓴다.
//
// 샛길은 "포장면 중 가는 부분 − OSM 길이 덮는 자리"의 뼈대라서 세 가지 흠이
// 생긴다.
//  1. **OSM 길의 그림자**: OSM 보행로와 캡처의 길이 몇 m 어긋나 있으면, 덮이지
//     않고 남은 가장자리가 그 길 옆에 나란히 뜬 조각이 된다(같은 길이 두 번).
//  2. **끊김**: 번짐·이름표에 가려 한 길이 여러 토막으로 잡힌다.
//  3. **부스러기**: 어디에도 닿지 않는 짧은 토막.
import 'dart:math' as math;

import 'stall_align.dart' show RoadLine, lineAngleDiff;

typedef PathPoint = (double, double);

double _dist(PathPoint a, PathPoint b) =>
    math.sqrt((a.$1 - b.$1) * (a.$1 - b.$1) + (a.$2 - b.$2) * (a.$2 - b.$2));

/// 꺾은선의 길이(m).
double polylineLength(List<PathPoint> line) {
  var len = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    len += _dist(line[i], line[i + 1]);
  }
  return len;
}

/// [line] 길이 가운데, 어느 도로 옆에 **나란히** 붙어 가는 몫(0~1).
///
/// 구간의 가운데가 도로 가장자리에서 [within]m 안이고 방향 차가 [maxAngle]
/// 안이면 그 구간은 그 도로의 그림자다.
double roadShadowFraction(
  List<PathPoint> line,
  List<RoadLine> roads, {
  double within = 8,
  double maxAngle = 30 * math.pi / 180,
}) {
  var total = 0.0, shadow = 0.0;
  for (var i = 0; i + 1 < line.length; i++) {
    final a = line[i], b = line[i + 1];
    final len = _dist(a, b);
    if (len < 1e-6) continue;
    total += len;
    final mx = (a.$1 + b.$1) / 2, my = (a.$2 + b.$2) / 2;
    final ang = math.atan2(b.$2 - a.$2, b.$1 - a.$1);
    var hit = false;
    for (final r in roads) {
      for (var k = 0; k + 1 < r.points.length && !hit; k++) {
        final (px, py) = r.points[k];
        final (qx, qy) = r.points[k + 1];
        final dx = qx - px, dy = qy - py;
        final l2 = dx * dx + dy * dy;
        if (l2 < 1e-6) continue;
        if (lineAngleDiff(ang, math.atan2(dy, dx)).abs() > maxAngle) continue;
        final t = (((mx - px) * dx + (my - py) * dy) / l2).clamp(0.0, 1.0);
        final ex = px + dx * t - mx, ey = py + dy * t - my;
        if (math.sqrt(ex * ex + ey * ey) <= r.halfWidth + within) hit = true;
      }
      if (hit) break;
    }
    if (hit) shadow += len;
  }
  return total == 0 ? 0 : shadow / total;
}

/// OSM 길의 그림자인 샛길을 뺀다([roadShadowFraction]이 [fraction] 이상).
List<List<PathPoint>> dropRoadShadows(
  List<List<PathPoint>> lines,
  List<RoadLine> roads, {
  double within = 8,
  double fraction = 0.6,
}) =>
    [
      for (final l in lines)
        if (roadShadowFraction(l, roads, within: within) < fraction) l,
    ];

/// 끝과 끝이 [maxGap]m 안으로 마주 본 토막들을 한 줄로 잇는다.
///
/// 잇는 선이 양쪽 토막의 끝 방향에서 [maxTurn] 넘게 꺾이면 잇지 않는다 —
/// 나란히 지나가는 다른 길이나 갈림길의 곁가지를 억지로 붙이지 않으려고.
/// 가장 가까운 짝부터 이어 나간다.
List<List<PathPoint>> joinPolylines(
  List<List<PathPoint>> lines, {
  double maxGap = 8,
  double maxTurn = 50 * math.pi / 180,
}) {
  final list = [
    for (final l in lines)
      if (l.length >= 2) [...l],
  ];

  // 줄 [l]의 끝([atEnd]면 마지막 점)에서 바깥으로 나가는 방향.
  double outward(List<PathPoint> l, bool atEnd) {
    final a = atEnd ? l[l.length - 2] : l[1];
    final b = atEnd ? l.last : l.first;
    return math.atan2(b.$2 - a.$2, b.$1 - a.$1);
  }

  double turn(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    return d.abs();
  }

  while (true) {
    double? best;
    var bi = -1, bj = -1;
    var bEndI = false, bEndJ = false;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        for (final endI in [false, true]) {
          for (final endJ in [false, true]) {
            final p = endI ? list[i].last : list[i].first;
            final q = endJ ? list[j].last : list[j].first;
            final gap = _dist(p, q);
            if (gap > maxGap || (best != null && gap >= best)) continue;
            if (gap > 0.5) {
              final bridge = math.atan2(q.$2 - p.$2, q.$1 - p.$1);
              if (turn(outward(list[i], endI), bridge) > maxTurn) continue;
              if (turn(outward(list[j], endJ), bridge + math.pi) > maxTurn) continue;
            }
            best = gap;
            bi = i;
            bj = j;
            bEndI = endI;
            bEndJ = endJ;
          }
        }
      }
    }
    if (best == null) return list;
    // i의 끝 → j의 처음 순서가 되게 뒤집어 붙인다.
    final a = bEndI ? list[bi] : list[bi].reversed.toList();
    final b = bEndJ ? list[bj].reversed.toList() : list[bj];
    list[bi] = [...a, ...b];
    list.removeAt(bj);
  }
}

/// 어디에도 닿지 않는 짧은 토막을 뺀다.
///
/// [minLength]m보다 짧고, 두 끝 모두 [anchored](도로·포장면 가까이)가 아니며
/// 다른 샛길에서 [near]m 안에도 없으면 부스러기다.
List<List<PathPoint>> dropIsolatedPaths(
  List<List<PathPoint>> lines, {
  required bool Function(double x, double y) anchored,
  double minLength = 30,
  double near = 4,
}) {
  bool touchesOther(int self, PathPoint p) {
    for (var j = 0; j < lines.length; j++) {
      if (j == self) continue;
      for (final q in lines[j]) {
        if (_dist(p, q) <= near) return true;
      }
    }
    return false;
  }

  return [
    for (var i = 0; i < lines.length; i++)
      if (polylineLength(lines[i]) >= minLength ||
          [lines[i].first, lines[i].last].any(
            (p) => anchored(p.$1, p.$2) || touchesOther(i, p),
          ))
        lines[i],
  ];
}
