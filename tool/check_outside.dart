// 부지 밖 건물 추출률을 잰다. VWorld 건물 중 캡처가 덮는 자리에 있는 것들이
// 얼마나 사진에서도 잡혔는지 본다. (VWorld는 검증용 — 정답은 사진이다)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'traced_json.dart';

const s = 0.619;
const shots = {
  'core.jpg': [-201.2, -215.0, 1793.0, 843.0],
  'north.png': [-236.5, -712.5, 1611.0, 842.0],
  'south.png': [-116.8, 163.5, 1759.0, 839.0],
};

bool covered(double x, double y) {
  for (final t in shots.values) {
    if (x >= t[0] && x <= t[0] + t[2] * s && y >= t[1] && y <= t[1] + t[3] * s) {
      return true;
    }
  }
  return false;
}

List<double> center(List r) {
  var a = 1e9, b = -1e9, c = 1e9, d = -1e9;
  for (final p in r) {
    a = math.min(a, (p[0] as num).toDouble());
    b = math.max(b, (p[0] as num).toDouble());
    c = math.min(c, (p[1] as num).toDouble());
    d = math.max(d, (p[1] as num).toDouble());
  }
  return [(a + b) / 2, (c + d) / 2];
}

bool pip(List ring, double x, double y) {
  var t = false;
  for (var i = 0, k = ring.length - 1; i < ring.length; k = i++) {
    final ax = (ring[i][0] as num).toDouble(), ay = (ring[i][1] as num).toDouble();
    final bx = (ring[k][0] as num).toDouble(), by = (ring[k][1] as num).toDouble();
    if ((ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax) t = !t;
  }
  return t;
}

void main() {
  final base = jsonDecode(File('assets/housing/campus_base.json').readAsStringSync());
  final side = jsonDecode(File('tool/mapsrc/outline.json').readAsStringSync());
  final outline = side['outline'][0];
  final traced = [for (final r in buildingRings(loadTraced())) center(r)];

  var target = 0, hit = 0;
  final missZones = <String, int>{};
  for (final b in base['buildings']) {
    final c = center(b['ring']);
    if (!covered(c[0], c[1])) continue;
    if (pip(outline, c[0], c[1])) continue; // 부지 안은 따로 검증했다
    target++;
    var best = 1e9;
    for (final t in traced) {
      final d = math.sqrt(math.pow(t[0] - c[0], 2) + math.pow(t[1] - c[1], 2));
      if (d < best) best = d;
    }
    if (best <= 12) {
      hit++;
    } else {
      // 어느 구역에서 놓쳤는지 20x20 격자로 센다
      final k = '${(c[0] / 100).floor() * 100},${(c[1] / 100).floor() * 100}';
      missZones[k] = (missZones[k] ?? 0) + 1;
    }
  }
  stdout.writeln('캡처가 덮는 부지 밖 VWorld 건물 $target동 중 '
      '사진에서도 잡힌 것 $hit동 (${(hit * 100 / target).toStringAsFixed(0)}%)');
  final z = missZones.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('놓친 곳 (100m 격자 좌표 → 동수):');
  for (final e in z.take(12)) {
    stdout.writeln('  (${e.key})  ${e.value}동');
  }
}
