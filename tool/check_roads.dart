// 도로 경계가 얼마나 구불구불한지 잰다.
//
// 앞서 두 번 헛짚었다. 총 회전량은 길그물이 막다른 길마다 정당하게 180° 도는
// 걸 못 걸러내고, 국소 편차는 단순화 뒤 변이 길어져 창보다 커지면 무너진다.
//
// 굽이의 본질은 **작은 각도로 좌우 번갈아 꺾이는 것**이다. 진짜 곡선은 한
// 방향으로 꾸준히 돌고, 진짜 모서리는 크게 한 번 꺾인다. 그래서 잰다:
//   지그재그율 = (이웃한 두 꺾임의 방향이 반대이고 둘 다 작은) 비율
import 'dart:io';
import 'dart:math' as math;
import 'traced_json.dart';

double _turn(List<double> a, List<double> b, List<double> c) {
  final v1x = b[0] - a[0], v1y = b[1] - a[1];
  final v2x = c[0] - b[0], v2y = c[1] - b[1];
  final l1 = math.sqrt(v1x * v1x + v1y * v1y);
  final l2 = math.sqrt(v2x * v2x + v2y * v2y);
  if (l1 < 1e-6 || l2 < 1e-6) return 0;
  final cross = (v1x * v2y - v1y * v2x) / (l1 * l2);
  final dot = ((v1x * v2x + v1y * v2y) / (l1 * l2)).clamp(-1.0, 1.0);
  return math.atan2(cross, dot) * 180 / math.pi; // 부호 있는 꺾임
}

void main(List<String> args) {
  final t = loadTraced();
  final pv = t['pavement'] as Map<String, dynamic>;
  final rings = [...asRings(pv['outer']), ...asRings(pv['holes'])];
  var zig = 0, pairs = 0, pts = 0;
  var perim = 0.0;
  final lens = <double>[];
  for (final r in rings) {
    if (r.length < 8) continue;
    var len = 0.0;
    for (var i = 0; i < r.length; i++) {
      final j = (i + 1) % r.length;
      final d = math.sqrt(
          math.pow(r[j][0] - r[i][0], 2) + math.pow(r[j][1] - r[i][1], 2));
      len += d;
      lens.add(d);
    }
    if (len < 40) continue;
    perim += len;
    pts += r.length;
    final turns = [
      for (var i = 0; i < r.length; i++)
        _turn(r[(i - 1 + r.length) % r.length], r[i], r[(i + 1) % r.length])
    ];
    for (var i = 0; i < turns.length; i++) {
      final a = turns[i], b = turns[(i + 1) % turns.length];
      if (a.abs() < 1 || b.abs() < 1) continue;
      pairs++;
      // 방향이 반대이고 둘 다 45° 미만이면 지그재그다
      if (a * b < 0 && a.abs() < 45 && b.abs() < 45) zig++;
    }
  }
  lens.sort();
  stdout.writeln('40m 이상 고리의 점 $pts, 둘레 ${perim.round()}m, '
      '변 중앙길이 ${lens[lens.length ~/ 2].toStringAsFixed(1)}m');
  stdout.writeln('지그재그율 ${(zig * 100 / pairs).toStringAsFixed(1)}%'
      '   (낮을수록 곧다)');
}
