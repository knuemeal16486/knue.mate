// 건물 폴리곤의 겹침·모양 이상을 찾아낸다.
import 'dart:io';
import 'dart:math' as math;
import 'traced_json.dart';

double area(List<List<double>> r) {
  var s = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s.abs() / 2;
}

void main() {
  final B = buildingRings(loadTraced());
  stdout.writeln('건물 ${B.length}동');

  // 0.25m 격자에 라벨을 찍어 겹친 칸 세기
  const cell = 0.25;
  var mnx = 1e9, mny = 1e9, mxx = -1e9, mxy = -1e9;
  for (final r in B) {
    for (final p in r) {
      mnx = math.min(mnx, p[0]);
      mxx = math.max(mxx, p[0]);
      mny = math.min(mny, p[1]);
      mxy = math.max(mxy, p[1]);
    }
  }
  final w = ((mxx - mnx) / cell).ceil() + 2, h = ((mxy - mny) / cell).ceil() + 2;
  final owner = List<int>.filled(w * h, -1);
  final dupWith = <String, int>{};
  var painted = 0, dup = 0;
  for (var bi = 0; bi < B.length; bi++) {
    final r = B[bi];
    for (var j = 0; j < h; j++) {
      final yw = mny + j * cell;
      final xs = <double>[];
      for (var i = 0; i < r.length; i++) {
        final a = r[i], b = r[(i + 1) % r.length];
        if ((a[1] <= yw) != (b[1] <= yw)) {
          xs.add(a[0] + (yw - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        for (var i = ((xs[k] - mnx) / cell).ceil();
            i <= ((xs[k + 1] - mnx) / cell).floor();
            i++) {
          if (i < 0 || i >= w) continue;
          painted++;
          final idx = j * w + i;
          if (owner[idx] >= 0) {
            dup++;
            final key = '${math.min(owner[idx], bi)}-${math.max(owner[idx], bi)}';
            dupWith[key] = (dupWith[key] ?? 0) + 1;
          } else {
            owner[idx] = bi;
          }
        }
      }
    }
  }
  stdout.writeln('겹친 칸 $dup / $painted = '
      '${(dup * 100 / painted).toStringAsFixed(2)}%  '
      '(${(dup * cell * cell).round()}㎡)');
  final worst = dupWith.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('--- 많이 겹친 짝 (면적 ㎡) ---');
  for (final e in worst.take(12)) {
    final ix = e.key.split('-').map(int.parse).toList();
    stdout.writeln('  ${ix[0]}번↔${ix[1]}번  ${(e.value * cell * cell).round()}㎡'
        ' (각 ${area(B[ix[0]]).round()}, ${area(B[ix[1]]).round()}㎡)');
  }

  // 모양 이상: 볼록껍질 대비 채움률이 낮거나, 둘레²/면적이 큰 것
  stdout.writeln('--- 모양이 이상한 동 (둘레²/면적, 낮을수록 단정) ---');
  final bad = <List<dynamic>>[];
  for (var i = 0; i < B.length; i++) {
    final r = B[i];
    var per = 0.0;
    for (var k = 0; k < r.length; k++) {
      final a = r[k], b = r[(k + 1) % r.length];
      per += math.sqrt(math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2));
    }
    final a2 = area(r);
    bad.add([i, per * per / a2, a2.round(), r.length]);
  }
  bad.sort((x, y) => (y[1] as double).compareTo(x[1] as double));
  for (final b in bad.take(12)) {
    stdout.writeln('  ${b[0]}번  지수 ${(b[1] as double).toStringAsFixed(1)}'
        '  ${b[2]}㎡  점${b[3]}');
  }
}
